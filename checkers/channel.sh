#!/bin/bash
# 通道状态检测 - 超时率告警

check_channel() {
    log "INFO" "通道状态检查"
    
    local log_file="$LOG_DIR/openclaw-$(date +%Y-%m-%d).log"
    [[ -f "$log_file" ]] || return 0
    
    # 统计发送和超时
    local sent=$(grep -c "onMessageSent" "$log_file" 2>/dev/null || echo 0)
    local timeout=$(grep -c "No response" "$log_file" 2>/dev/null || echo 0)
    
    # 计算超时率
    local timeout_rate=0
    if (( sent > 0 )); then
        timeout_rate=$(( timeout * 100 / sent ))
    fi
    
    log "INFO" "QQ发送 sent=$sent timeout=$timeout rate=${timeout_rate}%"
    
    # 超时率告警阈值 10%
    if (( timeout_rate > 10 )); then
        log "WARN" "QQ超时率过高: ${timeout_rate}%"
        return 1
    fi
    
    return 0
}
