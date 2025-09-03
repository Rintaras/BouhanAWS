#!/bin/bash

# ========================================
# Cloudflare Tunnel 設定スクリプト
# ルーター設定不要で外部アクセス可能
# ========================================

echo "Cloudflare Tunnelを設定しています..."

# cloudflaredのインストール（既にインストール済みの場合）
if ! command -v cloudflared &> /dev/null; then
    echo "cloudflaredをインストールしています..."
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
    sudo dpkg -i cloudflared-linux-arm64.deb
    rm cloudflared-linux-arm64.deb
fi

# 設定ディレクトリの作成
mkdir -p ~/.cloudflared

# 設定ファイルの作成
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: camera-tunnel
credentials-file: ~/.cloudflared/camera-tunnel.json
ingress:
  - hostname: camera.your-domain.com
    service: http://localhost:3000
  - hostname: camera-https.your-domain.com
    service: https://localhost:443
  - service: http_status:404
EOF

echo "✅ Cloudflare Tunnel設定ファイルを作成しました"
echo ""
echo "📋 次の手順を実行してください："
echo ""
echo "1. Cloudflareアカウントを作成（無料）:"
echo "   https://dash.cloudflare.com/sign-up"
echo ""
echo "2. ドメインを追加（無料ドメインでも可）:"
echo "   https://dash.cloudflare.com/"
echo ""
echo "3. トンネルを作成:"
echo "   cloudflared tunnel create camera-tunnel"
echo ""
echo "4. トンネルを起動:"
echo "   cloudflared tunnel run camera-tunnel"
echo ""
echo "5. フロントエンドの設定を更新:"
echo "   monitor-client/src/App.tsx のURLを更新"
echo ""
echo "🔗 詳細な手順は以下を参照:"
echo "   https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/" 