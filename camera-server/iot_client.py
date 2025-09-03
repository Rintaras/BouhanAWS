#!/usr/bin/env python3
"""
AWS IoT Core クライアント for Raspberry Pi Security Camera
"""

import json
import ssl
import time
import threading
import requests
import boto3
from datetime import datetime
from AWSIoTPythonSDK.MQTTLib import AWSIoTMQTTClient
import logging

# ログ設定
logger = logging.getLogger(__name__)


class IoTClient:
    def __init__(self):
        self.client = None
        self.connected = False
        self.heartbeat_thread = None
        self.stop_heartbeat = False

        # カメラサーバーの設定
        self.camera_server_url = "http://localhost:3000"

        # DynamoDB設定
        self.dynamodb = boto3.resource(
            'dynamodb', region_name='ap-northeast-1')
        self.response_table = self.dynamodb.Table(
            'security-camera-iot-responses')

        # AWS IoT設定
        self.endpoint = "a1elu8r7ww6uyj-ats.iot.ap-northeast-1.amazonaws.com"
        self.root_ca_path = "certs/root-CA.crt"
        self.private_key_path = "certs/private.pem.key"
        self.certificate_path = "certs/certificate.pem.crt"
        self.thing_name = "security-camera-raspberry-pi"

    def connect(self):
        """AWS IoT Coreに接続"""
        try:
            # MQTTクライアントを初期化
            self.client = AWSIoTMQTTClient(self.thing_name)
            self.client.configureEndpoint(self.endpoint, 8883)
            self.client.configureCredentials(
                self.root_ca_path,
                self.private_key_path,
                self.certificate_path
            )

            # MQTT設定
            self.client.configureAutoReconnectBackoffTime(1, 32, 20)
            self.client.configureOfflinePublishQueueing(-1)
            self.client.configureDrainingFrequency(2)
            self.client.configureConnectDisconnectTimeout(10)
            self.client.configureMQTTOperationTimeout(5)

            # 接続
            if self.client.connect():
                logger.info("✅ AWS IoT Coreに接続しました")
                self.connected = True

                # コマンドトピックを購読
                self.client.subscribe(
                    f"security-camera/{self.thing_name}/commands", 1, self.on_command_received)
                logger.info("📡 コマンドトピックを購読しました")

                return True
            else:
                logger.error("❌ AWS IoT Core接続に失敗しました")
                return False

        except Exception as e:
            logger.error(f"❌ IoT接続エラー: {e}")
            return False

    def on_command_received(self, client, userdata, message):
        """コマンド受信時の処理"""
        try:
            # メッセージをデコード
            payload = json.loads(message.payload.decode('utf-8'))
            logger.info(f"📨 IoTコマンド受信: {payload}")

            command = payload.get('command')
            data = payload.get('data', {})
            request_id = payload.get('requestId')
            timestamp = payload.get('timestamp')

            if not command or not request_id:
                logger.error("❌ 必要なパラメータが不足しています")
                return

            # カメラ制御コマンドを処理
            response = self.handle_camera_command(command, data)

            # DynamoDBにレスポンスを保存
            self.save_response_to_dynamodb(request_id, response)

            logger.info(f"✅ IoTコマンド処理完了: {command}")

        except Exception as e:
            logger.error(f"❌ IoTコマンド処理エラー: {e}")

    def handle_camera_command(self, command, data):
        """カメラ制御コマンドを処理"""
        try:
            # カメラサーバーのエンドポイントに対応
            endpoint_map = {
                'start': '/camera/start',
                'stop': '/camera/stop',
                'status': '/camera-status'
            }

            endpoint = endpoint_map.get(command)
            if not endpoint:
                return {
                    'statusCode': 400,
                    'contentType': 'application/json',
                    'body': json.dumps({'error': f'Unknown command: {command}'})
                }

            # カメラサーバーに直接リクエスト
            if command in ['start', 'stop']:
                response = self.forward_to_camera_server(
                    endpoint, 'POST', data)
            else:
                response = self.forward_to_camera_server(endpoint, 'GET', None)

            return response

        except Exception as e:
            logger.error(f"❌ カメラコマンド処理エラー: {e}")
            return {
                'statusCode': 500,
                'contentType': 'application/json',
                'body': json.dumps({'error': str(e)})
            }

    def forward_to_camera_server(self, path, method, body):
        """カメラサーバーにリクエストを転送"""
        try:
            url = f"{self.camera_server_url}{path}"
            headers = {'Content-Type': 'application/json'}

            # HTTPリクエストを送信
            if method.upper() == 'GET':
                response = requests.get(url, headers=headers, timeout=10)
            elif method.upper() == 'POST':
                response = requests.post(
                    url, headers=headers, json=body if body else {}, timeout=10)
            elif method.upper() == 'PUT':
                response = requests.put(
                    url, headers=headers, json=body if body else {}, timeout=10)
            elif method.upper() == 'DELETE':
                response = requests.delete(url, headers=headers, timeout=10)
            else:
                response = requests.get(url, headers=headers, timeout=10)

            # レスポンスを構造化
            return {
                'statusCode': response.status_code,
                'contentType': response.headers.get('content-type', 'application/json'),
                'body': response.text
            }

        except requests.exceptions.RequestException as e:
            logger.error(f"❌ カメラサーバーリクエストエラー: {e}")
            return {
                'statusCode': 500,
                'contentType': 'application/json',
                'body': json.dumps({
                    'error': True,
                    'message': f'Camera server error: {str(e)}',
                    'timestamp': datetime.now().isoformat()
                })
            }

    def save_response_to_dynamodb(self, request_id, response):
        """DynamoDBにレスポンスを保存"""
        try:
            # TTL設定（1時間後に削除）
            ttl = int(time.time()) + 3600

            # DynamoDBに保存
            self.response_table.put_item(
                Item={
                    'requestId': request_id,
                    'response': response,
                    'ttl': ttl,
                    'timestamp': datetime.now().isoformat()
                }
            )

            logger.info(f"✅ レスポンスをDynamoDBに保存しました: {request_id}")

        except Exception as e:
            logger.error(f"❌ DynamoDB保存エラー: {e}")

    def publish_status(self, status_data):
        """ステータスを公開"""
        if not self.connected or not self.client:
            return False

        try:
            topic = "security-camera/status"
            payload = json.dumps({
                **status_data,
                'timestamp': datetime.now().isoformat(),
                'thing_name': self.thing_name
            })

            self.client.publish(topic, payload, 1)
            logger.debug(f"📤 ステータス送信: {topic}")
            return True

        except Exception as e:
            logger.error(f"❌ ステータス送信エラー: {e}")
            return False

    def start_heartbeat(self):
        """ハートビートを開始"""
        if self.heartbeat_thread and self.heartbeat_thread.is_alive():
            return

        self.stop_heartbeat = False
        self.heartbeat_thread = threading.Thread(target=self._heartbeat_worker)
        self.heartbeat_thread.daemon = True
        self.heartbeat_thread.start()
        logger.info("💓 ハートビート開始")

    def _heartbeat_worker(self):
        """ハートビートワーカー"""
        while not self.stop_heartbeat and self.connected:
            try:
                status = {
                    'type': 'heartbeat',
                    'status': 'alive',
                    'connected': self.connected
                }
                self.publish_status(status)
                time.sleep(30)  # 30秒間隔

            except Exception as e:
                logger.error(f"❌ ハートビートエラー: {e}")
                time.sleep(30)

    def disconnect(self):
        """接続を切断"""
        try:
            self.stop_heartbeat = True
            self.connected = False

            if self.client:
                self.client.disconnect()
                logger.info("🔌 AWS IoT Coreから切断しました")

        except Exception as e:
            logger.error(f"❌ 切断エラー: {e}")


# シングルトンインスタンス
_iot_client = None


def get_iot_client():
    """IoTクライアントのシングルトンインスタンスを取得"""
    global _iot_client
    if _iot_client is None:
        _iot_client = IoTClient()
    return _iot_client
