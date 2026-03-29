#!/bin/bash
# API/认证错误检测

check_api_errors() {
    log "INFO" "API错误检测"
    
    local log_file="$LOG_DIR/openclaw-$(date +%Y-%m-%d).log"
    [[ -f "$log_file" ]] || return 0
    
    # 过滤已知的正常错误
    local api_errors
    api_errors=$(tail -500 "$log_file" 2>/dev/null | \
        grep -vE "session timed out|will re-identify|pricing bootstrap|DeprecationWarning|punycode|token_missing|unauthorized|qqbot:default|sendText result.*error=none|gateway/channels/qqbot" | \
        grep -c '"levelId":5' || true)
    api_errors=${api_errors:-0}
    api_errors=$(echo "$api_errors" | tr -d '[:space:]')
    
    if (( api_errors > 0 )); then
        log "WARN" "API错误: $api_errors 次"
    else
        log "INFO" "无API错误"
    fi
}
