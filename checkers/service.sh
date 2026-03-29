#!/bin/bash
# 服务检测 - 增强版 (智能识别)

check_service() {
    log "INFO" "服务托管检测"
    
    # 1. 检测 OpenClaw 运行模式
    # 方式1: systemd 服务
    local svc_active=$(systemctl show openclaw --property=ActiveState --value 2>/dev/null || echo "not-found")
    local svc_substate=$(systemctl show openclaw --property=SubState --value 2>/dev/null || echo "not-found")
    
    # 方式2: 进程检测
    local proc_count=$(pgrep -c -f "openclaw-gateway" 2>/dev/null || echo 0)
    local port_listen=$(ss -tlnp 2>/dev/null | grep -c ":15846" || echo 0)
    
    # 智能判断运行模式
    if [[ "$svc_active" == "active" && "$svc_substate" == "running" ]]; then
        # systemd 模式
        log "INFO" "OpenClaw: systemd服务运行中"
    elif (( proc_count > 0 )) && (( port_listen > 0 )); then
        # 独立进程模式 (正常)
        log "INFO" "OpenClaw: 独立进程模式运行中 (进程数=$proc_count, 端口监听正常)"
    elif (( proc_count > 0 )); then
        # 进程存在但端口未监听
        log "WARN" "OpenClaw: 进程存在但端口未监听 (进程数=$proc_count)"
    else
        # 完全没运行
        log "ERROR" "OpenClaw: 未运行"
    fi
    
    # 2. 看门狗自身检测 (心跳文件)
    local heartbeat_file="/tmp/openclaw/monitor.heartbeat"
    if [[ -f "$heartbeat_file" ]]; then
        local last_update=$(cat "$heartbeat_file" | awk '{print $2}')
        local now=$(date +%s)
        
        if [[ -n "$last_update" ]]; then
            local age=$((now - last_update))
            
            if (( age < 60 )); then
                log "INFO" "看门狗自检: 正常 (${age}s前)"
            elif (( age < 120 )); then
                log "WARN" "看门狗自检: 心跳过期 (${age}s前)"
            else
                log "ERROR" "看门狗自检: 心跳停止 (${age}s前)"
            fi
        fi
    fi
    
    # 3. openclaw-monitor 运行模式检测
    local mon_proc=$(pgrep -c -f "openclaw-monitor.sh" 2>/dev/null || echo 0)
    local cron_active=$(systemctl is-active cron 2>/dev/null || echo "unknown")
    
    if (( mon_proc > 0 )); then
        log "INFO" "看门狗: 独立进程模式 (PID数=$mon_proc)"
    elif [[ "$cron_active" == "active" ]]; then
        log "INFO" "看门狗: cron守护进程运行中"
    else
        log "WARN" "看门狗: 未检测到运行"
    fi
    
    return 0
}
