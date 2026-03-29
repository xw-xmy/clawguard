#!/bin/bash
# 网络检测 - 增强版

check_network() {
    log "INFO" "网络检查"
    
    local failed=0
    
    # 1. 外网连通性 (多目标 + HTTP状态码)
    for target in "http://www.baidu.com" "http://www.aliyun.com" "http://www.tencent.com"; do
        local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$target" 2>/dev/null || echo "000")
        if [[ "$code" =~ ^2|^3 ]]; then
            log "INFO" "外网连通 OK ($target: $code)"
            break
        else
            log "WARN" "外网异常 ($target: $code)"
            (( failed++ ))
        fi
    done
    
    # 2. DNS 检测 (TCP 握手)
    for dns in 8.8.8.8 114.114.114.114; do
        if timeout 3 nc -zv "$dns" 53 > /dev/null 2>&1; then
            log "INFO" "DNS $dns OK"
            break
        fi
    done
    
    # 3. NTP 时间同步检测
    if command -v ntpdate > /dev/null 2>&1; then
        local ntp_result=$(ntpdate -q pool.ntp.org 2>/dev/null | head -1)
        if [[ -n "$ntp_result" ]]; then
            local offset=$(echo "$ntp_result" | grep -oP 'offset [\d.-]+' | awk '{print $2}' | head -1)
            if [[ -n "$offset" ]]; then
                local abs_offset=$(echo "$offset" | tr -d '-')
                if (( $(echo "$abs_offset > 1" | bc -l 2>/dev/null || echo 0) )); then
                    log "WARN" "NTP时间偏移过大: ${offset}s (>1s)"
                else
                    log "INFO" "NTP同步正常: offset=${offset}s"
                fi
            fi
        fi
    fi
    
    return 0
}
