#!/bin/bash
# Gateway 检测 - v7.6 优化版

check_gateway() {
    log "INFO" "Gateway检查"
    
    # 动态端口
    local port=$(cat /root/.openclaw/openclaw.json 2>/dev/null | grep -oP '"port":\s*\K\d+' || echo "15846")
    
    # 阈值配置
    local max_retries=3
    local timeout_sec=5
    
    # 指数退避: 1s, 2s, 4s
    local delays=(1 2 4)
    
    for attempt in $(seq 1 $max_retries); do
        # 检测进程
        if ! timeout $timeout_sec pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
            log "WARN" "Gateway进程不存在 (尝试 $attempt/$max_retries)"
            (( attempt < max_retries )) && sleep ${delays[$((attempt-1))]} && continue
            auto_heal "gateway_down"
            return 1
        fi
        
        # 检测端口监听
        if ! timeout $timeout_sec ss -tlnp 2>/dev/null | grep -q ":$port "; then
            log "ERROR" "Gateway端口未监听 (PID: $(pgrep -f openclaw-gateway))"
            (( attempt < max_retries )) && sleep ${delays[$((attempt-1))]} && continue
            auto_heal "gateway_port_not_listening"
            return 1
        fi
        
        # 健康检查 + 响应体校验
        local response=$(timeout 10 curl -s -w "\n%{http_code}" http://127.0.0.1:$port/health 2>/dev/null || echo -e "\n000")
        local body=$(echo "$response" | head -n 1)
        local http_code=$(echo "$response" | tail -n 1)
        
        # 校验HTTP状态码
        if [[ "$http_code" != "200" ]]; then
            log "WARN" "Gateway HTTP异常 (code=$http_code) (尝试 $attempt/$max_retries)"
            (( attempt < max_retries )) && sleep ${delays[$((attempt-1))]} && continue
            auto_heal "gateway_unhealthy"
            return 1
        fi
        
        # 校验响应体包含 ok/status
        if [[ ! "$body" =~ "\"ok\":true" && ! "$body" =~ "\"status\":\"ok\"" && ! "$body" =~ "\"status\":\"live\"" ]]; then
            log "WARN" "Gateway响应体异常: $body"
            (( attempt < max_retries )) && sleep ${delays[$((attempt-1))]} && continue
            auto_heal "gateway_unhealthy"
            return 1
        fi
        
        # 正常
        local rt=$(echo "$body" | grep -oP '"rt":\s*\K\d+' || echo 0)
        log "INFO" "Gateway正常 port=$port responseMs=$rt"
        
        # 内存检测 (绝对值 + 百分比)
        local pid=$(pgrep -f openclaw-gateway | head -1)
        if [[ -n "$pid" ]]; then
            local mem_rss=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')  # MB
            local mem_pct=$(ps -o %mem= -p "$pid" 2>/dev/null | tr -d ' ')
            
            # 绝对值阈值: 2000MB
            if [[ -n "$mem_rss" && "$mem_rss" -gt 2000 ]]; then
                log "WARN" "Gateway内存过高 (RSS): ${mem_rss}MB > 2000MB"
                auto_heal "gateway_high_memory"
            fi
            
            # 百分比阈值: 60% (更保守)
            if [[ -n "$mem_pct" ]]; then
                local pct_val=$(echo "$mem_pct" | cut -d'.' -f1)
                if (( pct_val > 60 )); then
                    log "WARN" "Gateway内存过高: ${mem_pct}% > 60%"
                fi
            fi
        fi
        
        return 0
    done
    
    log "ERROR" "Gateway检测失败"
    auto_heal "gateway_down"
    return 1
}
