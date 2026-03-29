#!/bin/bash
# systemd 服务检测

check_service() {
    log "INFO" "服务托管检测"
    
    # 检测 OpenClaw 服务
    if systemctl is-active --quiet openclaw 2>/dev/null; then
        log "INFO" "OpenClaw systemd服务运行中"
    else
        log "WARN" "OpenClaw未以systemd服务运行 (独立进程模式)"
    fi
    
    # 检测看门狗服务
    if systemctl is-active --quiet openclaw-monitor 2>/dev/null; then
        log "INFO" "openclaw-monitor systemd服务运行中"
    else
        log "WARN" "openclaw-monitor未以systemd服务运行"
    fi
}
