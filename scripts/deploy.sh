#!/bin/bash

# 防犯カメラシステム AWS クラウドデプロイメントスクリプト
set -e

echo "=== 防犯カメラシステム AWS デプロイメント ==="

# 設定変数
TERRAFORM_DIR="terraform"
RASPBERRY_PI_IP=""
DOMAIN_NAME=""
KEY_PAIR_NAME=""
ALERT_EMAIL=""

# 引数の解析
while [[ $# -gt 0 ]]; do
  case $1 in
    --raspberry-pi-ip)
      RASPBERRY_PI_IP="$2"
      shift 2
      ;;
    --domain-name)
      DOMAIN_NAME="$2"
      shift 2
      ;;
    --key-pair-name)
      KEY_PAIR_NAME="$2"
      shift 2
      ;;
    --alert-email)
      ALERT_EMAIL="$2"
      shift 2
      ;;
    --help)
      echo "使用方法: $0 [オプション]"
      echo ""
      echo "オプション:"
      echo "  --raspberry-pi-ip   Raspberry PiのIPアドレス (必須)"
      echo "  --domain-name       ドメイン名 (SSL証明書用、オプション)"
      echo "  --key-pair-name     EC2キーペア名 (必須)"
      echo "  --alert-email       アラート通知用メールアドレス (オプション)"
      echo "  --help              このヘルプを表示"
      echo ""
      echo "例:"
      echo "  $0 --raspberry-pi-ip 192.168.1.100 --key-pair-name my-key --domain-name camera.example.com --alert-email admin@example.com"
      exit 0
      ;;
    *)
      echo "不明なオプション: $1"
      echo "ヘルプを表示するには --help を使用してください"
      exit 1
      ;;
  esac
done

# 必須パラメータのチェック
if [[ -z "$RASPBERRY_PI_IP" ]]; then
  echo "エラー: --raspberry-pi-ip パラメータが必要です"
  exit 1
fi

if [[ -z "$KEY_PAIR_NAME" ]]; then
  echo "エラー: --key-pair-name パラメータが必要です"
  exit 1
fi

# AWS CLIの確認
if ! command -v aws &> /dev/null; then
  echo "エラー: AWS CLIがインストールされていません"
  echo "AWS CLIをインストールして設定してください"
  exit 1
fi

# Terraformの確認
if ! command -v terraform &> /dev/null; then
  echo "エラー: Terraformがインストールされていません"
  echo "Terraformをインストールしてください"
  exit 1
fi

# AWS認証情報の確認
echo "AWS認証情報を確認中..."
if ! aws sts get-caller-identity &> /dev/null; then
  echo "エラー: AWS認証情報が設定されていません"
  echo "aws configure を実行して認証情報を設定してください"
  exit 1
fi

echo "認証情報OK: $(aws sts get-caller-identity --query 'Arn' --output text)"

# EC2キーペアの存在確認
echo "EC2キーペアの確認中..."
if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" &> /dev/null; then
  echo "エラー: キーペア '$KEY_PAIR_NAME' が存在しません"
  echo "EC2コンソールでキーペアを作成するか、既存のキーペア名を指定してください"
  exit 1
fi

echo "キーペアOK: $KEY_PAIR_NAME"

# Terraformディレクトリに移動
cd "$TERRAFORM_DIR"

# Terraform変数ファイルの作成
echo "Terraform変数ファイルを作成中..."
cat > terraform.tfvars << EOF
raspberry_pi_ip = "$RASPBERRY_PI_IP"
key_pair_name   = "$KEY_PAIR_NAME"
EOF

# オプション変数の追加
if [[ -n "$DOMAIN_NAME" ]]; then
  echo "domain_name = \"$DOMAIN_NAME\"" >> terraform.tfvars
  echo "manage_dns_with_route53 = true" >> terraform.tfvars
fi

if [[ -n "$ALERT_EMAIL" ]]; then
  echo "alert_email = \"$ALERT_EMAIL\"" >> terraform.tfvars
fi

# Terraform初期化
echo "Terraformを初期化中..."
terraform init

# Terraformプランの実行
echo "Terraformプランを作成中..."
terraform plan -out=tfplan

# ユーザー確認
echo ""
echo "=== デプロイメント確認 ==="
echo "Raspberry Pi IP: $RASPBERRY_PI_IP"
echo "キーペア名: $KEY_PAIR_NAME"
if [[ -n "$DOMAIN_NAME" ]]; then
  echo "ドメイン名: $DOMAIN_NAME"
fi
if [[ -n "$ALERT_EMAIL" ]]; then
  echo "アラートメール: $ALERT_EMAIL"
fi
echo ""
echo "上記の設定でAWSリソースをデプロイしますか？"
echo "このデプロイメントには料金が発生します。"
read -p "続行しますか？ (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "デプロイメントをキャンセルしました"
  exit 0
fi

# Terraformアプライ
echo "Terraformアプライを実行中..."
terraform apply tfplan

# 出力の表示
echo ""
echo "=== デプロイメント完了 ==="
echo ""
echo "ALB DNS名: $(terraform output -raw alb_dns_name)"
echo "プロキシサーバーIP: $(terraform output -raw proxy_server_public_ip)"

if [[ -n "$DOMAIN_NAME" ]]; then
  echo "アクセスURL: https://$DOMAIN_NAME"
else
  echo "アクセスURL: http://$(terraform output -raw alb_dns_name)"
fi

echo ""
echo "=== 次のステップ ==="
echo "1. VPN証明書をダウンロード:"
echo "   scp -i ~/.ssh/$KEY_PAIR_NAME.pem ec2-user@$(terraform output -raw proxy_server_public_ip):/home/ec2-user/client-certs/* ."
echo ""
echo "2. Raspberry Piでの設定:"
echo "   - VPN証明書を /etc/openvpn/keys/ にコピー"
echo "   - scripts/setup-vpn-client.sh を実行"
echo "   - VPN接続を開始: sudo systemctl start openvpn-client"
echo ""
echo "3. システム監視:"
echo "   - CloudWatchダッシュボード: https://console.aws.amazon.com/cloudwatch/home#dashboards:name=SecurityCameraSystem"
if [[ -n "$ALERT_EMAIL" ]]; then
  echo "   - アラートメールの確認とSNS購読の承認"
fi
echo ""
echo "デプロイメントが完了しました！" 