#!/bin/bash
# Gateway 检测 - 超时 + 重试

check_gateway() {
    log "INFO" "Gateway检查"
    
    local port=$(cat /root/.openclaw/openclaw.json 2>/dev/null | grep -oP '"port":\s*\K\d+' || echo "15846")
    local max_retries=3
    local retry_delay=2
    
    # 重试机制
    for attempt in $(seq 1 $max_retries); do
        # 检查进程 (超时 5s)
        if ! timeout 5 pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
            log "WARN" "Gateway进程不存在 (尝试 $attempt/$max_retries)"
            (( attempt < max_retries )) && sleep $retry_delay && continue
            auto_heal "gateway_down"
            return 1
        fi
        
        # 检查端口 (超时 5s)
        if ! timeout 5 ss -tlnp 2>/dev/null | grep -q ":$port "; then
            log "WARN" "Gateway端口 $port 未监听 (尝试 $attempt/$max_retries)"
            (( attempt < max_retries )) && sleep $retry_delay && continue
            auto_heal "gateway_down"
            return 1
        fi
        
        # 检查响应 (超时 10s)
        local start_time=$(date +%s%3N)
        local rt=$(timeout 10 curl -s -o /dev/null -w "%{time_total}" http://127.0.0.1:$port/health 2>/dev/null || echo 0)
        
        if [[ "$rt" != "0" ]]; then
            local ms=$(echo "$rt * 1000" | bc | cut -d'.' -f1)
            local duration=$(( $(date +%s%3N) - start_time ))
            log "INFO" "Gateway正常 responseMs=$ms durationMs=$duration"
            
            # 内存检查 (超时 5s)
            local pid=$(timeout 5 pgrep -f openclaw-gateway | head -1)
            if [[ -n "$pid" ]]; then
                local mem=$(timeout 5 ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
                if [[ -n "$mem" && "$mem" -gt 1200 ]]; then
                    log "WARN" "Gateway内存过高: ${mem}MB"
                    auto_heal "high_memory"
                fi
            fi
            return 0
        fi
        
        (( attempt < max_retries )) && sleep $retry_delay
    done
    
    log "ERROR" "Gateway检测失败 (已重试 $max_retries 次)"
    auto_heal "gateway_down"
    return 1
}
