#!/bin/bash

# ========================================
# Cronジョブ設定スクリプト
# IPアドレス変更の自動監視
# ========================================

# 設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DYNAMIC_DNS_SCRIPT="$SCRIPT_DIR/dynamic-dns-update.sh"
CRON_LOG="/var/log/dynamic-dns-update.log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 現在のcronジョブを確認
check_existing_cron() {
    crontab -l 2>/dev/null | grep -q "dynamic-dns-update.sh"
    return $?
}

# cronジョブを追加
add_cron_job() {
    log "Cronジョブを追加中..."
    
    # 既存のcrontabを取得
    existing_cron=$(crontab -l 2>/dev/null || echo "")
    
    # 新しいcronジョブを追加（5分ごとに実行）
    new_cron_job="*/5 * * * * $DYNAMIC_DNS_SCRIPT >> $CRON_LOG 2>&1"
    
    # 既存のcronジョブがある場合は削除
    if check_existing_cron; then
        log "既存のcronジョブを削除中..."
        existing_cron=$(echo "$existing_cron" | grep -v "dynamic-dns-update.sh")
    fi
    
    # 新しいcronジョブを追加
    echo "$existing_cron" | { cat; echo "$new_cron_job"; } | crontab -
    
    if [ $? -eq 0 ]; then
        log "Cronジョブを追加しました: 5分ごとに実行"
        return 0
    else
        log "Cronジョブの追加に失敗しました"
        return 1
    fi
}

# cronジョブを削除
remove_cron_job() {
    log "Cronジョブを削除中..."
    
    existing_cron=$(crontab -l 2>/dev/null || echo "")
    new_cron=$(echo "$existing_cron" | grep -v "dynamic-dns-update.sh")
    
    echo "$new_cron" | crontab -
    
    if [ $? -eq 0 ]; then
        log "Cronジョブを削除しました"
        return 0
    else
        log "Cronジョブの削除に失敗しました"
        return 1
    fi
}

# cronジョブの状態を表示
show_cron_status() {
    log "現在のcronジョブ:"
    crontab -l 2>/dev/null | grep "dynamic-dns-update.sh" || echo "Cronジョブが見つかりません"
    
    if [ -f "$CRON_LOG" ]; then
        log "最新のログ:"
        tail -10 "$CRON_LOG"
    else
        log "ログファイルが見つかりません: $CRON_LOG"
    fi
}

# 手動実行
manual_run() {
    log "手動でIPアドレス更新を実行中..."
    "$DYNAMIC_DNS_SCRIPT"
}

# ヘルプ表示
show_help() {
    echo "使用方法: $0 [コマンド]"
    echo ""
    echo "コマンド:"
    echo "  install    - Cronジョブをインストール"
    echo "  remove     - Cronジョブを削除"
    echo "  status     - Cronジョブの状態を表示"
    echo "  run        - 手動でIPアドレス更新を実行"
    echo "  help       - このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0 install    # Cronジョブをインストール"
    echo "  $0 status     # 状態を確認"
    echo "  $0 run        # 手動実行"
}

# メイン処理
case "${1:-help}" in
    install)
        add_cron_job
        ;;
    remove)
        remove_cron_job
        ;;
    status)
        show_cron_status
        ;;
    run)
        manual_run
        ;;
    help|*)
        show_help
        ;;
esac 