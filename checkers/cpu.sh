#!/bin/bash
# CPU 监控插件

check_cpu() {
    log "INFO" "CPU检查"
    
    # CPU 使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    log "INFO" "CPU使用率 cpuUsage=${cpu_usage}%"
    
    # CPU 负载
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    log "INFO" "系统负载 load=$load"
    
    # 阈值检查
    local cpu_int=${cpu_usage%.*}
    if [[ -n "$cpu_int" ]] && (( cpu_int > 80 )); then
        log "WARN" "CPU使用率过高: ${cpu_int}%"
        return 1
    fi
    
    return 0
}
