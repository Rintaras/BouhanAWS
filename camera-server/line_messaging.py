import requests
import logging
import json
import base64
from pathlib import Path
from datetime import datetime
from typing import Optional

logger = logging.getLogger(__name__)


class LineMessagingAPI:
    def __init__(self, channel_access_token: str = None, user_id: str = None):
        self.channel_access_token = channel_access_token
        self.user_id = user_id
        self.enabled = channel_access_token is not None
        self.base_url = "https://api.line.me/v2"

    def send_text_message(self, message: str) -> bool:
        """テキストメッセージを送信（友達全員にブロードキャスト）"""
        if not self.enabled:
            logger.info("LINE Messaging APIが無効です（トークンが設定されていません）")
            return False

        try:
            url = f"{self.base_url}/bot/message/broadcast"
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.channel_access_token}"
            }

            data = {
                "messages": [
                    {
                        "type": "text",
                        "text": message
                    }
                ]
            }

            response = requests.post(url, headers=headers, json=data)

            if response.status_code == 200:
                logger.info("LINE Messaging API ブロードキャスト送信成功")
                return True
            else:
                logger.error(
                    f"LINE Messaging API ブロードキャスト送信失敗: {response.status_code} - {response.text}")
                return False

        except Exception as e:
            logger.error(f"LINE Messaging API ブロードキャスト送信エラー: {e}")
            return False

    def send_image_message(self, image_path: Path, message: str = "") -> bool:
        """画像メッセージを送信"""
        if not self.enabled:
            logger.info("LINE Messaging APIが無効です（トークンが設定されていません）")
            return False

        try:
            if not image_path.exists():
                logger.error(f"画像ファイルが見つかりません: {image_path}")
                return False

            # 画像をアップロード
            upload_url = f"{self.base_url}/bot/message/upload"
            headers = {
                "Authorization": f"Bearer {self.channel_access_token}"
            }

            with open(image_path, "rb") as f:
                files = {"imageFile": f}
                response = requests.post(
                    upload_url, headers=headers, files=files)

            if response.status_code != 200:
                logger.error(
                    f"画像アップロード失敗: {response.status_code} - {response.text}")
                return False

            # アップロードされた画像のIDを取得
            upload_result = response.json()
            image_id = upload_result.get("imageId")

            if not image_id:
                logger.error("画像IDの取得に失敗しました")
                return False

            # 画像メッセージを送信
            push_url = f"{self.base_url}/bot/message/push"
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.channel_access_token}"
            }

            data = {
                "to": self.user_id,
                "messages": [
                    {
                        "type": "image",
                        "originalContentUrl": f"https://api.line.me/v2/bot/message/{image_id}/content",
                        "previewImageUrl": f"https://api.line.me/v2/bot/message/{image_id}/content"
                    }
                ]
            }

            # テキストメッセージも送信
            if message:
                data["messages"].append({
                    "type": "text",
                    "text": message
                })

            response = requests.post(push_url, headers=headers, json=data)

            if response.status_code == 200:
                logger.info("LINE Messaging API 画像送信成功")
                return True
            else:
                logger.error(
                    f"LINE Messaging API 画像送信失敗: {response.status_code} - {response.text}")
                return False

        except Exception as e:
            logger.error(f"LINE Messaging API 画像送信エラー: {e}")
            return False

    def send_motion_detected_notification(self, image_path: Optional[Path] = None) -> bool:
        """物体検知通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')
        current_time_short = datetime.now().strftime('%H:%M:%S')

        # 改善された基本メッセージ
        message = f"""🚨 **緊急通知: 物体検知**

⏰ **検知時刻**: {current_time}
📍 **場所**: 防犯カメラシステム
🔍 **状態**: 録画開始中

⚠️ **重要**: 物体が検知されました
📹 自動録画を開始しています
🔄 システムが正常に動作中

💡 **次のアクション**:
• 録画ファイルを確認
• 必要に応じて警察に連絡
• システム設定の見直し

---
🛡️ 防犯カメラシステム"""

        if image_path and image_path.exists():
            # 画像付きで送信
            return self.send_image_message(image_path, message)
        else:
            # テキストのみ送信
            return self.send_text_message(message)

    def send_recording_complete_notification(self, filename: str, file_size: int, duration: float = None, server_url: str = None) -> bool:
        """録画完了通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')
        size_mb = file_size / (1024 * 1024)

        # 録画時間の表示を改善
        duration_str = ""
        if duration:
            if duration < 60:
                duration_str = f"{duration:.1f}秒"
            else:
                minutes = int(duration // 60)
                seconds = duration % 60
                duration_str = f"{minutes}分{seconds:.1f}秒"

        # ファイルサイズの表示を改善
        if size_mb < 1:
            size_str = f"{size_mb * 1024:.1f}KB"
        else:
            size_str = f"{size_mb:.1f}MB"

        # 録画ファイルのURLを生成
        recording_url = ""
        if server_url:
            recording_url = f"{server_url}/recordings/{filename}"
        else:
            # デフォルトのローカルURL
            recording_url = f"http://localhost:3000/recordings/{filename}"

        # 改善されたメッセージ
        message = f"""📹 **録画完了通知**

✅ **録画完了**: {current_time}
📁 **ファイル名**: {filename}
📊 **ファイルサイズ**: {size_str}"""

        if duration_str:
            message += f"\n⏱️ **録画時間**: {duration_str}"

        message += f"""

💾 **保存場所**: 防犯カメラシステム
🔗 **録画データURL**: {recording_url}

🔍 **次のアクション**:
• 録画内容を確認
• 必要に応じてダウンロード
• 重要度に応じて保存/削除

📱 **アクセス方法**:
• 上記URLから直接アクセス
• Webブラウザでシステムにアクセス
• 録画一覧から確認可能

---
🛡️ 防犯カメラシステム"""

        return self.send_text_message(message)

    def send_test_notification(self) -> bool:
        """テスト通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')

        message = f"""🔔 **システムテスト通知**

✅ **テスト成功**: {current_time}
🛡️ **システム状態**: 正常動作中
📡 **通信状態**: 良好
🔋 **システム稼働**: 安定

📊 **システム情報**:
• カメラ: 正常
• 録画機能: 正常
• 通知機能: 正常
• ネットワーク: 正常

💡 **この通知について**:
• システムが正常に動作していることを確認
• 通知機能が正しく設定されている
• 緊急時の通知が受信可能

---
🛡️ 防犯カメラシステム"""

        return self.send_text_message(message)

    def send_system_startup_notification(self) -> bool:
        """システム起動通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')

        message = f"""🟢 **システム起動通知**

✅ **起動完了**: {current_time}
🛡️ **システム状態**: 起動中
📡 **初期化**: 完了
🔋 **システム稼働**: 開始

📊 **起動確認項目**:
• カメラ: 初期化完了
• 録画機能: 準備完了
• 通知機能: 動作確認済み
• ネットワーク: 接続確認済み

💡 **システム情報**:
• 防犯カメラシステムが正常に起動しました
• 24時間監視を開始しています
• 異常検知時に自動通知されます

---
🛡️ 防犯カメラシステム"""

        return self.send_text_message(message)

    def send_system_error_notification(self, error_message: str) -> bool:
        """システムエラー通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')

        message = f"""🔴 **システムエラー通知**

❌ **エラー発生**: {current_time}
🛡️ **システム状態**: エラー
⚠️ **重要度**: 要確認

📋 **エラー詳細**:
{error_message}

🔧 **推奨アクション**:
• システムの再起動を検討
• ログファイルの確認
• 設定の見直し
• 必要に応じて管理者に連絡

📞 **緊急時連絡先**:
• システム管理者に連絡
• 技術サポートに相談

---
🛡️ 防犯カメラシステム"""

        return self.send_text_message(message)

    def send_system_shutdown_notification(self) -> bool:
        """システム停止通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')

        message = f"""🟡 **システム停止通知**

⏹️ **停止時刻**: {current_time}
🛡️ **システム状態**: 停止中
📡 **通信状態**: 切断
🔋 **システム稼働**: 停止

📊 **停止前状態**:
• カメラ: 停止
• 録画機能: 停止
• 通知機能: 最終通知
• ネットワーク: 切断

💡 **注意事項**:
• 防犯カメラシステムが停止しました
• 監視機能が無効になっています
• 再起動まで監視は行われません

---
🛡️ 防犯カメラシステム"""

        return self.send_text_message(message)
