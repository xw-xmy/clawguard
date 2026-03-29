#!/bin/bash
# 日志检测插件 - 精确过滤

check_logs() {
    log "INFO" "日志检查"
    
    local log_file="$LOG_DIR/openclaw-$(date +%Y-%m-%d).log"
    [[ ! -f "$log_file" ]] && { log "INFO" "日志不存在"; return 0; }
    
    # 检查日志大小
    local size_mb=$(($(stat -c%s "$log_file" 2>/dev/null || echo 0) / 1024 / 1024))
    log "INFO" "日志大小: ${size_mb}MB"
    
    # 精确统计真实错误
    local err_count=$(tail -500 "$log_file" 2>/dev/null | grep -vE \
        "session timed out|will re-identify|re-identify" | \
        grep -vE "pricing bootstrap failed" | \
        grep -vE "DeprecationWarning|punycode" | \
        grep -vE "token_missing|unauthorized" | \
        grep -vE "qqbot:default.*deliver called" | \
        grep -vE "sendText result.*error=none" | \
        grep -vE "gateway/channels/qqbot" | \
        grep '"levelId":5' | wc -l)
    
    if (( err_count > 0 )); then
        log "WARN" "真实错误: $err_count"
    else
        log "INFO" "无真实错误"
    fi
}

cleanup_logs() {
    log "INFO" "开始日志清理"
    
    local deleted=0 freed=0
    
    # 删除过期日志
    if [[ -d "$LOG_DIR" ]]; then
        old=$(find "$LOG_DIR" -name "*.log" -mtime +${LOG_RETENTION_DAYS:-7} 2>/dev/null)
        if [[ -n "$old" ]]; then
            deleted=$(echo "$old" | wc -l)
            freed=$(echo "$old" | xargs du -sb 2>/dev/null | awk '{sum+=$1} END {print int(sum/1024/1024)}')
            find "$LOG_DIR" -name "*.log" -mtime +${LOG_RETENTION_DAYS:-7} -delete 2>/dev/null
        fi
    fi
    
    log "INFO" "清理完成: 删除${deleted}个文件，释放${freed}MB"
}
