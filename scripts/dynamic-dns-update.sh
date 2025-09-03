#!/bin/bash

# ========================================
# 動的DNS更新スクリプト
# RaspberryPiのIPアドレス変更に対応
# ========================================

# 設定
AWS_REGION="ap-northeast-1"
LAMBDA_FUNCTION_NAME="security-camera-api-proxy"
SERVICE_NAME="security-camera"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 現在のIPアドレスを取得
get_current_ip() {
    curl -s ifconfig.me
}

# 前回のIPアドレスを取得
get_previous_ip() {
    if [ -f "/tmp/previous_ip.txt" ]; then
        cat /tmp/previous_ip.txt
    else
        echo ""
    fi
}

# IPアドレスを保存
save_ip() {
    echo "$1" > /tmp/previous_ip.txt
}

# AWS Lambda関数の環境変数を更新
update_lambda_environment() {
    local new_ip=$1
    
    log "Lambda関数の環境変数を更新中..."
    
    # 現在の環境変数を取得
    current_env=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --query 'Environment.Variables' \
        --output json)
    
    # 新しい環境変数を作成
    new_env=$(echo "$current_env" | jq --arg host "$new_ip" '.RASPBERRY_PI_HOST = $host')
    
    # Lambda関数を更新（環境変数を個別に設定）
    aws lambda update-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --environment "Variables={FRONTEND_BUCKET_NAME=\"security-camera-frontend-2024\",CORS_ORIGIN=\"*\",ENABLE_RASPBERRY_PI_PROXY=\"true\",RASPBERRY_PI_HOST=\"$new_ip\",RASPBERRY_PI_PORT=\"3000\",RASPBERRY_PI_PROTOCOL=\"http\"}" \
        --output json > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log "Lambda関数の環境変数を更新しました: $new_ip"
        return 0
    else
        log "Lambda関数の更新に失敗しました"
        return 1
    fi
}

# ヘルスチェック
check_lambda_health() {
    log "Lambda関数のヘルスチェック中..."
    
    # API Gatewayのエンドポイントを取得
    api_url=$(aws apigatewayv2 get-apis \
        --region "$AWS_REGION" \
        --query "Items[?Name=='$SERVICE_NAME-api'].ApiEndpoint" \
        --output text)
    
    if [ -z "$api_url" ]; then
        log "API Gatewayのエンドポイントが見つかりません"
        return 1
    fi
    
    # ヘルスチェックを実行
    response=$(curl -s -w "%{http_code}" "$api_url/health" -o /tmp/health_response.json)
    
    if [ "$response" = "200" ]; then
        log "Lambda関数は正常に動作しています"
        return 0
    else
        log "Lambda関数のヘルスチェックに失敗しました: HTTP $response"
        return 1
    fi
}

# メイン処理
main() {
    log "動的DNS更新スクリプトを開始します"
    
    # 現在のIPアドレスを取得
    current_ip=$(get_current_ip)
    if [ -z "$current_ip" ]; then
        log "IPアドレスの取得に失敗しました"
        exit 1
    fi
    
    log "現在のIPアドレス: $current_ip"
    
    # 前回のIPアドレスを取得
    previous_ip=$(get_previous_ip)
    
    # IPアドレスが変更されたかチェック
    if [ "$current_ip" != "$previous_ip" ]; then
        log "IPアドレスが変更されました: $previous_ip -> $current_ip"
        
        # Lambda関数の環境変数を更新
        if update_lambda_environment "$current_ip"; then
            # IPアドレスを保存
            save_ip "$current_ip"
            
            # ヘルスチェック
            if check_lambda_health; then
                log "IPアドレス更新が完了しました"
            else
                log "ヘルスチェックに失敗しました"
                exit 1
            fi
        else
            log "IPアドレス更新に失敗しました"
            exit 1
        fi
    else
        log "IPアドレスは変更されていません: $current_ip"
    fi
    
    log "動的DNS更新スクリプトを完了しました"
}

# スクリプト実行
main "$@" 