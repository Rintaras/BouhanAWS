#!/bin/bash

# ========================================
# 動的IP管理スクリプト
# RaspberryPiのIPアドレス変更を自動検出・更新
# ========================================

# 設定
CONFIG_FILE="/home/pi/kumikomi3/.ip-config"
LOG_FILE="/var/log/ip-manager.log"
CHECK_INTERVAL=300 # 5分
MAX_RETRIES=3

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 現在のIPアドレスを取得
get_current_ip() {
    hostname -I | awk '{print $1}'
}

# 保存されたIPアドレスを取得
get_saved_ip() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo ""
    fi
}

# IPアドレスを保存
save_ip() {
    local ip="$1"
    echo "$ip" > "$CONFIG_FILE"
    log_info "IPアドレスを保存: $ip"
}

# AWS Lambda関数の環境変数を更新
update_lambda_environment() {
    local ip="$1"
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        log_info "Lambda関数の環境変数を更新中... (試行 $((retry_count + 1))/$MAX_RETRIES)"
        
        aws lambda update-function-configuration \
            --function-name security-camera-api-proxy \
            --environment "Variables={FRONTEND_BUCKET_NAME=\"security-camera-frontend-2024\",CORS_ORIGIN=\"*\",ENABLE_RASPBERRY_PI_PROXY=\"true\",USE_SSM_CONNECTION=\"false\",RASPBERRY_PI_HOST=\"$ip\",RASPBERRY_PI_PORT=\"3000\",RASPBERRY_PI_PROTOCOL=\"http\"}" \
            --region ap-northeast-1
        
        if [ $? -eq 0 ]; then
            log_success "Lambda関数環境変数更新完了: $ip"
            return 0
        else
            log_error "Lambda関数環境変数更新失敗 (試行 $((retry_count + 1)))"
            retry_count=$((retry_count + 1))
            sleep 10
        fi
    done
    
    log_error "Lambda関数環境変数更新が最大試行回数に達しました"
    return 1
}

# Terraform設定ファイルを更新
update_terraform_config() {
    local ip="$1"
    local tfvars_file="/home/pi/kumikomi3/terraform/terraform.tfvars"
    
    log_info "Terraform設定ファイルを更新中..."
    
    # バックアップを作成
    cp "$tfvars_file" "${tfvars_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # IPアドレスを更新
    sed -i "s/raspberry_pi_host.*=.*\".*\"/raspberry_pi_host     = \"$ip\"/" "$tfvars_file"
    
    if [ $? -eq 0 ]; then
        log_success "Terraform設定ファイル更新完了: $ip"
        return 0
    else
        log_error "Terraform設定ファイル更新失敗"
        return 1
    fi
}

# 接続テスト
test_connection() {
    local ip="$1"
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        log_info "接続テスト中... (試行 $((retry_count + 1))/$MAX_RETRIES)"
        
        if curl -s --connect-timeout 10 "http://$ip:3000/camera-status" > /dev/null; then
            log_success "接続テスト成功: $ip"
            return 0
        else
            log_warning "接続テスト失敗: $ip (試行 $((retry_count + 1)))"
            retry_count=$((retry_count + 1))
            sleep 5
        fi
    done
    
    log_error "接続テストが最大試行回数に達しました"
    return 1
}

# API Gateway統合を更新
update_api_gateway_integration() {
    local ip="$1"
    local api_id="2zz3z5nb2l"
    local resource_id="a0wsop"
    
    log_info "API Gateway統合を更新中..."
    
    # 統合URIを更新
    aws apigateway update-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method ANY \
        --patch-operations '[{"op":"replace","path":"/uri","value":"http://'"$ip"':3000/{proxy}"}]'
    
    if [ $? -eq 0 ]; then
        log_success "API Gateway統合更新完了: $ip"
        
        # デプロイメントを作成
        aws apigateway create-deployment \
            --rest-api-id "$api_id" \
            --stage-name prod
        
        if [ $? -eq 0 ]; then
            log_success "API Gatewayデプロイメント完了"
            return 0
        else
            log_error "API Gatewayデプロイメント失敗"
            return 1
        fi
    else
        log_error "API Gateway統合更新失敗"
        return 1
    fi
}

# ヘルスチェック
health_check() {
    local ip="$1"
    
    log_info "ヘルスチェック実行中..."
    
    # カメラサーバーの状態確認
    local camera_status=$(curl -s "http://$ip:3000/camera-status" 2>/dev/null)
    if [ $? -eq 0 ] && echo "$camera_status" | grep -q "is_active"; then
        log_success "カメラサーバー正常動作"
    else
        log_warning "カメラサーバー応答なし"
        return 1
    fi
    
    # API Gateway経由での接続テスト
    local api_response=$(curl -s "https://2zz3z5nb2l.execute-api.ap-northeast-1.amazonaws.com/prod/api/camera-status" 2>/dev/null)
    if [ $? -eq 0 ]; then
        log_success "API Gateway経由接続正常"
    else
        log_warning "API Gateway経由接続エラー"
        return 1
    fi
    
    return 0
}

# メイン処理
main() {
    local current_ip=$(get_current_ip)
    local saved_ip=$(get_saved_ip)
    
    log_info "IP管理スクリプト開始"
    log_info "現在のIP: $current_ip"
    log_info "保存されたIP: $saved_ip"
    
    # IPアドレスが変更された場合
    if [ "$current_ip" != "$saved_ip" ] && [ -n "$current_ip" ]; then
        log_info "IPアドレス変更を検出: $saved_ip -> $current_ip"
        
        # 接続テスト
        if test_connection "$current_ip"; then
            # Lambda関数環境変数を更新
            if update_lambda_environment "$current_ip"; then
                # Terraform設定ファイルを更新
                if update_terraform_config "$current_ip"; then
                    # API Gateway統合を更新
                    if update_api_gateway_integration "$current_ip"; then
                        # IPアドレスを保存
                        save_ip "$current_ip"
                        
                        # ヘルスチェック
                        if health_check "$current_ip"; then
                            log_success "IPアドレス更新完了"
                            return 0
                        else
                            log_error "ヘルスチェック失敗"
                            return 1
                        fi
                    else
                        log_error "API Gateway統合更新失敗"
                        return 1
                    fi
                else
                    log_error "Terraform設定ファイル更新失敗"
                    return 1
                fi
            else
                log_error "Lambda関数環境変数更新失敗"
                return 1
            fi
        else
            log_error "接続テスト失敗"
            return 1
        fi
    else
        log_info "IPアドレス変更なし"
        
        # 定期的なヘルスチェック
        if health_check "$current_ip"; then
            log_success "システム正常動作"
            return 0
        else
            log_warning "システム異常検出"
            return 1
        fi
    fi
}

# デーモンモード
daemon_mode() {
    log_info "デーモンモード開始"
    
    while true; do
        main
        sleep $CHECK_INTERVAL
    done
}

# ヘルプ表示
show_help() {
    echo "使用方法: $0 [コマンド]"
    echo ""
    echo "コマンド:"
    echo "  check     - IPアドレス変更をチェック"
    echo "  update    - 強制的にIPアドレスを更新"
    echo "  daemon    - デーモンモードで実行"
    echo "  health    - ヘルスチェック実行"
    echo "  status    - 現在の状態を表示"
    echo "  help      - このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0 check    # IPアドレス変更チェック"
    echo "  $0 daemon   # デーモンモード開始"
    echo "  $0 health   # ヘルスチェック"
}

# 現在の状態を表示
show_status() {
    local current_ip=$(get_current_ip)
    local saved_ip=$(get_saved_ip)
    
    echo "=== IP管理システム状態 ==="
    echo "現在のIP: $current_ip"
    echo "保存されたIP: $saved_ip"
    echo "変更検出: $([ "$current_ip" != "$saved_ip" ] && echo "あり" || echo "なし")"
    echo "設定ファイル: $CONFIG_FILE"
    echo "ログファイル: $LOG_FILE"
    echo ""
    
    if [ -n "$current_ip" ]; then
        echo "=== 接続テスト ==="
        if curl -s --connect-timeout 5 "http://$current_ip:3000/camera-status" > /dev/null; then
            echo "カメラサーバー: 正常"
        else
            echo "カメラサーバー: 異常"
        fi
    fi
}

# メイン処理
case "${1:-help}" in
    check)
        main
        ;;
    update)
        current_ip=$(get_current_ip)
        if [ -n "$current_ip" ]; then
            update_lambda_environment "$current_ip"
            update_terraform_config "$current_ip"
            update_api_gateway_integration "$current_ip"
            save_ip "$current_ip"
        fi
        ;;
    daemon)
        daemon_mode
        ;;
    health)
        current_ip=$(get_current_ip)
        if [ -n "$current_ip" ]; then
            health_check "$current_ip"
        fi
        ;;
    status)
        show_status
        ;;
    help|*)
        show_help
        ;;
esac 