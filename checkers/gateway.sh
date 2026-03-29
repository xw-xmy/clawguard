#!/bin/bash
# Gateway 检测 - 端口验证

check_gateway() {
    log "INFO" "Gateway检查"
    
    local port=$(cat /root/.openclaw/openclaw.json 2>/dev/null | grep -oP '"port":\s*\K\d+' || echo "15846")
    local max_retries=3
    
    # 重试检测
    for attempt in $(seq 1 $max_retries); do
        # 检测进程
        if ! timeout 5 pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
            log "WARN" "Gateway进程不存在 (尝试 $attempt/$max_retries)"
            (( attempt < max_retries )) && sleep 2 && continue
            auto_heal "gateway_down"
            return 1
        fi
        
        # 检测端口监听
        if ! timeout 5 ss -tlnp 2>/dev/null | grep -q ":$port "; then
            log "ERROR" "Gateway进程存在但端口 $port 未监听 (PID: $(pgrep -f openclaw-gateway))"
            (( attempt < max_retries )) && sleep 2 && continue
            auto_heal "gateway_port_not_listening"
            return 1
        fi
        
        # 检测响应
        local rt=$(timeout 10 curl -s -o /dev/null -w "%{time_total}" http://127.0.0.1:$port/health 2>/dev/null || echo 0)
        if [[ "$rt" != "0" ]]; then
            local ms=$(echo "$rt * 1000" | bc | cut -d'.' -f1)
            log "INFO" "Gateway正常 port=$port responseMs=$ms"
            
            # 内存检测
            local mem_pct=$(ps -o %mem= -p $(pgrep -f openclaw-gateway | head -1) 2>/dev/null | tr -d ' ')
            if [[ -n "$mem_pct" ]]; then
                mem_val=$(echo "$mem_pct" | cut -d'.' -f1)
                if (( mem_val > 70 )); then
                    log "WARN" "Gateway内存占用过高: ${mem_pct}%"
                    auto_heal "gateway_high_memory"
                fi
            fi
            return 0
        fi
        
        (( attempt < max_retries )) && sleep 2
    done
    
    log "ERROR" "Gateway检测失败"
    auto_heal "gateway_down"
    return 1
}
