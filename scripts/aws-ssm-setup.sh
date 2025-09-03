#!/bin/bash

# ========================================
# AWS Systems Manager Session Manager 設定スクリプト
# RaspberryPiとAWS Lambdaの安全な接続
# ========================================

# 設定
AWS_REGION="ap-northeast-1"
INSTANCE_NAME="raspberry-pi-camera"
ROLE_NAME="SSMInstanceRole"

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 前提条件チェック
check_prerequisites() {
    log_info "前提条件をチェックしています..."
    
    # AWS CLI確認
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLIがインストールされていません"
        exit 1
    fi
    
    # AWS認証確認
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証情報が設定されていません"
        exit 1
    fi
    
    log_success "前提条件チェック完了"
}

# IAMロール作成
create_iam_role() {
    log_info "IAMロールを作成しています..."
    
    # 信頼ポリシー
    cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # ロール作成
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://trust-policy.json
    
    # SSM管理ポリシーをアタッチ
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    
    # インスタンスプロファイル作成
    aws iam create-instance-profile --instance-profile-name "$ROLE_NAME"
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$ROLE_NAME" \
        --role-name "$ROLE_NAME"
    
    log_success "IAMロール作成完了"
}

# SSMエージェントインストール
install_ssm_agent() {
    log_info "SSMエージェントをインストールしています..."
    
    # snapdインストール
    sudo apt update
    sudo apt install -y snapd
    
    # SSMエージェントインストール
    sudo snap install amazon-ssm-agent --classic
    
    # サービス有効化
    sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
    sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
    
    log_success "SSMエージェントインストール完了"
}

# インスタンス登録
register_instance() {
    log_info "インスタンスを登録しています..."
    
    # インスタンスID取得
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    
    if [ -z "$INSTANCE_ID" ]; then
        log_warning "EC2インスタンスではないため、手動登録が必要です"
        return 1
    fi
    
    # タグ設定
    aws ec2 create-tags \
        --resources "$INSTANCE_ID" \
        --tags "Key=Name,Value=$INSTANCE_NAME"
    
    log_success "インスタンス登録完了: $INSTANCE_ID"
}

# Lambda関数更新
update_lambda_function() {
    log_info "Lambda関数を更新しています..."
    
    # 新しい環境変数設定
    aws lambda update-function-configuration \
        --function-name "security-camera-api-proxy" \
        --environment "Variables={FRONTEND_BUCKET_NAME=\"security-camera-frontend-2024\",CORS_ORIGIN=\"*\",ENABLE_RASPBERRY_PI_PROXY=\"true\",USE_SSM_CONNECTION=\"true\",SSM_INSTANCE_NAME=\"$INSTANCE_NAME\",RASPBERRY_PI_PORT=\"3000\",RASPBERRY_PI_PROTOCOL=\"http\"}" \
        --region "$AWS_REGION"
    
    log_success "Lambda関数更新完了"
}

# 接続テスト
test_connection() {
    log_info "SSM接続をテストしています..."
    
    # セッション開始
    aws ssm start-session \
        --target "$INSTANCE_NAME" \
        --region "$AWS_REGION" \
        --document-name "AWS-StartPortForwardingSession" \
        --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
    
    log_success "SSM接続テスト完了"
}

# ヘルプ表示
show_help() {
    echo "使用方法: $0 [コマンド]"
    echo ""
    echo "コマンド:"
    echo "  setup      - 完全セットアップ（IAMロール作成 + SSMエージェントインストール）"
    echo "  install    - SSMエージェントのみインストール"
    echo "  register   - インスタンス登録"
    echo "  update     - Lambda関数更新"
    echo "  test       - 接続テスト"
    echo "  help       - このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0 setup    # 完全セットアップ"
    echo "  $0 test     # 接続テスト"
}

# メイン処理
case "${1:-help}" in
    setup)
        check_prerequisites
        create_iam_role
        install_ssm_agent
        register_instance
        update_lambda_function
        ;;
    install)
        check_prerequisites
        install_ssm_agent
        ;;
    register)
        check_prerequisites
        register_instance
        ;;
    update)
        check_prerequisites
        update_lambda_function
        ;;
    test)
        check_prerequisites
        test_connection
        ;;
    help|*)
        show_help
        ;;
esac 