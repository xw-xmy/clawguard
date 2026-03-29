#!/bin/bash
# 日志检测 + 归档

check_logs() {
    log "INFO" "日志检查"
    local log_file="$LOG_DIR/openclaw-$(date +%Y-%m-%d).log"
    [[ ! -f "$log_file" ]] && return
    
    local size_mb=$(($(stat -c%s "$log_file" 2>/dev/null || echo 0) / 1024 / 1024))
    log "INFO" "日志大小: ${size_mb}MB"
}

cleanup_logs() {
    log "INFO" "日志清理"
    
    # 压缩旧日志
    find "$LOG_DIR" -name "*.log" -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null
    
    # 删除过期
    find "$LOG_DIR" -name "*.log.gz" -mtime +7 -delete 2>/dev/null
    
    log "INFO" "日志归档完成"
}
