# Terraform - 防犯カメラシステム AWS インフラ

このディレクトリには、防犯カメラシステムのAWSインフラを管理するTerraform設定ファイルが含まれています。

## 📁 ファイル構成

```
terraform/
├── main.tf                    # メイン設定ファイル
├── variables.tf               # 変数定義
├── outputs.tf                 # 出力定義
├── terraform.tfvars.example   # 変数値例
├── lambda-function.js         # Lambda関数コード
└── README.md                  # このファイル
```

## 🚀 使用方法

### 1. 前提条件

- **Terraform** (>= 1.0) がインストールされていること
- **AWS CLI** が設定されていること
- **AWS認証情報** が設定されていること

### 2. 初期設定

```bash
# 1. ディレクトリに移動
cd terraform

# 2. 変数ファイルを作成
cp terraform.tfvars.example terraform.tfvars

# 3. 変数ファイルを編集
nano terraform.tfvars
```

### 3. 必須設定項目

```hcl
# terraform.tfvars
aws_region = "ap-northeast-1"
environment = "production"

# ラズパイ設定（重要！）
raspberry_pi_ip = "192.168.1.100"
raspberry_pi_port = "3000"

# S3設定
s3_bucket_name = "security-camera-frontend"

# Lambda設定
lambda_function_name = "security-camera-api-proxy"
```

### 4. Terraform の実行

```bash
# 1. 初期化
terraform init

# 2. プラン確認
terraform plan

# 3. インフラ作成
terraform apply

# 4. 出力確認
terraform output
```

## 🏗️ 作成されるリソース

### 1. S3 バケット
- **静的ウェブサイトホスティング** 有効
- **バージョニング** 有効
- **公開アクセス** 設定済み

### 2. CloudFront ディストリビューション
- **CDN** 機能
- **HTTPS** 対応
- **キャッシュ** 設定済み
- **WAF** 関連付け済み

### 3. Lambda 関数
- **API プロキシ** 機能
- **CORS** 対応
- **ヘルスチェック** 機能
- **ログ** 出力

### 4. WAF Web ACL
- **レート制限** (2000リクエスト/分)
- **地理制限** (日本・アメリカ)
- **IP制限** (オプション)
- **監視** 機能

### 5. CloudWatch
- **ロググループ** (Lambda・WAF)
- **アラーム** (エラー・ブロック)
- **メトリクス** 監視

### 6. SNS
- **アラートトピック**
- **メール通知** (オプション)

## 🔧 設定オプション

### カスタムドメイン設定
```hcl
# terraform.tfvars
custom_domain = "security-camera.yourdomain.com"
ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-certificate-id"
```

### セキュリティ強化
```hcl
# terraform.tfvars
waf_blocked_ips = ["192.168.1.1", "10.0.0.1"]
alert_email = "admin@yourdomain.com"
basic_auth_password = "your-secure-password"
```

### パフォーマンス調整
```hcl
# terraform.tfvars
lambda_timeout = 30
lambda_memory_size = 128
waf_rate_limit = 2000
```

## 📊 出力情報

### アクセスURL
```bash
# フロントエンドURL
terraform output frontend_url

# API URL
terraform output api_url
```

### リソース情報
```bash
# 設定サマリー
terraform output configuration_summary

# セキュリティ情報
terraform output security_info

# コスト見積もり
terraform output cost_estimation
```

## 🔄 更新・削除

### 設定更新
```bash
# 1. 変数ファイルを編集
nano terraform.tfvars

# 2. プラン確認
terraform plan

# 3. 更新実行
terraform apply
```

### インフラ削除
```bash
# 注意: すべてのリソースが削除されます
terraform destroy
```

## 🛠️ トラブルシューティング

### よくある問題

#### 1. S3バケット名の重複
```bash
# エラー: Bucket already exists
# 解決: terraform.tfvars でバケット名を変更
s3_bucket_name = "security-camera-frontend-unique"
```

#### 2. Lambda関数のデプロイエラー
```bash
# エラー: Lambda function deployment failed
# 解決: Lambda関数コードを再作成
zip -r lambda-function.zip lambda-function.js
terraform apply
```

#### 3. WAF Web ACL の作成エラー
```bash
# エラー: WAF Web ACL creation failed
# 解決: リージョンを確認
aws_region = "ap-northeast-1"  # WAFv2対応リージョン
```

### ログ確認
```bash
# Lambda ログ
aws logs tail /aws/lambda/security-camera-api-proxy --follow

# WAF ログ
aws logs tail /aws/wafv2/security-camera --follow
```

## 💰 コスト管理

### 月額コスト見積もり
- **S3**: ~$0.50/月
- **CloudFront**: ~$1.00/月
- **Lambda**: ~$2.00/月
- **WAF**: ~$5.00/月
- **CloudWatch**: ~$1.00/月
- **合計**: ~$9.50/月

### コスト最適化
```hcl
# terraform.tfvars
# ログ保持期間を短縮
log_retention_days = 30

# WAFレート制限を調整
waf_rate_limit = 1000

# Lambdaメモリを最適化
lambda_memory_size = 128
```

## 🔒 セキュリティ

### 推奨設定
1. **IAMロール** の最小権限原則
2. **WAF** による攻撃防御
3. **CloudWatch** による監視
4. **SNS** によるアラート通知

### セキュリティチェックリスト
- [ ] ラズパイのIPアドレスが固定されている
- [ ] ファイアウォールが設定されている
- [ ] WAFレート制限が適切に設定されている
- [ ] ログ監視が有効になっている
- [ ] アラート通知が設定されている

## 📝 注意事項

1. **状態ファイル**: S3バックエンドを使用して状態ファイルを安全に管理
2. **機密情報**: `terraform.tfvars` に機密情報を含めない
3. **バックアップ**: 重要な設定はバージョン管理に含める
4. **テスト**: 本番環境に適用前にテスト環境で検証

## 🆘 サポート

問題が発生した場合は、以下を確認してください：

1. **Terraform バージョン**: `terraform version`
2. **AWS CLI 設定**: `aws sts get-caller-identity`
3. **ログ確認**: CloudWatch ログを確認
4. **リソース状態**: `terraform state list` 

このディレクトリには、防犯カメラシステムのAWSインフラを管理するTerraform設定ファイルが含まれています。

## 📁 ファイル構成

```
terraform/
├── main.tf                    # メイン設定ファイル
├── variables.tf               # 変数定義
├── outputs.tf                 # 出力定義
├── terraform.tfvars.example   # 変数値例
├── lambda-function.js         # Lambda関数コード
└── README.md                  # このファイル
```

## 🚀 使用方法

### 1. 前提条件

- **Terraform** (>= 1.0) がインストールされていること
- **AWS CLI** が設定されていること
- **AWS認証情報** が設定されていること

### 2. 初期設定

```bash
# 1. ディレクトリに移動
cd terraform

# 2. 変数ファイルを作成
cp terraform.tfvars.example terraform.tfvars

# 3. 変数ファイルを編集
nano terraform.tfvars
```

### 3. 必須設定項目

```hcl
# terraform.tfvars
aws_region = "ap-northeast-1"
environment = "production"

# ラズパイ設定（重要！）
raspberry_pi_ip = "192.168.1.100"
raspberry_pi_port = "3000"

# S3設定
s3_bucket_name = "security-camera-frontend"

# Lambda設定
lambda_function_name = "security-camera-api-proxy"
```

### 4. Terraform の実行

```bash
# 1. 初期化
terraform init

# 2. プラン確認
terraform plan

# 3. インフラ作成
terraform apply

# 4. 出力確認
terraform output
```

## 🏗️ 作成されるリソース

### 1. S3 バケット
- **静的ウェブサイトホスティング** 有効
- **バージョニング** 有効
- **公開アクセス** 設定済み

### 2. CloudFront ディストリビューション
- **CDN** 機能
- **HTTPS** 対応
- **キャッシュ** 設定済み
- **WAF** 関連付け済み

### 3. Lambda 関数
- **API プロキシ** 機能
- **CORS** 対応
- **ヘルスチェック** 機能
- **ログ** 出力

### 4. WAF Web ACL
- **レート制限** (2000リクエスト/分)
- **地理制限** (日本・アメリカ)
- **IP制限** (オプション)
- **監視** 機能

### 5. CloudWatch
- **ロググループ** (Lambda・WAF)
- **アラーム** (エラー・ブロック)
- **メトリクス** 監視

### 6. SNS
- **アラートトピック**
- **メール通知** (オプション)

## 🔧 設定オプション

### カスタムドメイン設定
```hcl
# terraform.tfvars
custom_domain = "security-camera.yourdomain.com"
ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-certificate-id"
```

### セキュリティ強化
```hcl
# terraform.tfvars
waf_blocked_ips = ["192.168.1.1", "10.0.0.1"]
alert_email = "admin@yourdomain.com"
basic_auth_password = "your-secure-password"
```

### パフォーマンス調整
```hcl
# terraform.tfvars
lambda_timeout = 30
lambda_memory_size = 128
waf_rate_limit = 2000
```

## 📊 出力情報

### アクセスURL
```bash
# フロントエンドURL
terraform output frontend_url

# API URL
terraform output api_url
```

### リソース情報
```bash
# 設定サマリー
terraform output configuration_summary

# セキュリティ情報
terraform output security_info

# コスト見積もり
terraform output cost_estimation
```

## 🔄 更新・削除

### 設定更新
```bash
# 1. 変数ファイルを編集
nano terraform.tfvars

# 2. プラン確認
terraform plan

# 3. 更新実行
terraform apply
```

### インフラ削除
```bash
# 注意: すべてのリソースが削除されます
terraform destroy
```

## 🛠️ トラブルシューティング

### よくある問題

#### 1. S3バケット名の重複
```bash
# エラー: Bucket already exists
# 解決: terraform.tfvars でバケット名を変更
s3_bucket_name = "security-camera-frontend-unique"
```

#### 2. Lambda関数のデプロイエラー
```bash
# エラー: Lambda function deployment failed
# 解決: Lambda関数コードを再作成
zip -r lambda-function.zip lambda-function.js
terraform apply
```

#### 3. WAF Web ACL の作成エラー
```bash
# エラー: WAF Web ACL creation failed
# 解決: リージョンを確認
aws_region = "ap-northeast-1"  # WAFv2対応リージョン
```

### ログ確認
```bash
# Lambda ログ
aws logs tail /aws/lambda/security-camera-api-proxy --follow

# WAF ログ
aws logs tail /aws/wafv2/security-camera --follow
```

## 💰 コスト管理

### 月額コスト見積もり
- **S3**: ~$0.50/月
- **CloudFront**: ~$1.00/月
- **Lambda**: ~$2.00/月
- **WAF**: ~$5.00/月
- **CloudWatch**: ~$1.00/月
- **合計**: ~$9.50/月

### コスト最適化
```hcl
# terraform.tfvars
# ログ保持期間を短縮
log_retention_days = 30

# WAFレート制限を調整
waf_rate_limit = 1000

# Lambdaメモリを最適化
lambda_memory_size = 128
```

## 🔒 セキュリティ

### 推奨設定
1. **IAMロール** の最小権限原則
2. **WAF** による攻撃防御
3. **CloudWatch** による監視
4. **SNS** によるアラート通知

### セキュリティチェックリスト
- [ ] ラズパイのIPアドレスが固定されている
- [ ] ファイアウォールが設定されている
- [ ] WAFレート制限が適切に設定されている
- [ ] ログ監視が有効になっている
- [ ] アラート通知が設定されている

## 📝 注意事項

1. **状態ファイル**: S3バックエンドを使用して状態ファイルを安全に管理
2. **機密情報**: `terraform.tfvars` に機密情報を含めない
3. **バックアップ**: 重要な設定はバージョン管理に含める
4. **テスト**: 本番環境に適用前にテスト環境で検証

## 🆘 サポート

問題が発生した場合は、以下を確認してください：

1. **Terraform バージョン**: `terraform version`
2. **AWS CLI 設定**: `aws sts get-caller-identity`
3. **ログ確認**: CloudWatch ログを確認
4. **リソース状態**: `terraform state list` 
 