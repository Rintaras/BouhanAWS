#!/bin/bash

# ========================================
# ngrok 無料版設定スクリプト
# ルーター設定不要で外部アクセス可能
# ========================================

echo "ngrok無料版を設定しています..."

# ngrokのインストール確認
if ! command -v ngrok &> /dev/null; then
    echo "ngrokをインストールしています..."
    wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz
    tar -xzf ngrok-v3-stable-linux-arm64.tgz
    sudo mv ngrok /usr/local/bin/
    rm ngrok-v3-stable-linux-arm64.tgz
fi

echo "✅ ngrokがインストールされました"
echo ""
echo "📋 次の手順を実行してください："
echo ""
echo "1. ngrokアカウントを作成（無料）:"
echo "   https://dashboard.ngrok.com/signup"
echo ""
echo "2. 認証トークンを取得:"
echo "   https://dashboard.ngrok.com/get-started/your-authtoken"
echo ""
echo "3. 認証トークンを設定:"
echo "   ngrok config add-authtoken YOUR_TOKEN_HERE"
echo ""
echo "4. HTTPSトンネルを起動:"
echo "   ngrok http 443 --log=stdout"
echo ""
echo "5. 表示されたURLをメモして、フロントエンドの設定を更新"
echo ""
echo "🔗 詳細な手順は以下を参照:"
echo "   https://ngrok.com/docs/getting-started/" 