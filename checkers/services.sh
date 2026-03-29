#!/bin/bash
# 依赖服务健康检测插件

check_services() {
    log "INFO" "依赖服务检查"
    
    # 关键服务 (未运行才告警)
    local critical_services=(
        "15846:Gateway:critical"
        "3306:MySQL:optional"
        "6379:Redis:optional"
    )
    
    for item in "${critical_services[@]}"; do
        IFS=':' read -r port name level <<< "$item"
        
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            log "INFO" "$name 端口 $port 监听中"
        else
            if [[ "$level" == "critical" ]]; then
                log "ERROR" "$name 关键服务未运行 (端口 $port)"
            else
                log "INFO" "$name 端口 $port 未监听 (可选)"
            fi
        fi
    done
    
    return 0
}
