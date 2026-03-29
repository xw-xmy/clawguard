#!/bin/bash
# API 错误检测 - 改进版

# 白名单配置
WHITELIST_FILE="/root/.openclaw/workspace/clawguard/config.d/error_whitelist.txt"

check_api_errors() {
    log "INFO" "API错误检测"
    
    local log_file="$LOG_DIR/openclaw-$(date +%Y-%m-%d).log"
    [[ -f "$log_file" ]] || return 0
    
    # 加载白名单
    local whitelist=""
    if [[ -f "$WHITELIST_FILE" ]]; then
        whitelist=$(cat "$WHITELIST_FILE" | tr '\n' '|')
    fi
    
    # 扫描全部日志 (不过滤白名单)
    local total_errors=$(grep -c '"levelId":5' "$log_file" 2>/dev/null || echo 0)
    
    # 白名单过滤后的真实错误
    local real_errors=0
    if [[ -n "$whitelist" ]]; then
        real_errors=$(grep '"levelId":5' "$log_file" 2>/dev/null | \
            grep -vE "$whitelist" | wc -l)
    else
        real_errors=$total_errors
    fi
    
    if (( real_errors > 0 )); then
        log "WARN" "API错误: 真实错误 $real_errors 次 (总计 $total_errors 次)"
    else
        log "INFO" "API错误: 0 次 (已过滤)"
    fi
    
    return 0
}

# 便捷: 生成白名单模板
init_whitelist() {
    cat > "$WHITELIST_FILE" << 'WL'
session timed out
will re-identify
pricing bootstrap
DeprecationWarning
punycode
token_missing
unauthorized
qqbot:default
sendText result.*error=none
gateway/channels/qqbot
handshake-timeout
content_filter
No response within timeout
WL
    log "INFO" "白名单已初始化"
}
