from fastapi import FastAPI, WebSocket, Request, HTTPException, Form
import asyncio
import cv2
import numpy as np
from fastapi import FastAPI, WebSocket, Request, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, StreamingResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import json
import logging
import base64
import os
import time
from datetime import datetime
from pathlib import Path
import threading
import io
from PIL import Image
from iot_client import get_iot_client
from line_messaging import LineMessagingAPI

# ログ設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="防犯カメラシステム - カメラ側")

# CORS設定を追加
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 本番環境では特定のオリジンのみを許可
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 録画ディレクトリの作成
RECORDINGS_DIR = Path("recordings")
RECORDINGS_DIR.mkdir(exist_ok=True)

# サムネイルディレクトリの作成
THUMBNAILS_DIR = Path("thumbnails")
THUMBNAILS_DIR.mkdir(exist_ok=True)

# LINE Messaging API設定
LINE_CHANNEL_ACCESS_TOKEN = os.getenv("LINE_CHANNEL_ACCESS_TOKEN")
line_messaging = LineMessagingAPI(LINE_CHANNEL_ACCESS_TOKEN)


def generate_thumbnail(video_path: Path, thumbnail_path: Path, time_position: float = None):
    """動画からサムネイルを生成（デフォルトで中間フレーム）"""
    try:
        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            logger.error(f"動画ファイルを開けません: {video_path}")
            return False

        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = cap.get(cv2.CAP_PROP_FPS)

        if total_frames == 0 or fps == 0:
            logger.error(f"動画情報が取得できません: {video_path}")
            cap.release()
            return False

        # time_positionが指定されていなければ動画の中間秒数を使う
        if time_position is None:
            duration = total_frames / fps
            time_position = duration / 2

        target_frame = int(time_position * fps)
        target_frame = min(target_frame, total_frames - 1)
        target_frame = max(target_frame, 0)

        cap.set(cv2.CAP_PROP_POS_FRAMES, target_frame)
        ret, frame = cap.read()
        cap.release()

        if not ret:
            logger.error(f"フレームの読み込みに失敗: {video_path}")
            return False

        height, width = frame.shape[:2]
        thumbnail_width = 320
        thumbnail_height = int(height * thumbnail_width / width)
        frame = cv2.resize(frame, (thumbnail_width, thumbnail_height))
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        pil_image = Image.fromarray(frame_rgb)
        pil_image.save(thumbnail_path, "JPEG", quality=85)
        logger.info(f"サムネイル生成成功: {thumbnail_path}")
        return True

    except Exception as e:
        logger.error(f"サムネイル生成エラー: {e}")
        return False


class MotionDetector:
    """動き検知クラス"""

    def __init__(self, threshold=35, min_area=2000):
        self.threshold = threshold
        self.min_area = min_area
        self.prev_frame = None
        self.motion_detected = False
        self.motion_start_time = None
        self.motion_end_time = None
        self.motion_cooldown = 3.0  # 動きがなくなってから3秒後に録画停止
        self.initialization_frames = 0  # 初期化フレーム数
        self.required_init_frames = 10  # 初期化に必要なフレーム数（5から10に増加）

    def detect_motion(self, frame):
        """動きを検知"""
        # 初期化期間中は動き検知を無効化
        if self.initialization_frames < self.required_init_frames:
            self.initialization_frames += 1
            if self.initialization_frames == self.required_init_frames:
                # 初期化完了時に最初のフレームを設定
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                gray = cv2.GaussianBlur(gray, (21, 21), 0)
                self.prev_frame = gray
                logger.info("動き検知の初期化が完了しました")
            return False

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (21, 21), 0)

        if self.prev_frame is None:
            self.prev_frame = gray
            return False

        # フレーム差分を計算
        frame_delta = cv2.absdiff(self.prev_frame, gray)
        thresh = cv2.threshold(frame_delta, self.threshold,
                               255, cv2.THRESH_BINARY)[1]

        # ノイズを除去（より強力なモルフォロジー処理）
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        thresh = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        thresh = cv2.dilate(thresh, None, iterations=3)
        thresh = cv2.erode(thresh, None, iterations=1)

        contours, _ = cv2.findContours(
            thresh.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        # 動きの検知（より厳密な条件）
        motion_detected = False
        total_motion_area = 0

        for contour in contours:
            area = cv2.contourArea(contour)
            if area > self.min_area:
                # 輪郭の長方形を取得
                x, y, w, h = cv2.boundingRect(contour)
                aspect_ratio = w / h if h > 0 else 0

                # 小さすぎる動きや細すぎる動きを除外
                if area > self.min_area and w > 50 and h > 50 and 0.2 < aspect_ratio < 5.0:
                    total_motion_area += area
                    motion_detected = True

        # 総動き面積が一定以上の場合のみ動きとみなす
        if total_motion_area < self.min_area * 2:
            motion_detected = False

        # 動きの状態を更新
        if motion_detected and not self.motion_detected:
            # 動き開始
            self.motion_detected = True
            self.motion_start_time = time.time()
            logger.info(f"動きを検知しました - 録画開始 (面積: {total_motion_area:.0f}px)")

            # 動体検知通知は無効化（録画完了通知のみ）
            # if line_messaging.enabled:
            #     # 現在のフレームを画像として保存して送信
            #     timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            #     image_filename = f"motion_detected_{timestamp}.jpg"
            #     image_path = RECORDINGS_DIR / image_filename

            #     # フレームを画像として保存
            #     cv2.imwrite(str(image_path), frame)

            #     # LINE通知を送信（画像付き）
            #     line_messaging.send_motion_detected_notification(image_path)

        elif not motion_detected and self.motion_detected:
            # 動き終了（クールダウン期間を設定）
            if self.motion_end_time is None:
                self.motion_end_time = time.time()
            elif time.time() - self.motion_end_time > self.motion_cooldown:
                # クールダウン期間が過ぎたら動き終了とみなす
                self.motion_detected = False
                self.motion_start_time = None
                self.motion_end_time = None
                logger.info("動きが終了しました - 録画停止")
        elif motion_detected and self.motion_detected:
            # 動き継続中
            self.motion_end_time = None

        self.prev_frame = gray
        return self.motion_detected


class RecordingManager:
    """録画管理クラス"""

    def __init__(self):
        self.is_recording = False
        self.video_writer = None
        self.recording_start_time = None
        self.recording_path = None
        self.frame_count = 0
        self.target_fps = 30.0
        self.stop_recording_flag = False
        self.server_url = "http://localhost:3000"  # デフォルトURL

    def start_recording(self, frame, camera_fps=30.0):
        """録画開始"""
        if self.is_recording:
            return

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"motion_{timestamp}.mp4"
        self.recording_path = RECORDINGS_DIR / filename

        # 動画エンコーダーを設定
        height, width = frame.shape[:2]

        # 固定フレームレートで録画（等倍再生のため）
        recording_fps = 120.0  # 固定120FPS

        # より安定したコーデック設定（等倍再生のため）
        # まずH.264を試行（最も安定）
        fourcc = cv2.VideoWriter_fourcc(*'H264')
        self.video_writer = cv2.VideoWriter(
            str(self.recording_path),
            fourcc,
            recording_fps,
            (width, height)
        )

        # H.264が利用できない場合はmp4vにフォールバック
        if not self.video_writer.isOpened():
            logger.warning("H.264コーデックが利用できません。mp4vにフォールバックします。")
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            self.video_writer = cv2.VideoWriter(
                str(self.recording_path),
                fourcc,
                recording_fps,
                (width, height)
            )

        # mp4vも利用できない場合はXVIDにフォールバック
        if not self.video_writer.isOpened():
            logger.warning("mp4vコーデックも利用できません。XVIDにフォールバックします。")
            fourcc = cv2.VideoWriter_fourcc(*'XVID')
            self.video_writer = cv2.VideoWriter(
                str(self.recording_path),
                fourcc,
                recording_fps,
                (width, height)
            )

        # XVIDも利用できない場合はMJPGにフォールバック
        if not self.video_writer.isOpened():
            logger.warning("XVIDコーデックも利用できません。MJPGにフォールバックします。")
            fourcc = cv2.VideoWriter_fourcc(*'MJPG')
            self.video_writer = cv2.VideoWriter(
                str(self.recording_path),
                fourcc,
                recording_fps,
                (width, height)
            )

        # 録画開始時のログ
        if self.video_writer.isOpened():
            logger.info(
                f"録画開始: {self.recording_path} (FPS: {recording_fps}, 解像度: {width}x{height})")
        else:
            logger.error("録画開始に失敗しました")
            # 録画エラー通知は無効化（録画完了通知のみ）
            # if line_messaging.enabled:
            #     line_messaging.send_system_error_notification(
            #         "録画開始に失敗しました。動体検知は継続されますが、録画機能が無効です。")

        self.is_recording = True
        self.recording_start_time = time.time()
        self.frame_count = 0
        self.target_fps = 120.0  # 固定120FPS
        self.stop_recording_flag = False
        self.frame_buffer = []  # フレームバッファを追加
        self.last_frame_time = time.time()  # フレームタイミング制御用

        logger.info(f"録画開始: {self.recording_path} (固定FPS: {recording_fps})")

    def add_frame(self, frame):
        """フレームを録画に追加"""
        if self.is_recording and self.video_writer and frame is not None:
            try:
                # 録画フレームに日時を追加
                frame_with_timestamp = frame.copy()
                current_datetime = datetime.now()
                date_str = current_datetime.strftime("%Y/%m/%d")
                time_str = current_datetime.strftime("%H:%M:%S")

                # 日付を表示（左上）
                cv2.putText(frame_with_timestamp, date_str, (10, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
                cv2.putText(frame_with_timestamp, date_str, (10, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 1)

                # 時刻を表示（右上）
                time_x = frame_with_timestamp.shape[1] - 150
                cv2.putText(frame_with_timestamp, time_str, (time_x, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
                cv2.putText(frame_with_timestamp, time_str, (time_x, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 1)

                # 固定間隔でフレームを記録（等倍再生のため）
                current_time = time.time()

                if self.frame_count == 0:
                    # 最初のフレーム
                    self.last_frame_time = current_time
                    self.video_writer.write(frame_with_timestamp)
                    self.frame_count += 1
                else:
                    # 固定間隔でフレームを記録
                    frame_interval = 1.0 / self.target_fps
                    time_since_last = current_time - self.last_frame_time

                    # フレーム間隔が短すぎる場合は待機
                    if time_since_last < frame_interval:
                        sleep_time = frame_interval - time_since_last
                        time.sleep(sleep_time)

                    # フレームを記録
                    self.video_writer.write(frame_with_timestamp)
                    self.frame_count += 1
                    self.last_frame_time = time.time()

                # フレームレートの監視（デバッグ用）
                if self.frame_count % 30 == 0:
                    elapsed_time = current_time - self.recording_start_time
                    if elapsed_time > 0:
                        actual_fps = self.frame_count / elapsed_time
                        logger.info(
                            f"録画FPS: {actual_fps:.1f} (目標: {self.target_fps:.1f})")

            except Exception as e:
                logger.error(f"フレーム書き込みエラー: {e}")

    def stop_recording(self):
        """録画停止"""
        if not self.is_recording:
            return

        self.stop_recording_flag = True
        self.is_recording = False

        if self.video_writer:
            self.video_writer.release()
            self.video_writer = None

        duration = time.time() - self.recording_start_time if self.recording_start_time else 0
        filename = self.recording_path.name if self.recording_path else "unknown"

        # ファイルサイズを取得
        file_size = 0
        if self.recording_path and self.recording_path.exists():
            file_size = self.recording_path.stat().st_size

        logger.info(f"録画停止: {self.recording_path} (長さ: {duration:.1f}秒)")

        # LINE通知を送信
        if line_messaging.enabled:
            line_messaging.send_recording_complete_notification(
                filename, file_size, duration, self.server_url)

        self.recording_start_time = None
        self.recording_path = None
        self.frame_count = 0

    def get_recording_status(self):
        """録画状態を取得"""
        return {
            "is_recording": self.is_recording,
            "recording_path": str(self.recording_path) if self.recording_path else None,
            "duration": time.time() - self.recording_start_time if self.is_recording and self.recording_start_time else 0
        }

    def update_server_url(self, request: Request):
        """サーバーのURLを更新"""
        try:
            # リクエストからホスト情報を取得
            host = request.headers.get("host", "localhost:3000")
            scheme = request.headers.get("x-forwarded-proto", "http")

            # ポート番号を取得
            if ":" in host:
                hostname, port = host.split(":", 1)
            else:
                hostname = host
                port = "3000" if scheme == "http" else "443"

            # URLを構築
            if scheme == "https" and port == "443":
                self.server_url = f"https://{hostname}"
            elif scheme == "http" and port == "80":
                self.server_url = f"http://{hostname}"
            else:
                self.server_url = f"{scheme}://{hostname}:{port}"

            logger.info(f"サーバーURL更新: {self.server_url}")
        except Exception as e:
            logger.error(f"サーバーURL更新エラー: {e}")
            # エラー時はデフォルトURLを使用
            self.server_url = "http://localhost:3000"


# グローバル変数で起動状態を管理
camera_manager = None
is_camera_active = False


class CameraManager:
    """カメラ管理クラス"""

    def __init__(self):
        self.camera = None
        self.motion_detector = MotionDetector()
        self.recording_manager = RecordingManager()
        self.is_initialized = False
        self.frame_thread = None
        self.stop_thread = False
        self.current_frame = None
        self.frame_lock = threading.Lock()
        self.start_time = None  # カメラ起動時間を記録

    def update_server_url(self, request: Request):
        """サーバーのURLを更新"""
        self.recording_manager.update_server_url(request)

    def initialize_camera(self):
        """カメラを初期化"""
        try:
            camera_devices = [0, 1]  # USBカメラのデバイス番号

            for device in camera_devices:
                try:
                    logger.info(f"カメラデバイス {device} を試行中...")
                    self.camera = cv2.VideoCapture(device)

                    if self.camera.isOpened():
                        logger.info(f"カメラデバイス {device} でカメラを開きました")

                        # カメラの設定
                        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                        self.camera.set(cv2.CAP_PROP_FPS, 30)

                        # テストフレームを取得してカメラが正常に動作するか確認
                        ret, test_frame = self.camera.read()
                        if not ret or test_frame is None:
                            logger.warning(f"カメラデバイス {device} でテストフレーム取得失敗")
                            self.camera.release()
                            continue

                        # 実際のフレームレートを取得
                        actual_fps = self.camera.get(cv2.CAP_PROP_FPS)
                        if actual_fps > 0:
                            self.camera_fps = round(actual_fps, 2)
                            logger.info(f"カメラFPS: {self.camera_fps}")
                        else:
                            # FPS取得失敗時は、実際のフレーム取得速度を測定
                            logger.warning("FPS取得失敗、実際のフレーム取得速度を測定します")
                            start_time = time.time()
                            frame_count = 0
                            for _ in range(30):  # 30フレーム取得して速度を測定
                                ret, _ = self.camera.read()
                                if ret:
                                    frame_count += 1
                            elapsed_time = time.time() - start_time
                            if elapsed_time > 0 and frame_count > 0:
                                self.camera_fps = round(
                                    frame_count / elapsed_time, 2)
                                logger.info(f"測定されたカメラFPS: {self.camera_fps}")
                            else:
                                self.camera_fps = 30.0
                                logger.warning(
                                    f"FPS測定失敗、デフォルト値({self.camera_fps})を使用")

                        self.is_initialized = True
                        self.start_time = time.time()  # 起動時間を記録

                        # 動き検知をリセット
                        self.motion_detector.initialization_frames = 0
                        self.motion_detector.prev_frame = None
                        self.motion_detector.motion_detected = False
                        self.motion_detector.motion_start_time = None
                        self.motion_detector.motion_end_time = None

                        logger.info("カメラが正常に初期化されました")
                        return
                    else:
                        logger.warning(f"カメラデバイス {device} を開けませんでした")
                        if self.camera:
                            self.camera.release()
                            self.camera = None
                except Exception as e:
                    logger.warning(f"カメラデバイス {device} でエラー: {e}")
                    if self.camera:
                        self.camera.release()
                        self.camera = None

            # すべてのデバイスで失敗した場合
            logger.error("利用可能なカメラが見つかりませんでした")
            self.camera = None
            self.is_initialized = True  # ダミーフレームモードでも初期化完了とする
            self.camera_fps = 30.0  # デフォルトFPS設定
            self.start_time = time.time()  # 起動時間を記録
            logger.info("ダミーフレームモードで動作します")

            # カメラエラー通知は無効化（録画完了通知のみ）
            # if line_messaging.enabled:
            #     line_messaging.send_system_error_notification(
            #         "利用可能なカメラが見つかりませんでした。ダミーフレームモードで動作します。")

        except Exception as e:
            logger.error(f"カメラ初期化中にエラーが発生しました: {e}")
            self.camera = None
            self.is_initialized = True  # ダミーフレームモードでも初期化完了とする
            self.camera_fps = 30.0  # デフォルトFPS設定
            self.start_time = time.time()  # 起動時間を記録
            logger.info("エラー後ダミーフレームモードで動作します")

            # カメラエラー通知は無効化（録画完了通知のみ）
            # if line_messaging.enabled:
            #     line_messaging.send_system_error_notification(
            #         f"カメラ初期化エラー: {str(e)}")

    def get_frame(self):
        """フレームを取得"""
        if self.camera is None or not self.is_initialized:
            # ダミーフレームを生成
            frame = np.zeros((480, 640, 3), dtype=np.uint8)
            # テキストを描画
            cv2.putText(frame, "No Camera Available", (50, 240),
                        cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
            cv2.putText(frame, "カメラが利用できません", (50, 280),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
            return frame

        try:
            ret, frame = self.camera.read()
            if not ret or frame is None:
                logger.error("フレームを読み取れませんでした")
                # エラー時もダミーフレームを生成
                frame = np.zeros((480, 640, 3), dtype=np.uint8)
                cv2.putText(frame, "Camera Error", (50, 240),
                            cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 0, 0), 2)
                return frame

            # 動き検知
            motion_detected = self.motion_detector.detect_motion(frame)

            # 録画制御（起動後2秒間は録画を無効化、動き検知初期化期間中も無効化）
            current_time = time.time()
            startup_period = 2.0  # 2秒間の起動期間（1秒から2秒に延長）
            is_initialization_period = self.motion_detector.initialization_frames < self.motion_detector.required_init_frames

            # 起動期間または初期化期間中は録画を完全に無効化
            is_recording_disabled = (
                (self.start_time and (current_time - self.start_time) < startup_period) or
                is_initialization_period
            )

            if is_recording_disabled:
                # 録画を強制的に停止
                if self.recording_manager.is_recording:
                    self.recording_manager.stop_recording()
                    if is_initialization_period:
                        logger.info(
                            f"動き検知初期化期間中のため録画を停止しました (進捗: {self.motion_detector.initialization_frames}/{self.motion_detector.required_init_frames})")
                    else:
                        remaining_time = startup_period - \
                            (current_time - self.start_time)
                        logger.info(
                            f"起動期間中のため録画を停止しました (残り: {remaining_time:.1f}秒)")
            else:
                # 初期化完了後は通常の録画制御
                if motion_detected and not self.recording_manager.is_recording:
                    # 固定フレームレートで録画開始
                    self.recording_manager.start_recording(
                        frame, 120.0)  # 固定120FPS
                    logger.info("動きを検知して録画を開始しました (固定120FPS)")
                elif not motion_detected and self.recording_manager.is_recording:
                    self.recording_manager.stop_recording()
                    logger.info("動きが終了して録画を停止しました")

            # 録画中の場合はフレームを録画に追加（無効化期間中は追加しない）
            if self.recording_manager.is_recording and not is_recording_disabled:
                self.recording_manager.add_frame(frame)

            # 動き検知の可視化
            if motion_detected:
                cv2.rectangle(frame, (10, 10), (200, 50), (0, 0, 255), -1)
                cv2.putText(frame, "MOTION DETECTED", (20, 35),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)

            # 録画状態の可視化
            if self.recording_manager.is_recording:
                cv2.rectangle(frame, (10, 60), (200, 100), (0, 255, 0), -1)
                cv2.putText(frame, "RECORDING", (20, 85),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)

            # 現在の日時を表示
            current_datetime = datetime.now()
            date_str = current_datetime.strftime("%Y/%m/%d")
            time_str = current_datetime.strftime("%H:%M:%S")

            # 日付を表示（左上）
            cv2.putText(frame, date_str, (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
            cv2.putText(frame, date_str, (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 1)

            # 時刻を表示（右上）
            time_x = frame.shape[1] - 150
            cv2.putText(frame, time_str, (time_x, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
            cv2.putText(frame, time_str, (time_x, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 1)

            return frame

        except Exception as e:
            logger.error(f"フレーム取得中にエラーが発生しました: {e}")
            # エラー時もダミーフレームを生成
            frame = np.zeros((480, 640, 3), dtype=np.uint8)
            cv2.putText(frame, "Camera Error", (50, 240),
                        cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 0, 0), 2)
            return frame

    def get_motion_status(self):
        """動き検知状態を取得"""
        current_time = time.time()
        startup_period = 2.0  # 2秒間の起動期間

        # 起動期間中かどうかをチェック
        is_startup_period = (
            self.start_time is not None and
            (current_time - self.start_time) < startup_period
        )

        # 動き検知初期化期間中かどうかをチェック
        is_initialization_period = self.motion_detector.initialization_frames < self.motion_detector.required_init_frames

        return {
            "motion_detected": self.motion_detector.motion_detected,
            "recording_status": self.recording_manager.get_recording_status(),
            "is_startup_period": is_startup_period,
            "startup_remaining": max(0, startup_period - (current_time - self.start_time)) if self.start_time else 0,
            "is_initialization_period": is_initialization_period,
            "initialization_progress": self.motion_detector.initialization_frames,
            "initialization_required": self.motion_detector.required_init_frames
        }

    def __del__(self):
        if hasattr(self, 'camera') and self.camera:
            self.camera.release()
        if hasattr(self, 'recording_manager'):
            self.recording_manager.stop_recording()

# Pydanticモデル


class OfferRequest(BaseModel):
    sdp: str
    type: str


# グローバル変数
camera_manager = CameraManager()

# IoT Coreクライアント
iot_client = None


@app.on_event("startup")
async def startup_event():
    """アプリケーション起動時の処理"""
    global iot_client, camera_manager

    # カメラを初期化
    logger.info("🎥 Initializing camera...")
    camera_manager.initialize_camera()

    # IoT Coreクライアントを初期化（一時的に無効化）
    try:
        iot_client = get_iot_client()
        if iot_client.connect():
            logger.info("✅ Connected to AWS IoT Core")
            iot_client.start_heartbeat()
        else:
            logger.error("❌ Failed to connect to AWS IoT Core")
            # IoT接続失敗時はダミークライアントを使用
            iot_client = None
            # エラー通知は無効化（録画完了通知のみ）
            # if line_messaging.enabled:
            #     line_messaging.send_system_error_notification(
            #         "AWS IoT Core接続に失敗しました")
    except Exception as e:
        logger.error(f"❌ IoT Core connection error: {e}")
        # IoT接続失敗時はダミークライアントを使用
        iot_client = None
        # エラー通知は無効化（録画完了通知のみ）
        # if line_messaging.enabled:
        #     line_messaging.send_system_error_notification(
        #         f"AWS IoT Core接続エラー: {str(e)}")

    # システム起動通知は無効化（録画完了通知のみ）
    # if line_messaging.enabled:
    #     try:
    #         line_messaging.send_system_startup_notification()
    #         logger.info("✅ System startup notification sent")
    #     except Exception as e:
    #         logger.error(f"❌ Failed to send startup notification: {e}")


@app.on_event("shutdown")
async def shutdown_event():
    """アプリケーション終了時の処理"""
    global iot_client

    # システム停止通知は無効化（録画完了通知のみ）
    # if line_messaging.enabled:
    #     try:
    #         line_messaging.send_system_shutdown_notification()
    #         logger.info("✅ System shutdown notification sent")
    #     except Exception as e:
    #         logger.error(f"❌ Failed to send shutdown notification: {e}")

    if iot_client:
        iot_client.disconnect()
        logger.info("Disconnected from AWS IoT Core")


@app.get("/", response_class=HTMLResponse)
async def index():
    """メインページ"""
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>防犯カメラシステム - カメラ側</title>
        <meta charset="utf-8">
        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
                background-color: #f5f5f5;
            }
            .container {
                background: white;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            h1 {
                color: #333;
                text-align: center;
            }
            .status {
                padding: 10px;
                margin: 10px 0;
                border-radius: 4px;
                text-align: center;
            }
            .status.online {
                background-color: #d4edda;
                color: #155724;
                border: 1px solid #c3e6cb;
            }
            .status.offline {
                background-color: #f8d7da;
                color: #721c24;
                border: 1px solid #f5c6cb;
            }
            .info {
                background-color: #e7f3ff;
                padding: 15px;
                border-radius: 4px;
                margin: 20px 0;
            }
            .feature {
                background-color: #fff3cd;
                padding: 15px;
                border-radius: 4px;
                margin: 20px 0;
                border-left: 4px solid #ffc107;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🔴 防犯カメラシステム - カメラ側</h1>
            
            <div class="status online">
                <strong>🟢 カメラサーバー稼働中</strong>
            </div>
            
            <div class="feature">
                <h3>🎥 動き検知・自動録画機能</h3>
                <ul>
                    <li><strong>動き検知:</strong> 大きな動きを自動検知</li>
                    <li><strong>自動録画:</strong> 動き開始から終了まで自動録画</li>
                    <li><strong>録画保存:</strong> recordings/ フォルダに保存</li>
                    <li><strong>クールダウン:</strong> 動き終了後3秒で録画停止</li>
                </ul>
            </div>
            
            <div class="info">
                <h3>📋 システム情報</h3>
                <p><strong>ポート:</strong> 3000</p>
                <p><strong>WebRTC:</strong> 有効</p>
                <p><strong>監視側URL:</strong> <a href="http://localhost:8000" target="_blank">http://localhost:8000</a></p>
                <p><strong>録画フォルダ:</strong> recordings/</p>
            </div>
            
            <div class="info">
                <h3>🔧 技術仕様</h3>
                <ul>
                    <li>Python + FastAPI</li>
                    <li>OpenCV (カメラ映像処理・動き検知)</li>
                    <li>aiortc (WebRTC実装)</li>
                    <li>リアルタイム映像配信</li>
                    <li>自動動き検知・録画機能</li>
                </ul>
            </div>
        </div>
    </body>
    </html>
    """


@app.get("/video")
async def get_video():
    """カメラ映像を取得"""
    try:
        frame = camera_manager.get_frame()
        # JPEGにエンコード
        _, buffer = cv2.imencode('.jpg', frame)
        jpeg_data = buffer.tobytes()

        return StreamingResponse(
            iter([jpeg_data]),
            media_type="image/jpeg",
            headers={"Cache-Control": "no-cache"}
        )
    except Exception as e:
        logger.error(f"映像取得エラー: {e}")
        return {"error": "Failed to get video"}


@app.get("/video-frame")
async def get_video_frame():
    """動画フレームを取得"""
    global camera_manager, is_camera_active

    if not is_camera_active or camera_manager is None:
        return {"error": "カメラが起動していません"}

    try:
        frame = camera_manager.get_frame()
        if frame is None:
            return {"error": "フレームを取得できませんでした"}

        # フレームをJPEGにエンコード
        _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
        jpeg_data = base64.b64encode(buffer).decode('utf-8')

        return {"image": f"data:image/jpeg;base64,{jpeg_data}"}
    except Exception as e:
        logger.error(f"フレーム取得エラー: {e}")
        return {"error": "フレーム取得に失敗しました"}


@app.get("/motion-status")
async def get_motion_status():
    """動き検知状態を取得"""
    global camera_manager, is_camera_active

    if not is_camera_active or camera_manager is None:
        return {"error": "カメラが起動していません"}

    try:
        motion_status = camera_manager.get_motion_status()
        return motion_status
    except Exception as e:
        logger.error(f"動き検知状態取得エラー: {e}")
        return {"error": "動き検知状態の取得に失敗しました"}


@app.get("/motion-settings")
async def get_motion_settings():
    """動き検知設定を取得"""
    try:
        detector = camera_manager.motion_detector
        return {
            "threshold": detector.threshold,
            "min_area": detector.min_area,
            "motion_cooldown": detector.motion_cooldown
        }
    except Exception as e:
        logger.error(f"動き検知設定取得エラー: {e}")
        return {"error": "Failed to get motion settings"}


@app.post("/motion-settings")
async def update_motion_settings(threshold: int = None, min_area: int = None, motion_cooldown: float = None):
    """動き検知設定を更新"""
    try:
        detector = camera_manager.motion_detector

        if threshold is not None:
            detector.threshold = max(10, min(100, threshold))  # 10-100の範囲に制限
        if min_area is not None:
            detector.min_area = max(
                100, min(10000, min_area))  # 100-10000の範囲に制限
        if motion_cooldown is not None:
            detector.motion_cooldown = max(
                1.0, min(10.0, motion_cooldown))  # 1-10秒の範囲に制限

        logger.info(
            f"動き検知設定を更新: threshold={detector.threshold}, min_area={detector.min_area}, cooldown={detector.motion_cooldown}")

        return {
            "threshold": detector.threshold,
            "min_area": detector.min_area,
            "motion_cooldown": detector.motion_cooldown
        }
    except Exception as e:
        logger.error(f"動き検知設定更新エラー: {e}")
        return {"error": "Failed to update motion settings"}


@app.get("/recordings/{filename}/info")
async def get_recording_info(filename: str):
    """録画ファイルの詳細情報を取得"""
    try:
        # ファイル名の安全性をチェック
        if ".." in filename or "/" in filename:
            return {"error": "Invalid filename"}

        file_path = RECORDINGS_DIR / filename
        if not file_path.exists():
            logger.error(f"ファイルが見つかりません: {file_path}")
            return {"error": "File not found"}

        logger.info(f"録画ファイル情報取得: {filename}")

        # ffprobeを使用して動画情報を取得
        import subprocess
        result = subprocess.run([
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", "-show_streams", str(file_path)
        ], capture_output=True, text=True)

        if result.returncode == 0:
            import json
            info = json.loads(result.stdout)
            logger.info(f"録画ファイル情報取得成功: {filename}")
            return {
                "filename": filename,
                "info": info,
                "size": file_path.stat().st_size,
                "created": datetime.fromtimestamp(file_path.stat().st_ctime).isoformat(),
                "modified": datetime.fromtimestamp(file_path.stat().st_mtime).isoformat()
            }
        else:
            logger.error(f"ffprobe実行エラー: {result.stderr}")
            # 基本的な情報のみ返す
            return {
                "filename": filename,
                "info": None,
                "size": file_path.stat().st_size,
                "created": datetime.fromtimestamp(file_path.stat().st_ctime).isoformat(),
                "modified": datetime.fromtimestamp(file_path.stat().st_mtime).isoformat()
            }
    except Exception as e:
        logger.error(f"録画ファイル情報取得エラー: {e}")
        # エラー時も基本的な情報を返す
        try:
            file_path = RECORDINGS_DIR / filename
            if file_path.exists():
                return {
                    "filename": filename,
                    "info": None,
                    "size": file_path.stat().st_size,
                    "created": datetime.fromtimestamp(file_path.stat().st_ctime).isoformat(),
                    "modified": datetime.fromtimestamp(file_path.stat().st_mtime).isoformat()
                }
        except:
            pass
        return {"error": "Failed to get recording info"}


@app.get("/recordings/{filename}")
async def get_recording_file(filename: str, request: Request, download: bool = False):
    """録画ファイルを取得"""
    try:
        # ファイル名の安全性をチェック
        if ".." in filename or "/" in filename:
            return {"error": "Invalid filename"}

        file_path = RECORDINGS_DIR / filename
        if not file_path.exists():
            logger.error(f"ファイルが見つかりません: {file_path}")
            return {"error": "File not found"}

        # ファイルの詳細情報を取得
        stat = file_path.stat()
        file_size = stat.st_size
        logger.info(
            f"録画ファイル配信: {filename} (サイズ: {file_size} bytes, ダウンロード: {download})")

        # ダウンロードモードの場合はattachmentヘッダーを設定
        content_disposition = f"attachment; filename={filename}" if download else f"inline; filename={filename}"

        # Rangeリクエストの処理
        range_header = request.headers.get("range")
        if range_header:
            try:
                # Rangeヘッダーを解析 (例: "bytes=0-1023")
                range_str = range_header.replace("bytes=", "")
                start, end = range_str.split("-")
                start = int(start)
                end = int(end) if end else file_size - 1

                # 範囲の検証
                if start >= file_size or end >= file_size or start > end:
                    return {"error": "Invalid range"}, 416

                content_length = end - start + 1

                def iterfile():
                    try:
                        with open(file_path, "rb") as file:
                            file.seek(start)
                            remaining = content_length
                            while remaining > 0:
                                chunk_size = min(8192, remaining)
                                chunk = file.read(chunk_size)
                                if not chunk:
                                    break
                                yield chunk
                                remaining -= len(chunk)
                    except Exception as e:
                        logger.error(f"ファイル読み込みエラー: {e}")
                        raise

                return StreamingResponse(
                    iterfile(),
                    media_type="video/mp4",
                    headers={
                        "Content-Type": "video/mp4",
                        "Content-Disposition": content_disposition,
                        "Accept-Ranges": "bytes",
                        "Content-Length": str(content_length),
                        "Content-Range": f"bytes {start}-{end}/{file_size}",
                        "Cache-Control": "no-cache",
                        "Access-Control-Allow-Origin": "*",
                        "Access-Control-Allow-Methods": "GET, OPTIONS",
                        "Access-Control-Allow-Headers": "Range, Content-Range, Accept-Ranges",
                        "Access-Control-Expose-Headers": "Content-Range, Accept-Ranges",
                        "X-Content-Type-Options": "nosniff"
                    },
                    status_code=206
                )
            except Exception as e:
                logger.error(f"Rangeリクエスト処理エラー: {e}")
                # Rangeリクエストの処理に失敗した場合は通常の配信にフォールバック

        # 通常の配信（Rangeリクエストなし）
        def iterfile():
            try:
                with open(file_path, "rb") as file:
                    yield from file
            except Exception as e:
                logger.error(f"ファイル読み込みエラー: {e}")
                raise

        return StreamingResponse(
            iterfile(),
            media_type="video/mp4",
            headers={
                "Content-Type": "video/mp4",
                "Content-Disposition": content_disposition,
                "Accept-Ranges": "bytes",
                "Content-Length": str(file_size),
                "Cache-Control": "public, max-age=3600",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "Range, Content-Range, Accept-Ranges",
                "Access-Control-Expose-Headers": "Content-Range, Accept-Ranges",
                "X-Content-Type-Options": "nosniff"
            }
        )
    except Exception as e:
        logger.error(f"録画ファイル取得エラー: {e}")
        return {"error": "Failed to get recording file"}


@app.options("/recordings/{filename}")
async def options_recording_file(filename: str):
    """録画ファイルのOPTIONSリクエストに対応"""
    return {
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "*"
        }
    }


@app.delete("/recordings/{filename}")
async def delete_recording(filename: str):
    """録画ファイルを削除"""
    try:
        file_path = RECORDINGS_DIR / filename
        if not file_path.exists():
            return {"error": "File not found"}

        # 対応するサムネイルファイル名を生成
        thumbnail_name = f"{file_path.stem}_thumb.jpg"
        thumbnail_path = THUMBNAILS_DIR / thumbnail_name

        # 録画ファイルを削除
        file_path.unlink()
        logger.info(f"録画ファイル削除: {filename}")

        # 対応するサムネイルファイルも削除
        if thumbnail_path.exists():
            thumbnail_path.unlink()
            logger.info(f"サムネイルファイル削除: {thumbnail_name}")

        return {"message": "File and thumbnail deleted successfully"}
    except Exception as e:
        logger.error(f"録画ファイル削除エラー: {e}")
        return {"error": "Failed to delete recording file"}


@app.get("/recordings")
async def get_recordings():
    """録画ファイル一覧を取得"""
    try:
        recordings = []
        for file in RECORDINGS_DIR.glob("*.mp4"):
            stat = file.stat()

            # サムネイルファイル名を生成
            thumbnail_name = f"{file.stem}_thumb.jpg"
            thumbnail_path = THUMBNAILS_DIR / thumbnail_name

            # サムネイルが存在しない場合は生成
            if not thumbnail_path.exists():
                if generate_thumbnail(file, thumbnail_path):
                    logger.info(f"サムネイル生成: {thumbnail_name}")
                else:
                    logger.warning(f"サムネイル生成失敗: {file.name}")

            recordings.append({
                "filename": file.name,
                "size": stat.st_size,
                "created": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                "thumbnail": thumbnail_name if thumbnail_path.exists() else None
            })

        # 作成日時でソート（新しい順）
        recordings.sort(key=lambda x: x["created"], reverse=True)
        return {"recordings": recordings}
    except Exception as e:
        logger.error(f"録画一覧取得エラー: {e}")
        return {"error": "Failed to get recordings"}


@app.get("/thumbnails/{thumbnail_name}")
async def get_thumbnail(thumbnail_name: str):
    """サムネイル画像を取得"""
    try:
        # ファイル名の安全性をチェック
        if ".." in thumbnail_name or "/" in thumbnail_name:
            return {"error": "Invalid filename"}

        thumbnail_path = THUMBNAILS_DIR / thumbnail_name
        if not thumbnail_path.exists():
            return {"error": "Thumbnail not found"}

        # 画像ファイルを読み込んで返す
        with open(thumbnail_path, "rb") as f:
            image_data = f.read()

        return Response(
            content=image_data,
            media_type="image/jpeg",
            headers={
                "Cache-Control": "public, max-age=3600",
                "Access-Control-Allow-Origin": "*"
            }
        )
    except Exception as e:
        logger.error(f"サムネイル取得エラー: {e}")
        return {"error": "Failed to get thumbnail"}


@app.get("/camera-status")
async def get_camera_status():
    """カメラの起動状態を取得"""
    global is_camera_active, camera_manager

    # デバッグ情報を追加
    debug_info = {
        "is_active": is_camera_active,
        "is_initialized": camera_manager.is_initialized if camera_manager else False,
        "camera_manager_exists": camera_manager is not None,
        "camera_manager_type": type(camera_manager).__name__ if camera_manager else None,
        "timestamp": datetime.now().isoformat()
    }

    logger.info(f"Camera status requested: {debug_info}")
    return debug_info


@app.post("/camera/start")
async def start_camera():
    """カメラを起動"""
    global camera_manager, is_camera_active

    if is_camera_active:
        return {"message": "カメラは既に起動中です", "status": "already_active"}

    try:
        if camera_manager is None:
            camera_manager = CameraManager()

        # カメラが既に初期化されている場合はスキップ
        if not camera_manager.is_initialized:
            camera_manager.initialize_camera()

        # 初期化が成功したかチェック
        if not camera_manager.is_initialized:
            logger.error("カメラの初期化に失敗しました")
            return {"error": "カメラの初期化に失敗しました", "status": "initialization_failed"}

        is_camera_active = True
        logger.info("カメラを起動しました")
        return {"message": "カメラを起動しました", "status": "started"}
    except Exception as e:
        logger.error(f"カメラ起動エラー: {e}")
        # エラーが発生した場合は状態をリセット
        is_camera_active = False
        if camera_manager:
            camera_manager.is_initialized = False
        return {"error": f"カメラ起動に失敗しました: {str(e)}", "status": "error"}


@app.post("/camera/stop")
async def stop_camera():
    """カメラを停止"""
    global camera_manager, is_camera_active

    if not is_camera_active:
        return {"message": "カメラは既に停止中です", "status": "already_stopped"}

    try:
        is_camera_active = False

        if camera_manager:
            # 録画を停止
            camera_manager.recording_manager.stop_recording()
            # カメラをリリース
            if camera_manager.camera:
                camera_manager.camera.release()
                camera_manager.camera = None
            # 初期化状態をリセット
            camera_manager.is_initialized = False
            camera_manager.start_time = None  # 起動時間をリセット

        logger.info("カメラを停止しました")
        return {"message": "カメラを停止しました", "status": "stopped"}
    except Exception as e:
        logger.error(f"カメラ停止エラー: {e}")
        return {"error": f"カメラ停止に失敗しました: {str(e)}", "status": "error"}


@app.get("/health")
async def health_check():
    """ヘルスチェック"""
    try:
        camera_working = camera_manager.camera is not None and camera_manager.camera.isOpened()
        iot_connected = iot_client is not None and hasattr(
            iot_client, 'client') and iot_client.connected if iot_client else False

        return {
            "status": "healthy",
            "camera_working": camera_working,
            "iot_connected": iot_connected,
            "line_messaging_enabled": line_messaging.enabled,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        return {
            "status": "error",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }


@app.get("/line-messaging/status")
async def get_line_messaging_status():
    """LINE Messaging APIの状態を取得"""
    return {
        "enabled": line_messaging.enabled,
        "configured": line_messaging.channel_access_token is not None
    }


@app.post("/line-messaging/test")
async def test_line_messaging():
    """LINE Messaging APIのテスト送信"""
    if not line_messaging.enabled:
        raise HTTPException(
            status_code=400, detail="LINE Messaging APIが設定されていません")

    success = line_messaging.send_test_notification()

    if success:
        return {"message": "テスト通知を送信しました"}
    else:
        raise HTTPException(status_code=500, detail="通知送信に失敗しました")


@app.post("/line-messaging/system-startup")
async def send_system_startup_notification():
    """システム起動通知を送信"""
    if not line_messaging.enabled:
        raise HTTPException(
            status_code=400, detail="LINE Messaging APIが設定されていません")

    success = line_messaging.send_system_startup_notification()

    if success:
        return {"message": "システム起動通知を送信しました"}
    else:
        raise HTTPException(status_code=500, detail="通知送信に失敗しました")


@app.post("/line-messaging/system-shutdown")
async def send_system_shutdown_notification():
    """システム停止通知を送信"""
    if not line_messaging.enabled:
        raise HTTPException(
            status_code=400, detail="LINE Messaging APIが設定されていません")

    success = line_messaging.send_system_shutdown_notification()

    if success:
        return {"message": "システム停止通知を送信しました"}
    else:
        raise HTTPException(status_code=500, detail="通知送信に失敗しました")


@app.post("/line-messaging/system-error")
async def send_system_error_notification(error_message: str = Form(None)):
    """システムエラー通知を送信"""
    if not line_messaging.enabled:
        raise HTTPException(
            status_code=400, detail="LINE Messaging APIが設定されていません")

    if not error_message:
        error_message = "システムエラーが発生しました"

    success = line_messaging.send_system_error_notification(error_message)

    if success:
        return {"message": "システムエラー通知を送信しました"}
    else:
        raise HTTPException(status_code=500, detail="通知送信に失敗しました")


if __name__ == "__main__":
    import uvicorn
    logger.info("防犯カメラシステム - カメラ側を起動しています...")
    uvicorn.run(app, host="0.0.0.0", port=3000)
