import requests
import logging
from pathlib import Path
from datetime import datetime

logger = logging.getLogger(__name__)


class LineNotifier:
    def __init__(self, token: str = None):
        self.token = token
        self.enabled = token is not None

    def send_notification(self, message: str, image_path: Path = None):
        """LINE Notifyに通知を送信"""
        if not self.enabled:
            logger.info("LINE通知が無効です（トークンが設定されていません）")
            return False

        try:
            url = "https://notify-api.line.me/api/notify"
            headers = {"Authorization": f"Bearer {self.token}"}

            data = {"message": message}
            files = {}

            # 画像がある場合は添付
            if image_path and image_path.exists():
                files = {"imageFile": open(image_path, "rb")}

            response = requests.post(
                url, headers=headers, data=data, files=files)

            if response.status_code == 200:
                logger.info("LINE通知送信成功")
                return True
            else:
                logger.error(
                    f"LINE通知送信失敗: {response.status_code} - {response.text}")
                return False

        except Exception as e:
            logger.error(f"LINE通知送信エラー: {e}")
            return False

    def send_recording_complete_notification(self, filename: str, file_size: int, duration: float = None, server_url: str = None):
        """録画完了通知を送信"""
        if not self.enabled:
            return False

        # ファイルサイズを人間が読みやすい形式に変換
        size_mb = file_size / (1024 * 1024)

        # ファイルサイズの表示を改善
        if size_mb < 1:
            size_str = f"{size_mb * 1024:.1f}KB"
        else:
            size_str = f"{size_mb:.1f}MB"

        # 録画時間の表示を改善
        duration_str = ""
        if duration:
            if duration < 60:
                duration_str = f"{duration:.1f}秒"
            else:
                minutes = int(duration // 60)
                seconds = duration % 60
                duration_str = f"{minutes}分{seconds:.1f}秒"

        # 録画ファイルのURLを生成
        recording_url = ""
        if server_url:
            recording_url = f"{server_url}/recordings/{filename}"
        else:
            # デフォルトのローカルURL
            recording_url = f"http://localhost:3000/recordings/{filename}"

        message = f"""📹 **録画完了通知**

✅ **録画完了**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
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

---
🛡️ 防犯カメラシステム"""

        return self.send_notification(message)

    def send_motion_detected_notification(self, filename: str = None):
        """動体検知通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        message = f"""🚨 **緊急通知: 物体検知**

⏰ **検知時刻**: {current_time}
📍 **場所**: 防犯カメラシステム
🔍 **状態**: 録画開始中

⚠️ **重要**: 物体が検知されました
📹 自動録画を開始しています
🔄 システムが正常に動作中"""

        if filename:
            message += f"\n📁 **録画ファイル**: {filename}"

        message += f"""

💡 **次のアクション**:
• 録画ファイルを確認
• 必要に応じて警察に連絡
• システム設定の見直し

---
🛡️ 防犯カメラシステム"""

        return self.send_notification(message)

    def send_system_startup_notification(self):
        """システム起動通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

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

        return self.send_notification(message)

    def send_system_error_notification(self, error_message: str):
        """システムエラー通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

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

        return self.send_notification(message)

    def send_system_shutdown_notification(self):
        """システム停止通知を送信"""
        if not self.enabled:
            return False

        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

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

        return self.send_notification(message)
