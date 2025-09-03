#!/bin/bash

# ========================================
# Terraform デプロイスクリプト
# 防犯カメラシステム AWS インフラ
# ========================================

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ヘルプ表示
show_help() {
    echo "使用方法: $0 [オプション]"
    echo ""
    echo "オプション:"
    echo "  init      Terraformを初期化"
    echo "  plan      デプロイプランを表示"
    echo "  apply     インフラを作成・更新"
    echo "  destroy   インフラを削除"
    echo "  output    出力情報を表示"
    echo "  validate  設定を検証"
    echo "  format    コードをフォーマット"
    echo "  help      このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0 init"
    echo "  $0 plan"
    echo "  $0 apply"
}

# 前提条件チェック
check_prerequisites() {
    log_info "前提条件をチェックしています..."
    
    # Terraform のインストール確認
    if ! command -v terraform &> /dev/null; then
        log_error "Terraformがインストールされていません"
        echo "インストール方法: https://www.terraform.io/downloads.html"
        exit 1
    fi
    
    # AWS CLI のインストール確認
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLIがインストールされていません"
        echo "インストール方法: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    # AWS認証情報の確認
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証情報が設定されていません"
        echo "設定方法: aws configure"
        exit 1
    fi
    
    # terraform.tfvars の存在確認
    if [ ! -f "terraform.tfvars" ]; then
        log_warning "terraform.tfvarsファイルが見つかりません"
        if [ -f "terraform.tfvars.example" ]; then
            log_info "terraform.tfvars.exampleをコピーして設定してください"
            echo "cp terraform.tfvars.example terraform.tfvars"
        fi
        exit 1
    fi
    
    log_success "前提条件チェック完了"
}

# Terraform初期化
terraform_init() {
    log_info "Terraformを初期化しています..."
    
    # S3バケットの存在確認（バックエンド用）
    BACKEND_BUCKET="security-camera-terraform-state"
    if ! aws s3 ls "s3://$BACKEND_BUCKET" &> /dev/null; then
        log_info "Terraform状態ファイル用のS3バケットを作成しています..."
        aws s3 mb "s3://$BACKEND_BUCKET" --region ap-northeast-1
        aws s3api put-bucket-versioning --bucket "$BACKEND_BUCKET" --versioning-configuration Status=Enabled
    fi
    
    terraform init
    log_success "Terraform初期化完了"
}

# 設定検証
terraform_validate() {
    log_info "Terraform設定を検証しています..."
    terraform validate
    log_success "設定検証完了"
}

# コードフォーマット
terraform_format() {
    log_info "Terraformコードをフォーマットしています..."
    terraform fmt -recursive
    log_success "コードフォーマット完了"
}

# デプロイプラン表示
terraform_plan() {
    log_info "デプロイプランを表示しています..."
    terraform plan
    log_success "プラン表示完了"
}

# インフラ作成・更新
terraform_apply() {
    log_info "インフラを作成・更新しています..."
    
    # 確認プロンプト
    read -p "本当にインフラを作成・更新しますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "キャンセルされました"
        exit 0
    fi
    
    terraform apply -auto-approve
    log_success "インフラ作成・更新完了"
    
    # 出力情報を表示
    echo ""
    log_info "作成されたリソース情報:"
    terraform output
}

# インフラ削除
terraform_destroy() {
    log_warning "インフラを削除します。この操作は取り消せません。"
    
    # 確認プロンプト
    read -p "本当にすべてのリソースを削除しますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "キャンセルされました"
        exit 0
    fi
    
    log_info "インフラを削除しています..."
    terraform destroy -auto-approve
    log_success "インフラ削除完了"
}

# 出力情報表示
terraform_output() {
    log_info "出力情報を表示しています..."
    terraform output
}

# Lambda関数のデプロイ
deploy_lambda() {
    log_info "Lambda関数をデプロイしています..."
    
    # Lambda関数コードをZIP化
    if [ -f "lambda-function.js" ]; then
        zip -r lambda-function.zip lambda-function.js
        log_success "Lambda関数コードをZIP化しました"
    else
        log_error "lambda-function.jsが見つかりません"
        exit 1
    fi
}

# フロントエンドのデプロイ
deploy_frontend() {
    log_info "フロントエンドをデプロイしています..."
    
    # フロントエンドをビルド
    cd ../monitor-client
    npm install
    npm run build
    
    # S3にアップロード
    BUCKET_NAME=$(terraform -chdir=../terraform output -raw s3_bucket_name)
    aws s3 sync dist/ "s3://$BUCKET_NAME" --delete
    
    # CloudFrontキャッシュ無効化
    DISTRIBUTION_ID=$(terraform -chdir=../terraform output -raw cloudfront_distribution_id)
    aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*"
    
    cd ../terraform
    log_success "フロントエンドデプロイ完了"
}

# ヘルスチェック
health_check() {
    log_info "ヘルスチェックを実行しています..."
    
    # Lambda関数のヘルスチェック
    FUNCTION_URL=$(terraform output -raw lambda_function_url)
    if curl -f "$FUNCTION_URL/health" &> /dev/null; then
        log_success "Lambda関数: 正常"
    else
        log_error "Lambda関数: 異常"
    fi
    
    # CloudFrontのヘルスチェック
    FRONTEND_URL=$(terraform output -raw frontend_url)
    if curl -f "$FRONTEND_URL" &> /dev/null; then
        log_success "CloudFront: 正常"
    else
        log_error "CloudFront: 異常"
    fi
}

# メイン処理
main() {
    case "${1:-help}" in
        "init")
            check_prerequisites
            terraform_init
            ;;
        "validate")
            check_prerequisites
            terraform_validate
            ;;
        "format")
            terraform_format
            ;;
        "plan")
            check_prerequisites
            terraform_plan
            ;;
        "apply")
            check_prerequisites
            deploy_lambda
            terraform_apply
            deploy_frontend
            health_check
            ;;
        "destroy")
            check_prerequisites
            terraform_destroy
            ;;
        "output")
            check_prerequisites
            terraform_output
            ;;
        "deploy")
            check_prerequisites
            deploy_lambda
            terraform_apply
            deploy_frontend
            health_check
            ;;
        "health")
            check_prerequisites
            health_check
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# スクリプト実行
main "$@" 
 