#!/bin/bash

# ========================================
# localtunnel 設定スクリプト
# 認証不要、ルーター設定不要
# ========================================

echo "localtunnelを設定しています..."

# Node.jsの確認
if ! command -v node &> /dev/null; then
    echo "Node.jsがインストールされていません。先にNode.jsをインストールしてください。"
    exit 1
fi

# localtunnelのインストール
echo "localtunnelをインストールしています..."
npm install -g localtunnel

echo "✅ localtunnelがインストールされました"
echo ""
echo "📋 使用方法："
echo ""
echo "1. HTTPSトンネルを起動:"
echo "   lt --port 443 --subdomain camera-system"
echo ""
echo "2. または、ランダムサブドメインで起動:"
echo "   lt --port 443"
echo ""
echo "3. 表示されたURLをメモして、フロントエンドの設定を更新"
echo ""
echo "🔗 詳細な手順は以下を参照:"
echo "   https://github.com/localtunnel/localtunnel" 