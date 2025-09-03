#!/bin/bash

# ========================================
# HTTPS リバースプロキシ設定スクリプト
# Raspberry Pi用
# ========================================

echo "HTTPS リバースプロキシを設定しています..."

# Nginxのインストール
sudo apt update
sudo apt install -y nginx openssl

# 自己署名証明書の作成
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/camera.key \
    -out /etc/nginx/ssl/camera.crt \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=CameraSystem/CN=camera.local"

# Nginx設定ファイルの作成
sudo tee /etc/nginx/sites-available/camera-proxy > /dev/null << 'EOF'
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/camera.crt;
    ssl_certificate_key /etc/nginx/ssl/camera.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # CORS設定
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
    add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;

    # OPTIONSリクエストの処理
    if ($request_method = 'OPTIONS') {
        return 204;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket対応
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # タイムアウト設定
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# HTTP -> HTTPS リダイレクト
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$server_name$request_uri;
}
EOF

# サイトの有効化
sudo ln -sf /etc/nginx/sites-available/camera-proxy /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Nginx設定テスト
sudo nginx -t

if [ $? -eq 0 ]; then
    # Nginxの再起動
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    
    echo "✅ HTTPS リバースプロキシの設定が完了しました"
    echo "📱 HTTPS URL: https://$(hostname -I | awk '{print $1}')"
    echo "🔐 自己署名証明書を使用しています（ブラウザで警告が表示される場合があります）"
else
    echo "❌ Nginx設定にエラーがあります"
    exit 1
fi 