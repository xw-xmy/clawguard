#!/bin/bash
# 网络检测 - 多服务器

check_network() {
    log "INFO" "网络检查"
    
    # 外网连通
    if curl -s --max-time 5 -o /dev/null http://www.baidu.com; then
        log "INFO" "外网连通 OK"
    else
        log "WARN" "外网不可达"
    fi
    
    # 多 DNS 检测
    for dns in 8.8.8.8 114.114.114.114 223.5.5.5; do
        if ping -c 1 -W 2 "$dns" > /dev/null 2>&1; then
            log "INFO" "DNS $dns OK"
            break
        fi
    done
    
    # NTP
    if command -v ntpdate > /dev/null; then
        ntpdate -q pool.ntp.org 2>/dev/null | head -1 || true
    fi
}
