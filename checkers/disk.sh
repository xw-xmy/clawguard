#!/bin/bash
# 磁盘检测插件

check_disk() {
    log "INFO" "磁盘检查"
    
    local disk=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    log "INFO" "磁盘使用 diskPercent=$disk"
    
    # 阈值检查
    if (( disk > DISK_THRESHOLD )); then
        log "WARN" "磁盘使用率过高: ${disk}%"
        return 1
    fi
    
    return 0
}
