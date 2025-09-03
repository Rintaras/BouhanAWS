#!/bin/bash

# 防犯カメラシステム自動起動スクリプト
# Raspberry Pi起動時に実行される

echo "🚀 防犯カメラシステムを起動中..."

# プロジェクトディレクトリに移動
cd /home/pi/kumikomi3

# カメラサーバーを起動
echo "📹 カメラサーバーを起動中..."
sudo systemctl start security-camera.service

# 少し待機
sleep 10

# フロントエンドサーバーを起動
echo "🌐 フロントエンドサーバーを起動中..."
sudo systemctl start security-camera-frontend.service

# 少し待機
sleep 5

# 状態確認
echo "✅ システム起動完了"
echo "📹 カメラサーバー: http://localhost:3000"
echo "🌐 フロントエンド: http://localhost:8001"
echo "📱 外部アクセス: http://172.20.10.2:8001"

# サービスの状態を表示
sudo systemctl status security-camera.service --no-pager
sudo systemctl status security-camera-frontend.service --no-pager 