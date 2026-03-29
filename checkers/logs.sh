#!/bin/bash
# 日志检测插件 - 配置化清理

check_logs() {
    log "INFO" "日志检查"
    
    local log_file="$LOG_DIR/openclaw-$(date +%Y-%m-%d).log"
    
    # 检查日志是否存在
    [[ ! -f "$log_file" ]] && { log "INFO" "日志文件不存在"; return 0; }
    
    # 检查日志大小
    local log_size=$(stat -c %s "$log_file" 2>/dev/null || echo 0)
    local size_mb=$((log_size / 1024 / 1024))
    
    if (( size_mb > LOG_MAX_SIZE_MB )); then
        log "WARN" "日志过大: ${size_mB}MB，超过阈值 ${LOG_MAX_SIZE_MB}MB"
        auto_heal "log_full"
    fi
    
    log "INFO" "日志大小: ${size_mb}MB"
    
    # 检查错误数量
    local err_count=$(tail -500 "$log_file" 2>/dev/null | \
        grep -vE "content_filter|session timed out|No response|handshake-timeout|gateway client|gateway timeout|DeprecationWarning|punycode|edit failed|message failed|qqbot-api.*Body" | \
        grep -c '"levelId":5' | tr -d '\n' || echo 0)
    
    (( err_count > 0 )) && log "WARN" "检测到错误 errorCount=$err_count" || log "INFO" "无真实错误"
    
    return 0
}

# 清理函数 - 独立调用
cleanup_logs() {
    log "INFO" "开始日志清理"
    
    local deleted_count=0
    local freed_space=0
    
    # 1. 删除过期日志
    if [[ -d "$LOG_DIR" ]]; then
        # 统计要删除的文件
        local old_files=$(find "$LOG_DIR" -name "*.log" -mtime +${LOG_RETENTION_DAYS:-7} 2>/dev/null)
        if [[ -n "$old_files" ]]; then
            deleted_count=$(echo "$old_files" | wc -l)
            freed_space=$(echo "$old_files" | xargs du -sb 2>/dev/null | awk '{sum+=$1} END {print int(sum/1024/1024)}')
            find "$LOG_DIR" -name "*.log" -mtime +${LOG_RETENTION_DAYS:-7} -delete 2>/dev/null
            log "INFO" "删除过期日志: ${deleted_count}个文件，释放 ${freed_space}MB"
        fi
    fi
    
    # 2. 压缩旧日志
    if [[ -d "$LOG_DIR" ]]; then
        local compress_count=0
        for log_file in $(find "$LOG_DIR" -name "*.log" -mtime +${LOG_COMPRESS_AFTER_DAYS:-1} ! -name "*.gz" 2>/dev/null); do
            if [[ -f "$log_file" ]]; then
                gzip -9 "$log_file" 2>/dev/null && ((compress_count++))
            fi
        done
        (( compress_count > 0 )) && log "INFO" "压缩日志: ${compress_count}个文件"
    fi
    
    # 3. 清理临时文件
    local temp_count=0
    if [[ -d "$LOG_DIR" ]]; then
        temp_count=$(find "$LOG_DIR" -name "*.tmp" -delete 2>/dev/null; echo $temp_count)
    fi
    
    # 清理报告
    log "INFO" "清理完成: 删除${deleted_count}个文件，压缩${compress_count}个，释放${freed_space}MB"
    
    return 0
}
