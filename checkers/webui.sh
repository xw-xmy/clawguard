#!/bin/bash
# Web UI 检测 - 超时控制

check_webui() {
    log "INFO" "Web UI检查"
    
    # 检测进程 (超时 5s)
    if ! timeout 5 pgrep -f "web-ui.py" > /dev/null 2>&1; then
        log "WARN" "Web UI进程不存在"
        return 1
    fi
    
    # 检测端口 (超时 5s)
    if ! timeout 5 ss -tlnp 2>/dev/null | grep -q ":15847"; then
        log "WARN" "Web UI端口未监听"
        return 1
    fi
    
    log "INFO" "Web UI运行中"
    return 0
}
