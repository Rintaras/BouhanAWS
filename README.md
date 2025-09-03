# BouhanAWS - 防犯カメラシステム

Raspberry Pi を使用したリアルタイム防犯カメラシステムです。AWS IoT Core、Lambda、S3、CloudFrontを使用したクラウドネイティブな監視システムです。モーション検知、録画機能、LINE通知機能を搭載しています。

## 🏗️ アーキテクチャ概要

このシステムは以下のAWSサービスを活用したサーバーレスアーキテクチャで構築されています：

- **AWS IoT Core**: Raspberry Piとクラウド間のセキュアなMQTT通信
- **AWS Lambda**: サーバーレスAPI処理とLINE通知機能
- **Amazon S3**: フロントエンドアセットと録画ファイルの保存
- **Amazon CloudFront**: グローバルCDN配信とセキュリティ
- **Amazon DynamoDB**: セッション管理とユーザー認証
- **AWS API Gateway**: RESTful API エンドポイント
- **Amazon CloudWatch**: ログ管理とモニタリング

## 🌐 アクセス情報

### CloudFront URL (インターネット経由アクセス)
- **フロントエンドURL**: `https://YOUR_CLOUDFRONT_DISTRIBUTION_ID.cloudfront.net`
- **API Gateway URL**: `https://YOUR_API_GATEWAY_ID.execute-api.ap-northeast-1.amazonaws.com/prod`

> **設定方法**: 
> 1. AWS CloudFrontコンソールでDistribution IDを確認
> 2. AWS API GatewayコンソールでAPI Gateway URLを確認
> 3. 上記のプレースホルダーを実際のURLに置き換えてください

### ローカルアクセス
- **フロントエンドURL**: `http://localhost:5173`
- **カメラサーバーURL**: `http://YOUR_RASPBERRY_PI_IP:3000`

> **設定方法**: 
> 1. `YOUR_RASPBERRY_PI_IP`を実際のRaspberry PiのIPアドレスに置き換えてください
> 2. `ip addr show`コマンドでIPアドレスを確認できます

## 🔒 セキュリティとネットワークアクセス

### アクセス方法

#### CloudFrontアクセス（フル機能対応）
- **フロントエンドURL**: `https://YOUR_CLOUDFRONT_DISTRIBUTION_ID.cloudfront.net`
- **機能**: カメラ制御、監視、録画機能すべて利用可能
- **技術**: AWS IoT経由でのセキュアなカメラ制御

#### ローカルネットワークアクセス（直接制御）
- **フロントエンドURL**: `http://YOUR_RASPBERRY_PI_IP:8001`
- **カメラサーバーURL**: `http://YOUR_RASPBERRY_PI_IP:3000`
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
2. ローカルURL（`http://YOUR_RASPBERRY_PI_IP:8001`）でアクセス
3. カメラサーバーが起動していることを確認

## 🛠 技術スタック

### フロントエンド
- **フレームワーク**: React 18 + TypeScript 5 + Vite 4
- **UI**: CSS3 with custom animations and responsive design
- **状態管理**: React Hooks (useState, useEffect, useContext)
- **配信**: Amazon CloudFront + S3 Static Website Hosting
- **認証**: JWT-based authentication with session management

### バックエンド・API
- **カメラサーバー**: Python 3.11 + FastAPI (Raspberry Pi上で動作)
- **API Gateway**: AWS API Gateway with Lambda Proxy Integration
- **Lambda関数**: Node.js 18 (API proxy, LINE notification, IoT message handling)
- **データベース**: Amazon DynamoDB (session management, user data)
- **IoT通信**: AWS IoT Core (MQTT over TLS with X.509 certificates)

### クラウドインフラ
- **CDN**: Amazon CloudFront (Global distribution with edge caching)
- **ストレージ**: Amazon S3 (frontend assets, recordings, static files)
- **認証**: Custom JWT-based authentication with DynamoDB sessions
- **プロビジョニング**: Terraform 1.0+ (Infrastructure as Code)
- **監視**: CloudWatch Logs & Metrics with custom dashboards
- **セキュリティ**: AWS WAF (Web Application Firewall)

### セキュリティ・認証
- **HTTPS**: CloudFront enforced TLS 1.2+
- **CORS**: Properly configured for cross-origin requests
- **Geo-restriction**: Japan and US only (CloudFront geo-blocking)
- **IoT Security**: X.509 certificates for device authentication
- **API Security**: API Gateway throttling and rate limiting
- **Data Encryption**: S3 server-side encryption (SSE-S3)

### 開発・デプロイメント
- **バージョン管理**: Git with GitHub integration
- **CI/CD**: GitHub Actions (planned)
- **環境管理**: Terraform workspaces for dev/staging/prod
- **依存関係管理**: npm (Node.js), pip (Python), Terraform modules

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
- **ハードウェア**: Raspberry Pi 4 (8GB推奨) + Raspberry Pi Camera Module
- **OS**: Raspberry Pi OS (64-bit)
- **クラウド**: AWS アカウント (Free Tier対応)
- **開発環境**: 
  - Terraform v1.0+
  - Node.js v18+
  - Python 3.11+
  - Git
  - AWS CLI v2

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

### 🔧 URL設定方法

#### CloudFront Distribution IDの確認
```bash
# AWS CLIでCloudFront Distribution一覧を確認
aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,DomainName,Comment]' --output table

# またはTerraformの出力から確認
cd terraform
terraform output cloudfront_distribution_id
```

#### API Gateway URLの確認
```bash
# AWS CLIでAPI Gateway一覧を確認
aws apigateway get-rest-apis --query 'items[*].[id,name,createdDate]' --output table

# またはTerraformの出力から確認
cd terraform
terraform output api_gateway_url
```

#### Raspberry Pi IPアドレスの確認
```bash
# Raspberry PiでIPアドレスを確認
ip addr show | grep inet

# または
hostname -I
```

#### S3バケット名の確認
```bash
# AWS CLIでS3バケット一覧を確認
aws s3 ls

# またはTerraformの出力から確認
cd terraform
terraform output s3_bucket_name
```

4. **フロントエンドビルド & デプロイ**
```bash
cd monitor-client
npm run build
aws s3 sync dist/ s3://YOUR_S3_BUCKET_NAME/
aws cloudfront create-invalidation --distribution-id YOUR_DISTRIBUTION_ID --paths "/*"
```

5. **動作確認**
```bash
# CloudFrontからカメラ制御をテスト
curl -X POST "https://YOUR_CLOUDFRONT_DISTRIBUTION_ID.cloudfront.net/api/camera/start"
curl -X POST "https://YOUR_CLOUDFRONT_DISTRIBUTION_ID.cloudfront.net/api/camera/stop"

# ブラウザでアクセス
# https://YOUR_CLOUDFRONT_DISTRIBUTION_ID.cloudfront.net
```

> **注意**: 上記の`YOUR_S3_BUCKET_NAME`、`YOUR_DISTRIBUTION_ID`、`YOUR_CLOUDFRONT_DISTRIBUTION_ID`を実際の値に置き換えてください

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

1. CloudFrontURL (`https://YOUR_CLOUDFRONT_DISTRIBUTION_ID.cloudfront.net`) にアクセス
2. 「カメラを起動」ボタンをクリック
3. リアルタイムでカメラ映像を確認
4. 録画タブで過去の録画を確認・ダウンロード

> **設定**: `YOUR_CLOUDFRONT_DISTRIBUTION_ID`を実際のCloudFront Distribution IDに置き換えてください

## 🤝 貢献

プルリクエストやイシューの報告を歓迎します。

## 📄 ライセンス

MIT License

---

## 📊 システム構成図

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Raspberry Pi  │    │   AWS Cloud      │    │   End Users     │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │   Camera    │ │    │ │  CloudFront  │ │◄───┤ │   Browser   │ │
│ │   Module    │ │    │ │     CDN      │ │    │ │             │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
│                 │    │         │        │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │ FastAPI     │ │◄───┤ │ API Gateway  │ │◄───┤ │ Mobile App  │ │
│ │ Server      │ │    │ │              │ │    │ │             │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
│         │       │    │         │        │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │                 │
│ │ AWS IoT     │ │◄───┤ │ AWS IoT Core │ │    │                 │
│ │ Client      │ │    │ │              │ │    │                 │
│ └─────────────┘ │    │ └──────────────┘ │    │                 │
└─────────────────┘    │         │        │    └─────────────────┘
                       │ ┌──────────────┐ │
                       │ │   Lambda     │ │
                       │ │   Functions  │ │
                       │ └──────────────┘ │
                       │         │        │
                       │ ┌──────────────┐ │
                       │ │     S3       │ │
                       │ │   Storage    │ │
                       │ └──────────────┘ │
                       │         │        │
                       │ ┌──────────────┐ │
                       │ │  DynamoDB    │ │
                       │ │   Sessions   │ │
                       │ └──────────────┘ │
                       └──────────────────┘
```

**最終更新**: 2025年1月30日  
**バージョン**: 2.1.0  
**ステータス**: ✅ GitHub公開完了  
**リポジトリ**: https://github.com/Rintaras/BouhanAWS 