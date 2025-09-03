#!/usr/bin/env python3
"""
IoT Core接続テストスクリプト
"""

import os
import sys
import time
import json
import ssl
import paho.mqtt.client as mqtt
import boto3


def test_iot_connection():
    """IoT Core接続をテスト"""

    # 証明書パス
    cert_dir = os.path.join(os.path.dirname(__file__), "certs")
    cert_path = os.path.join(cert_dir, "certificate.pem.crt")
    key_path = os.path.join(cert_dir, "private.pem.key")
    root_ca_path = os.path.join(cert_dir, "root-CA.crt")

    print(f"証明書パス: {cert_path}")
    print(f"秘密鍵パス: {key_path}")
    print(f"ルートCAパス: {root_ca_path}")

    # ファイルの存在確認
    for path in [cert_path, key_path, root_ca_path]:
        if not os.path.exists(path):
            print(f"❌ ファイルが存在しません: {path}")
            return False
        else:
            print(f"✅ ファイルが存在します: {path}")

    # ファイルサイズ確認
    for path in [cert_path, key_path, root_ca_path]:
        size = os.path.getsize(path)
        print(f"ファイルサイズ {path}: {size} bytes")

    # IoT Coreエンドポイントを取得
    try:
        iot_client = boto3.client('iot')
        endpoint = iot_client.describe_endpoint(
            endpointType='iot:Data-ATS')['endpointAddress']
        print(f"✅ IoT Coreエンドポイント: {endpoint}")
    except Exception as e:
        print(f"❌ IoT Coreエンドポイント取得エラー: {e}")
        return False

    # MQTTクライアント設定
    mqtt_client = mqtt.Client()

    def on_connect(client, userdata, flags, rc):
        print(f"✅ MQTT接続成功: {rc}")

    def on_message(client, userdata, msg):
        print(f"📨 メッセージ受信: {msg.topic} - {msg.payload.decode()}")

    def on_disconnect(client, userdata, rc):
        print(f"❌ MQTT切断: {rc}")

    mqtt_client.on_connect = on_connect
    mqtt_client.on_message = on_message
    mqtt_client.on_disconnect = on_disconnect

    # TLS設定
    try:
        mqtt_client.tls_set(
            ca_certs=root_ca_path,
            certfile=cert_path,
            keyfile=key_path,
            cert_reqs=ssl.CERT_REQUIRED,
            tls_version=ssl.PROTOCOL_TLSv1_2,
            ciphers=None
        )
        print("✅ TLS設定完了")
    except Exception as e:
        print(f"❌ TLS設定エラー: {e}")
        return False

    # 接続テスト
    try:
        print("🔌 IoT Coreに接続中...")
        mqtt_client.connect(endpoint, 8883, 60)
        mqtt_client.loop_start()

        # 接続を待機
        time.sleep(5)

        if mqtt_client.is_connected():
            print("✅ IoT Core接続成功!")

            # テストメッセージを送信
            test_message = {
                "test": True,
                "timestamp": time.time(),
                "message": "IoT Core接続テスト"
            }

            mqtt_client.publish(
                "security-camera/test",
                json.dumps(test_message),
                qos=1
            )
            print("✅ テストメッセージ送信完了")

            # 少し待機
            time.sleep(3)

            mqtt_client.disconnect()
            mqtt_client.loop_stop()
            print("✅ 接続テスト完了")
            return True

        else:
            print("❌ IoT Core接続失敗")
            return False

    except Exception as e:
        print(f"❌ 接続エラー: {e}")
        return False


if __name__ == "__main__":
    print("🚀 IoT Core接続テスト開始")
    success = test_iot_connection()

    if success:
        print("🎉 IoT Core接続テスト成功!")
    else:
        print("💥 IoT Core接続テスト失敗!")
        sys.exit(1)
