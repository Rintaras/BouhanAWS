#!/bin/bash

# ========================================
# HTTPS サーバー自動起動スクリプト
# ルーター設定不要で外部アクセス可能
# ========================================

echo "HTTPS サーバーを起動しています..."

# カメラサーバーが起動しているか確認
if ! curl -s "http://localhost:3000/camera-status" > /dev/null; then
    echo "❌ カメラサーバーが起動していません"
    echo "先にカメラサーバーを起動してください:"
    echo "cd camera-server && python main.py"
    exit 1
fi

# 既存のHTTPSサーバープロセスを停止
pkill -f "simple-https-server.py"

# HTTPSサーバーを起動
cd /home/pi/kumikomi3
python3 scripts/simple-https-server.py &

# 起動確認
sleep 3
if curl -k -s "https://localhost:8443/camera-status" > /dev/null; then
    echo "✅ HTTPS サーバーが正常に起動しました"
    echo ""
    echo "📱 アクセスURL:"
    echo "   内部: https://192.168.50.105:8443"
    echo "   外部: https://133.43.7.18:8443"
    echo ""
    echo "🌐 フロントエンド: https://d1dc57z0cxlh4u.cloudfront.net"
    echo ""
    echo "📋 外部からアクセスするには、ポート8443を開放する必要があります"
    echo "   または、ngrokなどのトンネリングサービスを使用してください"
    echo ""
    echo "⏹️  停止するには: pkill -f 'simple-https-server.py'"
else
    echo "❌ HTTPS サーバーの起動に失敗しました"
    exit 1
fi 