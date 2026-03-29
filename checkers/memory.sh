#!/bin/bash
# 内存检测插件

check_memory() {
    log "INFO" "内存检查"
    
    # 系统内存
    local sys_mem_used=$(free -m | awk 'NR==2{print $3}')
    local sys_mem_total=$(free -m | awk 'NR==2{print $2}')
    local sys_mem_pct=$((sys_mem_used * 100 / sys_mem_total))
    log "INFO" "系统内存 usedMB=$sys_mem_used totalMB=$sys_mem_total percent=${sys_mem_pct}%"
    
    # Gateway 内存
    local pid=$(pgrep -f openclaw-gateway | head -1)
    if [[ -n "$pid" ]]; then
        local gw_mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
        if [[ -n "$gw_mem" ]]; then
            log "INFO" "Gateway内存 memoryMB=$gw_mem"
            
            if (( gw_mem > MEMORY_THRESHOLD )); then
                log "WARN" "Gateway内存超过阈值: ${gw_mem}MB"
                auto_heal "high_memory"
            fi
        fi
    fi
    
    return 0
}
