#!/bin/bash

echo "🚀 Cloudflare Tunnel セットアップ開始"
echo "========================================"

# 1. Cloudflaredがインストールされているか確認
if ! command -v cloudflared &> /dev/null; then
    echo "❌ cloudflaredがインストールされていません"
    echo "📦 インストール中..."
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
    sudo dpkg -i cloudflared.deb
    rm cloudflared.deb
fi

echo "✅ cloudflared インストール完了"

# 2. 認証状態を確認
if [ ! -f ~/.cloudflared/cert.pem ]; then
    echo "🔐 Cloudflare認証が必要です"
    echo "📱 ブラウザで以下のURLにアクセスしてください："
    echo "   https://dash.cloudflare.com/argotunnel"
    echo ""
    echo "手順："
    echo "1. Cloudflareアカウントを作成/ログイン"
    echo "2. Zero Trust → Access → Tunnels"
    echo "3. 「Create a tunnel」をクリック"
    echo "4. トンネル名: kumikomi-camera"
    echo "5. 設定ファイルをダウンロード"
    echo ""
    echo "設定ファイルをダウンロードしたら、このスクリプトを再実行してください"
    exit 1
fi

echo "✅ Cloudflare認証完了"

# 3. トンネル設定ファイルを作成
cat > ~/.cloudflared/config.yml << EOF
tunnel: kumikomi-camera
credentials-file: ~/.cloudflared/kumikomi-camera.json

ingress:
  - hostname: kumikomi-camera.your-domain.com
    service: https://localhost:8443
  - service: http_status:404
EOF

echo "✅ トンネル設定ファイル作成完了"

# 4. トンネルを起動
echo "🚀 Cloudflare Tunnelを起動中..."
echo "📱 外部URL: https://kumikomi-camera.your-domain.com"
echo "⏹️  停止するには Ctrl+C を押してください"

cloudflared tunnel --config ~/.cloudflared/config.yml run kumikomi-camera 