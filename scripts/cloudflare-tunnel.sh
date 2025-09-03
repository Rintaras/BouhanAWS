#!/bin/bash

# ========================================
# Cloudflare Tunnel 設定スクリプト
# RaspberryPiカメラサーバーを外部公開
# ========================================

# 設定
LOCAL_PORT=3000
TUNNEL_NAME="raspberry-pi-camera"
CONFIG_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CONFIG_DIR/config.yml"

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

# Cloudflare Tunnel設定
setup_tunnel() {
    log_info "Cloudflare Tunnel設定を開始しています..."
    
    # 設定ディレクトリ作成
    mkdir -p "$CONFIG_DIR"
    
    # トンネル作成
    cloudflared tunnel create "$TUNNEL_NAME" --config "$CONFIG_FILE"
    
    # 設定ファイル作成
    cat > "$CONFIG_FILE" << EOF
tunnel: $TUNNEL_NAME
credentials-file: $CONFIG_DIR/$TUNNEL_NAME.json

ingress:
  - hostname: $TUNNEL_NAME.your-domain.com
    service: http://localhost:$LOCAL_PORT
  - service: http_status:404
EOF
    
    log_success "Cloudflare Tunnel設定完了"
}

# トンネル開始
start_tunnel() {
    log_info "Cloudflare Tunnelを開始しています..."
    
    # 既存のcloudflaredプロセスを停止
    pkill -f cloudflared || true
    
    # トンネル開始
    cloudflared tunnel --config "$CONFIG_FILE" run "$TUNNEL_NAME" > /tmp/cloudflared.log 2>&1 &
    CLOUDFLARED_PID=$!
    
    # 起動待機
    sleep 5
    
    # トンネルURL取得
    TUNNEL_URL=$(cloudflared tunnel info "$TUNNEL_NAME" --config "$CONFIG_FILE" | grep -o 'https://[^[:space:]]*' | head -1)
    
    if [ -n "$TUNNEL_URL" ]; then
        log_success "Cloudflare Tunnel開始完了: $TUNNEL_URL"
        echo "$TUNNEL_URL" > /tmp/cloudflared_url.txt
        
        # Lambda関数の環境変数を更新
        update_lambda_environment "$TUNNEL_URL"
        
        return 0
    else
        log_error "Cloudflare Tunnel開始失敗"
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
    log_info "Cloudflare Tunnelを停止しています..."
    pkill -f cloudflared || true
    log_success "Cloudflare Tunnel停止完了"
}

# トンネル状態確認
check_tunnel_status() {
    log_info "Cloudflare Tunnel状態を確認しています..."
    
    if [ -f /tmp/cloudflared_url.txt ]; then
        TUNNEL_URL=$(cat /tmp/cloudflared_url.txt)
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

# トンネル情報表示
show_tunnel_info() {
    log_info "Cloudflare Tunnel情報を表示しています..."
    
    if [ -f "$CONFIG_FILE" ]; then
        echo "設定ファイル: $CONFIG_FILE"
        cat "$CONFIG_FILE"
    else
        log_warning "設定ファイルが見つかりません"
    fi
    
    # トンネル一覧
    cloudflared tunnel list
}

# ヘルプ表示
show_help() {
    echo "使用方法: $0 [コマンド]"
    echo ""
    echo "コマンド:"
    echo "  setup      - Cloudflare Tunnel設定"
    echo "  start      - トンネル開始"
    echo "  stop       - トンネル停止"
    echo "  status     - トンネル状態確認"
    echo "  info       - トンネル情報表示"
    echo "  restart    - トンネル再起動"
    echo "  help       - このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0 setup    # Cloudflare Tunnel設定"
    echo "  $0 start    # トンネル開始"
    echo "  $0 status   # 状態確認"
}

# メイン処理
case "${1:-help}" in
    setup)
        setup_tunnel
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
    info)
        show_tunnel_info
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