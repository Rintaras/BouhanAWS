#!/bin/bash

# AWS EC2用VPNサーバー設定スクリプト
# Raspberry Piからの接続を受け入れるOpenVPNサーバーを構築

set -e

echo "=== AWS EC2 VPN Server Setup ==="

# 必要なパッケージのインストール
echo "Installing required packages..."
yum update -y
yum install -y openvpn easy-rsa iptables-services

# Easy-RSA設定
echo "Setting up Easy-RSA..."
cd /etc/openvpn
cp -r /usr/share/easy-rsa/3.0.8 easy-rsa
cd easy-rsa

# PKI初期化
./easyrsa init-pki

# CA作成（自動化のため環境変数設定）
export EASYRSA_BATCH=1
export EASYRSA_REQ_CN="SecurityCameraVPN-CA"
./easyrsa build-ca nopass

# サーバー証明書作成
./easyrsa build-server-full server nopass

# クライアント証明書作成
./easyrsa build-client-full client nopass

# Diffie-Hellman パラメータ生成
./easyrsa gen-dh

# TLS認証キー生成
openvpn --genkey --secret ta.key

# 証明書を適切な場所にコピー
cp pki/ca.crt /etc/openvpn/
cp pki/issued/server.crt /etc/openvpn/
cp pki/private/server.key /etc/openvpn/
cp pki/dh.pem /etc/openvpn/
cp ta.key /etc/openvpn/

# OpenVPNサーバー設定ファイル作成
cat > /etc/openvpn/server.conf << 'EOF'
port 1194
proto udp
dev tun

ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0

server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

# Raspberry Piに固定IPを割り当て
client-config-dir ccd
route 192.168.1.0 255.255.255.0

push "route 10.0.0.0 255.255.0.0"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

keepalive 10 120
cipher AES-256-CBC
user nobody
group nobody
persist-key
persist-tun

status openvpn-status.log
verb 3

# ログ設定
log-append /var/log/openvpn.log
EOF

# クライアント設定ディレクトリ作成
mkdir -p /etc/openvpn/ccd

# Raspberry Pi用の固定IP設定
cat > /etc/openvpn/ccd/client << 'EOF'
ifconfig-push 10.8.0.10 10.8.0.9
EOF

# IPフォワーディング有効化
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# iptables設定
echo "Configuring iptables..."
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# iptables設定を永続化
service iptables save
systemctl enable iptables

# OpenVPN自動起動設定
systemctl enable openvpn@server
systemctl start openvpn@server

# クライアント用証明書ファイルの準備
echo "Preparing client certificates..."
mkdir -p /home/ec2-user/client-certs
cp /etc/openvpn/easy-rsa/pki/ca.crt /home/ec2-user/client-certs/
cp /etc/openvpn/easy-rsa/pki/issued/client.crt /home/ec2-user/client-certs/
cp /etc/openvpn/easy-rsa/pki/private/client.key /home/ec2-user/client-certs/
cp /etc/openvpn/ta.key /home/ec2-user/client-certs/

# 権限設定
chown -R ec2-user:ec2-user /home/ec2-user/client-certs
chmod 600 /home/ec2-user/client-certs/*

# クライアント設定ファイル生成
cat > /home/ec2-user/client-certs/client.ovpn << EOF
client
dev tun
proto udp
remote $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) 1194
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
EOF

echo "=== VPN Server Setup Completed ==="
echo ""
echo "VPN Server Information:"
echo "- Server IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "- Port: 1194 (UDP)"
echo "- Client certificates location: /home/ec2-user/client-certs/"
echo ""
echo "Next steps:"
echo "1. Download client certificates from /home/ec2-user/client-certs/"
echo "2. Copy certificates to Raspberry Pi"
echo "3. Start VPN client on Raspberry Pi"
echo ""
echo "Status check commands:"
echo "- systemctl status openvpn@server"
echo "- cat /var/log/openvpn.log"
echo "- cat /etc/openvpn/openvpn-status.log" 