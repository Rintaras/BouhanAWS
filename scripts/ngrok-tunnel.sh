#!/bin/bash

# ========================================
# ngrok トンネル設定スクリプト
# RaspberryPiカメラサーバーを外部公開
# ========================================

# 設定
LOCAL_PORT=3000
NGROK_CONFIG_DIR="$HOME/.ngrok2"
NGROK_CONFIG_FILE="$NGROK_CONFIG_DIR/ngrok.yml"

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

# ngrok設定ディレクトリ作成
setup_ngrok_config() {
    log_info "ngrok設定ディレクトリを作成しています..."
    
    mkdir -p "$NGROK_CONFIG_DIR"
    
    # 設定ファイル作成
    cat > "$NGROK_CONFIG_FILE" << EOF
version: "2"
authtoken: ""
tunnels:
  camera-server:
    proto: http
    addr: $LOCAL_PORT
    inspect: false
EOF
    
    log_success "ngrok設定完了"
}

# ngrokトンネル開始
start_tunnel() {
    log_info "ngrokトンネルを開始しています..."
    
    # 既存のngrokプロセスを停止
    pkill -f ngrok || true
    
    # トンネル開始
    ngrok http $LOCAL_PORT --config "$NGROK_CONFIG_FILE" > /tmp/ngrok.log 2>&1 &
    NGROK_PID=$!
    
    # 起動待機
    sleep 3
    
    # トンネルURL取得
    TUNNEL_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' 2>/dev/null)
    
    if [ -n "$TUNNEL_URL" ] && [ "$TUNNEL_URL" != "null" ]; then
        log_success "ngrokトンネル開始完了: $TUNNEL_URL"
        echo "$TUNNEL_URL" > /tmp/ngrok_url.txt
        
        # Lambda関数の環境変数を更新
        update_lambda_environment "$TUNNEL_URL"
        
        return 0
    else
        log_error "ngrokトンネル開始失敗"
        return 1
    fi
}

# Lambda関数の環境変数を更新
update_lambda_environment() {
    local tunnel_url="$1"
    local host=$(echo "$tunnel_url" | sed 's|https://||')
    
    log_info "Lambda関数の環境変数を更新しています..."
    log_info "トンネルURL: $tunnel_url"
    log_info "ホスト: $host"
    
    aws lambda update-function-configuration \
        --function-name security-camera-api-proxy \
        --environment "Variables={FRONTEND_BUCKET_NAME=\"security-camera-frontend-2024\",CORS_ORIGIN=\"*\",ENABLE_RASPBERRY_PI_PROXY=\"true\",USE_SSM_CONNECTION=\"false\",RASPBERRY_PI_HOST=\"$host\",RASPBERRY_PI_PORT=\"443\",RASPBERRY_PI_PROTOCOL=\"https\"}" \
        --region ap-northeast-1
    
    if [ $? -eq 0 ]; then
        log_success "Lambda関数環境変数更新完了"
    else
        log_error "Lambda関数環境変数更新失敗"
    fi
}

# トンネル停止
stop_tunnel() {
    log_info "ngrokトンネルを停止しています..."
    pkill -f ngrok || true
    log_success "ngrokトンネル停止完了"
}

# トンネル状態確認
check_tunnel_status() {
    log_info "ngrokトンネル状態を確認しています..."
    
    if [ -f /tmp/ngrok_url.txt ]; then
        TUNNEL_URL=$(cat /tmp/ngrok_url.txt)
        log_info "現在のトンネルURL: $TUNNEL_URL"
        
        # 接続テスト
        if curl -s "$TUNNEL_URL/camera-status" > /dev/null; then
            log_success "トンネル接続正常"
            return 0
        else
            log_warning "トンネル接続エラー"
            return 1
        fi
    else
        log_warning "トンネルURLファイルが見つかりません"
        return 1
    fi
}

# ヘルプ表示
show_help() {
    echo "使用方法: $0 [コマンド]"
    echo ""
    echo "コマンド:"
    echo "  setup      - ngrok設定"
    echo "  start      - トンネル開始"
    echo "  stop       - トンネル停止"
    echo "  status     - トンネル状態確認"
    echo "  restart    - トンネル再起動"
    echo "  help       - このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0 setup    # ngrok設定"
    echo "  $0 start    # トンネル開始"
    echo "  $0 status   # 状態確認"
}

# メイン処理
case "${1:-help}" in
    setup)
        setup_ngrok_config
        ;;
    start)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    status)
        check_tunnel_status
        ;;
    restart)
        stop_tunnel
        sleep 2
        start_tunnel
        ;;
    help|*)
        show_help
        ;;
esac 