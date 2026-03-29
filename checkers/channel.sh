#!/bin/bash
# 通道状态检测插件

check_channel() {
    log "INFO" "通道状态检查"
    
    local log_file="$LOG_DIR/openclaw-$(date +%Y-%m-%d).log"
    
    if [[ -f "$log_file" ]]; then
        local sent=$(grep -c "onMessageSent" "$log_file" 2>/dev/null || echo 0)
        local timeout=$(grep -c "No response" "$log_file" 2>/dev/null || echo 0)
        log "INFO" "QQ发送 sent=$sent timeout=$timeout"
    fi
    
    return 0
}
