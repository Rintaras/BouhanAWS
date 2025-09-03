# ポートフォワーディング設定ガイド

## 概要
外部からRaspberry Piのカメラサーバーにアクセスするため、ルーターでポートフォワーディングを設定します。

## 設定手順

### 1. Raspberry PiのローカルIP確認
```bash
hostname -I
# 出力例: 192.168.50.105
```

### 2. ルーター管理画面にアクセス
通常は以下のURLのいずれかでアクセス可能：
- http://192.168.1.1
- http://192.168.0.1
- http://10.0.0.1

### 3. ポートフォワーディング設定
ルーターの管理画面で以下を設定：

| 項目 | 値 |
|------|-----|
| 外部ポート | 443 |
| 内部ポート | 443 |
| プロトコル | TCP |
| 転送先IP | 192.168.50.105 |
| 説明 | Camera HTTPS |

### 4. 追加でHTTPも設定（オプション）
HTTPからHTTPSにリダイレクトするため：

| 項目 | 値 |
|------|-----|
| 外部ポート | 80 |
| 内部ポート | 80 |
| プロトコル | TCP |
| 転送先IP | 192.168.50.105 |
| 説明 | Camera HTTP |

## テスト方法

### 内部テスト（設定前後両方で確認）
```bash
# HTTPSテスト
curl -k -s "https://192.168.50.105/camera-status"

# HTTPテスト（リダイレクト確認）
curl -s "http://192.168.50.105/camera-status"
```

### 外部テスト（設定後のみ）
```bash
# HTTPSテスト
curl -k -s "https://133.43.7.18/camera-status"

# HTTPテスト（リダイレクト確認）
curl -s "http://133.43.7.18/camera-status"
```

## 注意事項

1. **セキュリティ**: 外部からアクセス可能になるため、認証を強化することを推奨
2. **証明書**: 自己署名証明書を使用するため、ブラウザで警告が表示されます
3. **ファイアウォール**: 必要に応じてファイアウォール設定も確認してください

## トラブルシューティング

### ポートが開いているか確認
```bash
# 外部から確認（オンラインツール）
# https://www.yougetsignal.com/tools/open-ports/

# 内部から確認
nmap -p 80,443 192.168.50.105
```

### Nginxログ確認
```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### サービス状態確認
```bash
sudo systemctl status nginx
sudo systemctl status camera-server
```

## 設定完了後のURL

- **外部HTTPS**: https://133.43.7.18
- **内部HTTPS**: https://192.168.50.105
- **フロントエンド**: https://d1dc57z0cxlh4u.cloudfront.net 