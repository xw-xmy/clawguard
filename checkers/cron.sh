#!/bin/bash
# 定时任务检测插件

check_cron() {
    log "INFO" "定时任务检查"
    
    local jobs_file="/root/.openclaw/cron/jobs.json"
    
    if [[ -f "$jobs_file" && -r "$jobs_file" ]]; then
        python3 -c "
import json
with open('$jobs_file') as f:
    for j in json.load(f).get('jobs', []):
        s = j.get('state', {})
        e = s.get('consecutiveErrors', 0)
        st = 'ok' if j.get('enabled') and e == 0 else 'error'
        print(f'\"name\":\"{j.get(\"name\")}\",\"status\":\"{st}\"')
" 2>/dev/null | while read -r job; do
            log "INFO" "任务状态 {$job}"
        done
    else
        log "WARN" "无法读取任务配置"
    fi
    
    return 0
}
