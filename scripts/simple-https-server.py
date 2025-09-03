#!/usr/bin/env python3
"""
HTTPS対応の簡単なリバースプロキシサーバー
ルーター設定不要で外部アクセス可能
"""

import http.server
import socketserver
import ssl
import urllib.request
import urllib.parse
import urllib.error
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler


class CameraProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            # カメラサーバーにリクエストを転送
            url = f"http://localhost:3000{self.path}"
            req = urllib.request.Request(url)

            # レスポンスを取得
            with urllib.request.urlopen(req) as response:
                data = response.read()

            # CORSヘッダーを追加
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods',
                             'GET, POST, PUT, DELETE, OPTIONS')
            self.send_header('Access-Control-Allow-Headers',
                             'Content-Type, Authorization')
            self.end_headers()

            self.wfile.write(data)

        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            error_response = json.dumps({"error": str(e)})
            self.wfile.write(error_response.encode())

    def do_POST(self):
        try:
            # リクエストボディを読み取り
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)

            # カメラサーバーにリクエストを転送
            url = f"http://localhost:3000{self.path}"
            req = urllib.request.Request(url, data=post_data, method='POST')
            req.add_header('Content-Type', 'application/json')

            # レスポンスを取得
            with urllib.request.urlopen(req) as response:
                data = response.read()

            # CORSヘッダーを追加
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods',
                             'GET, POST, PUT, DELETE, OPTIONS')
            self.send_header('Access-Control-Allow-Headers',
                             'Content-Type, Authorization')
            self.end_headers()

            self.wfile.write(data)

        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            error_response = json.dumps({"error": str(e)})
            self.wfile.write(error_response.encode())

    def do_OPTIONS(self):
        # CORS preflight リクエストの処理
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods',
                         'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers',
                         'Content-Type, Authorization')
        self.end_headers()


def create_ssl_context():
    """自己署名証明書を作成"""
    import subprocess
    import os

    if not os.path.exists('server.key') or not os.path.exists('server.crt'):
        print("自己署名証明書を作成しています...")
        subprocess.run([
            'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
            '-keyout', 'server.key', '-out', 'server.crt',
            '-days', '365', '-nodes',
            '-subj', '/C=JP/ST=Tokyo/L=Tokyo/O=CameraSystem/CN=localhost'
        ], check=True)
        print("✅ 証明書を作成しました")

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain('server.crt', 'server.key')
    return context


def main():
    PORT = 8443

    # HTTPSサーバーの作成
    httpd = HTTPServer(('0.0.0.0', PORT), CameraProxyHandler)
    httpd.socket = create_ssl_context().wrap_socket(httpd.socket, server_side=True)

    print(f"🚀 HTTPS プロキシサーバーを起動しました")
    print(f"📱 URL: https://localhost:{PORT}")
    print(f"🌐 外部アクセス: https://133.43.7.18:{PORT}")
    print(f"📋 フロントエンドの設定を更新してください")
    print(f"⏹️  停止するには Ctrl+C を押してください")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 サーバーを停止しました")
        httpd.server_close()


if __name__ == '__main__':
    main()
