#!/bin/bash

# Raspberry Pi用VPNクライアント設定スクリプト
# AWS EC2プロキシサーバーとの接続を確立

set -e

echo "=== Raspberry Pi VPN Client Setup ==="

# 必要なパッケージのインストール
echo "Installing required packages..."
sudo apt update
sudo apt install -y openvpn easy-rsa curl wget

# OpenVPN設定ディレクトリ作成
sudo mkdir -p /etc/openvpn/client
sudo mkdir -p /etc/openvpn/keys

# VPN設定ファイル作成
cat > /tmp/client.conf << 'EOF'
client
dev tun
proto udp
remote YOUR_AWS_EC2_PUBLIC_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
tls-auth ta.key 1
cipher AES-256-CBC
verb 3
comp-lzo
keepalive 10 120

# AWS EC2への接続後、プロキシサーバーへの通信を許可
route 10.0.0.0 255.255.0.0

# DNS設定
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4
EOF

sudo mv /tmp/client.conf /etc/openvpn/client/

# systemdサービス作成
cat > /tmp/openvpn-client.service << 'EOF'
[Unit]
Description=OpenVPN Client
After=network.target

[Service]
Type=notify
PrivateTmp=true
WorkingDirectory=/etc/openvpn/client
ExecStart=/usr/sbin/openvpn --daemon ovpn-client --status /run/openvpn/client.status 10 --cd /etc/openvpn/client --config /etc/openvpn/client/client.conf --writepid /run/openvpn/client.pid
PIDFile=/run/openvpn/client.pid
KillMode=process
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/openvpn-client.service /etc/systemd/system/

# ファイアウォール設定（UFWを使用している場合）
if command -v ufw >/dev/null 2>&1; then
    echo "Configuring firewall..."
    sudo ufw allow out 1194/udp
    sudo ufw allow out on tun0
fi

# IPフォワーディング有効化
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 証明書配置用ディレクトリの権限設定
sudo chown -R root:root /etc/openvpn/
sudo chmod -R 600 /etc/openvpn/keys/

echo "=== VPN Client Setup Completed ==="
echo ""
echo "Next steps:"
echo "1. AWS EC2でVPNサーバーをセットアップ"
echo "2. 生成された証明書ファイルを以下にコピー:"
echo "   - ca.crt -> /etc/openvpn/keys/"
echo "   - client.crt -> /etc/openvpn/keys/"
echo "   - client.key -> /etc/openvpn/keys/"
echo "   - ta.key -> /etc/openvpn/keys/"
echo "3. /etc/openvpn/client/client.confのYOUR_AWS_EC2_PUBLIC_IPを実際のIPに変更"
echo "4. VPN接続開始: sudo systemctl start openvpn-client"
echo "5. 自動起動有効化: sudo systemctl enable openvpn-client" 