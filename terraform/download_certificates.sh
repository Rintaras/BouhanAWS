#!/bin/bash

# AWS IoT Core 証明書ダウンロードスクリプト

set -e

# 設定
CERT_DIR="/home/pi/kumikomi3/camera-server/certs"
THING_NAME="security-camera-raspberry-pi"

echo "AWS IoT Core 証明書をダウンロード中..."

# ディレクトリ作成
mkdir -p "$CERT_DIR"

# Terraformの出力から証明書IDを取得
CERT_ID=$(terraform output -raw iot_certificate_id)
echo "証明書ID: $CERT_ID"

# 証明書ファイルをダウンロード
echo "証明書をダウンロード中..."
aws iot describe-certificate --certificate-id "$CERT_ID" --query 'certificateDescription.certificatePem' --output text > "$CERT_DIR/certificate.pem.crt"

# 秘密鍵をダウンロード
echo "秘密鍵をダウンロード中..."
aws iot describe-certificate --certificate-id "$CERT_ID" --query 'certificateDescription.keyPair.privateKey' --output text > "$CERT_DIR/private.pem.key"

# ルートCA証明書をダウンロード
echo "ルートCA証明書をダウンロード中..."
curl -s https://www.amazontrust.com/repository/AmazonRootCA1.pem > "$CERT_DIR/root-CA.crt"

# 権限設定
chmod 600 "$CERT_DIR/private.pem.key"
chmod 644 "$CERT_DIR/certificate.pem.crt"
chmod 644 "$CERT_DIR/root-CA.crt"

echo "証明書のダウンロードが完了しました:"
echo "証明書: $CERT_DIR/certificate.pem.crt"
echo "秘密鍵: $CERT_DIR/private.pem.key"
echo "ルートCA: $CERT_DIR/root-CA.crt"

# IoT Coreエンドポイントを表示
echo "IoT Coreエンドポイント:"
terraform output -raw iot_endpoint 