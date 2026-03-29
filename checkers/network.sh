#!/bin/bash
# 网络连通性检测插件 - 优化版

check_network() {
    log "INFO" "网络检查"
    
    # 1. 检测外网连通性（主要）
    if curl -s --max-time 5 -o /dev/null -w "%{http_code}" http://www.baidu.com | grep -q "200\|301\|302"; then
        log "INFO" "外网连通 OK"
    else
        log "WARN" "外网不可达"
    fi
    
    # 2. 检测 DNS
    local dns_ok=0
    for dns in "8.8.8.8" "114.114.114.114"; do
        if ping -c 1 -W 2 "$dns" > /dev/null 2>&1; then
            log "INFO" "DNS连通 dns=$dns OK"
            dns_ok=1
            break
        fi
    done
    [[ $dns_ok -eq 0 ]] && log "WARN" "DNS不可达"
    
    # 3. NTP 时间同步
    if command -v ntpdate > /dev/null 2>&1; then
        local ntp_offset=$(ntpdate -q pool.ntp.org 2>&1 | grep "adjust" | awk '{print $5}')
        if [[ -n "$ntp_offset" ]]; then
            log "INFO" "NTP时间差 offset=${ntp_offset}s"
        fi
    fi
    
    # 4. 内网网关（跳过检测，云服务器正常不可达）
    # log "INFO" "内网检测已跳过（云服务器正常）"
    
    return 0
}
