#!/bin/bash
# 服务检测 - 增强版

check_service() {
    log "INFO" "服务托管检测"
    
    # 1. OpenClaw 服务状态检测
    local svc_status=$(systemctl show openclaw --property=ActiveState --value 2>/dev/null || echo "unknown")
    local svc_substate=$(systemctl show openclaw --property=SubState --value 2>/dev/null || echo "unknown")
    
    if [[ "$svc_status" == "active" && "$svc_substate" == "running" ]]; then
        log "INFO" "OpenClaw systemd服务: active + running"
    else
        log "WARN" "OpenClaw服务状态: Active=$svc_status, SubState=$svc_substate (独立进程模式)"
    fi
    
    # 2. 看门狗自身检测 (心跳文件)
    local heartbeat_file="/tmp/openclaw/monitor.heartbeat"
    if [[ -f "$heartbeat_file" ]]; then
        local last_update=$(cat "$heartbeat_file" | awk '{print $2}')
        local now=$(date +%s)
        
        if [[ -n "$last_update" ]]; then
            local age=$((now - last_update))
            
            if (( age < 60 )); then
                log "INFO" "看门狗自检: 正常 (${age}s前更新)"
            elif (( age < 120 )); then
                log "WARN" "看门狗自检: 心跳过期 (${age}s前更新)"
            else
                log "ERROR" "看门狗自检: 心跳停止 (${age}s前更新)"
                # 尝试重启
                auto_heal "monitor_hung"
            fi
        fi
    else
        log "WARN" "看门狗心跳文件不存在"
    fi
    
    # 3. openclaw-monitor systemd 服务
    local mon_status=$(systemctl show openclaw-monitor --property=ActiveState --value 2>/dev/null || echo "not-found")
    if [[ "$mon_status" == "active" ]]; then
        log "INFO" "openclaw-monitor systemd服务: active"
    else
        log "WARN" "openclaw-monitor服务: $mon_status (cron模式)"
    fi
    
    return 0
}
