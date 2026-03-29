#!/bin/bash
# Web UI 检测插件

check_webui() {
    log "INFO" "Web UI检查"
    
    if ! ss -tlnp 2>/dev/null | grep -q ":15847"; then
        log "WARN" "Web UI未运行"
        auto_heal "webui_down"
        return 1
    fi
    
    return 0
}
