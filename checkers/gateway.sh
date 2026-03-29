#!/bin/bash
# Gateway 检测插件

check_gateway() {
    log "INFO" "Gateway检查开始"
    
    # 检查进程
    if ! pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
        log "WARN" "Gateway进程不存在"
        auto_heal "gateway_down"
        return 1
    fi
    
    # 检查响应
    for i in 1 2 3; do
        local rt=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 \
            http://127.0.0.1:15846/health 2>/dev/null || echo 0)
        
        if [[ "$rt" != "0" ]]; then
            local ms=$(echo "$rt * 1000" | bc | cut -d'.' -f1)
            log "INFO" "Gateway正常 responseMs=$ms"
            
            # 检查内存
            local pid=$(pgrep -f openclaw-gateway | head -1)
            if [[ -n "$pid" ]]; then
                local mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
                if [[ -n "$mem" && "$mem" -gt 1500 ]]; then
                    log "WARN" "Gateway内存过高: ${mem}MB"
                    auto_heal "high_memory"
                fi
            fi
            return 0
        fi
        (( i < 3 )) && sleep 2
    done
    
    log "ERROR" "Gateway无响应"
    auto_heal "gateway_down"
    return 1
}
