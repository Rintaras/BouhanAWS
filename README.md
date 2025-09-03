# 防犯カメラシステム

Raspberry Pi を使用したリアルタイム防犯カメラシステムです。モーション検知、録画機能、LINE通知機能を搭載しています。

## 🌐 アクセス情報

### CloudFront URL (インターネット経由アクセス)
- **フロントエンドURL**: https://d1ayuibfpvx6ov.cloudfront.net
- **API Gateway URL**: https://j5793ql583.execute-api.ap-northeast-1.amazonaws.com/prod

### ローカルアクセス
- **フロントエンドURL**: http://localhost:5173
- **カメラサーバーURL**: http://172.20.10.2:3000

## 🔒 セキュリティとネットワークアクセス

### アクセス方法

#### CloudFrontアクセス（フル機能対応）
- **フロントエンドURL**: https://d1ayuibfpvx6ov.cloudfront.net
- **機能**: カメラ制御、監視、録画機能すべて利用可能
- **技術**: AWS IoT経由でのセキュアなカメラ制御

#### ローカルネットワークアクセス（直接制御）
- **フロントエンドURL**: http://172.20.10.2:8001
- **カメラサーバーURL**: http://172.20.10.2:3000
- **要件**: Raspberry Piと同じWi-Fiネットワークに接続

### セキュリティ仕様

1. **AWS IoT経由制御**: 
   - CloudFrontからのカメラ制御はAWS IoT Core経由で実行
   - Lambda関数でIoTメッセージをパブリッシュ
   - セキュアなMQTT通信でコマンド送信

2. **認証システム**: 
   - JWT based authentication
   - セッション管理（DynamoDB）

3. **通信暗号化**: 
   - HTTPS/TLS 1.2+ のみ
   - API Gateway + Lambda プロキシ
   - AWS IoT Core MQTT over TLS

4. **地域制限**: 
   - CloudFront で日本・米国のみアクセス許可

### トラブルシューティング

#### CloudFrontからカメラ制御が動作しない場合

**症状**: 「カメラを起動」ボタンが反応しない
**原因**: ネットワーク接続問題またはAWS IoT接続問題

**解決方法**:
1. ブラウザの開発者ツールでネットワークエラーを確認
2. AWS IoTコンソールでメッセージ送受信状況を確認
3. Lambda関数のCloudWatchログを確認

#### ローカルアクセスでカメラが起動しない場合

**症状**: ローカルネットワークからカメラ制御できない

**解決方法**:
1. Raspberry Piと同じWi-Fiネットワークに接続
2. ローカルURL（http://172.20.10.2:8001）でアクセス
3. カメラサーバーが起動していることを確認

## 🛠 技術スタック

### フロントエンド
- **フレームワーク**: React + TypeScript + Vite
- **UI**: CSS3 with custom animations and responsive design
- **配信**: Amazon CloudFront + S3

### バックエンド
- **カメラサーバー**: Python FastAPI (Raspberry Pi上で動作)
- **API Gateway**: AWS API Gateway with Lambda Proxy
- **Lambda関数**: Node.js (API proxy, LINE notification)
- **データベース**: Amazon DynamoDB (session management)
- **IoT通信**: AWS IoT Core (MQTT)

### インフラ
- **CDN**: Amazon CloudFront
- **ストレージ**: Amazon S3 (frontend assets, recordings)
- **認証**: Custom JWT-based authentication
- **プロビジョニング**: Terraform
- **監視**: CloudWatch Logs & Metrics

### セキュリティ
- **HTTPS**: CloudFront enforced
- **CORS**: Properly configured for cross-origin requests
- **Geo-restriction**: Japan and US only
- **IoT Security**: X.509 certificates for device authentication

## 📋 主要機能

- 🎥 **リアルタイム映像配信**: Raspberry Pi カメラからのライブストリーミング
- 🚨 **モーション検知**: 動体検出時の自動録画開始
- 📹 **録画機能**: 動画ファイルの保存とダウンロード
- 📱 **LINE通知**: モーション検知時のLINE通知機能
- 🌐 **CloudFrontアクセス**: インターネットからフル機能利用可能
- ☁️ **AWS IoT制御**: セキュアなIoT経由でのリモートカメラ制御
- 🔐 **セキュア認証**: JWT based authentication system
- 📊 **リアルタイム監視**: システム状態とカメラステータスの監視

## 🚀 セットアップ方法

### 必要な環境
- Raspberry Pi (カメラ接続済み)
- AWS アカウント
- Terraform v1.0+
- Node.js v18+
- Python 3.8+

### デプロイ手順

1. **Raspberry Piサーバー起動**
```bash
cd camera-server
python3 main.py
```

2. **フロントエンド開発サーバー起動**
```bash
cd monitor-client
npm install
npm run dev
```

3. **AWS インフラデプロイ**
```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

4. **フロントエンドビルド & デプロイ**
```bash
cd monitor-client
npm run build
aws s3 sync dist/ s3://security-camera-frontend-serverless-2024/
aws cloudfront create-invalidation --distribution-id E1VLB4DPLHSE34 --paths "/*"
```

5. **動作確認**
```bash
# CloudFrontからカメラ制御をテスト
curl -X POST "https://d1ayuibfpvx6ov.cloudfront.net/api/camera/start"
curl -X POST "https://d1ayuibfpvx6ov.cloudfront.net/api/camera/stop"

# ブラウザでアクセス
# https://d1ayuibfpvx6ov.cloudfront.net
```

## 💰 推定コスト

| サービス | 月額コスト (推定) |
|---------|----------------|
| Lambda | ~$2.00 |
| API Gateway | ~$3.50 |
| CloudFront | ~$1.00 |
| S3 Storage | ~$0.50 |
| DynamoDB | ~$1.25 |
| IoT Core | ~$0.80 |
| CloudWatch | ~$2.00 |
| **合計** | **~$11.05/月** |

## 🔧 トラブルシューティング

### カメラサーバーが起動しない
```bash
# 依存関係インストール
pip3 install -r camera-server/requirements.txt

# ポート確認
sudo netstat -tulpn | grep :3000
```

### CloudFrontでCORSエラーが発生する
- Lambda関数が正しいCORSヘッダーを返していることを確認
- CloudFrontのCache Behaviorが適切に設定されていることを確認

### LINE通知が動作しない
```bash
# LINE Messaging API設定確認
cat camera-server/line_messaging_config.txt
```

## 📚 API エンドポイント

| エンドポイント | メソッド | 説明 |
|-------------|--------|------|
| `/api/health` | GET | システムヘルスチェック |
| `/api/camera-status` | GET | カメラステータス確認 |
| `/api/camera/start` | POST | カメラ起動 |
| `/api/camera/stop` | POST | カメラ停止 |
| `/api/video-frame` | GET | 現在のフレーム取得 |
| `/api/line-messaging/status` | GET | LINE通知ステータス |
| `/api/recordings` | GET | 録画一覧取得 |

## 📱 使用方法

1. CloudFrontURL (https://d1ayuibfpvx6ov.cloudfront.net) にアクセス
2. 「カメラを起動」ボタンをクリック
3. リアルタイムでカメラ映像を確認
4. 録画タブで過去の録画を確認・ダウンロード

## 🤝 貢献

プルリクエストやイシューの報告を歓迎します。

## 📄 ライセンス

MIT License

---

**最終更新**: 2025年7月30日  
**バージョン**: 2.0.0  
**ステータス**: ✅ CloudFront対応完了 