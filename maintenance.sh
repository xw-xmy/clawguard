#!/bin/bash
# OpenClaw 系统维护脚本 (增强版)
# 功能：基础健康检查、内存清理、日志轮转、自动备份
# 设计原则：轻量运行，不影响系统

LOG_FILE="/tmp/openclaw/maintenance.log"
MEMORY_DIR="/root/.openclaw/workspace/memory"
MAX_LOG_SIZE=10485760
BACKUP_DIR="/root/.openclaw/cron"
JOBS_FILE="$BACKUP_DIR/jobs.json"

mkdir -p /tmp/openclaw /tmp/openclaw/tmp /tmp/openclaw/cache

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    
    # 日志轮转
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$lines" -gt 5000 ]; then
        tail -n 2000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

# 0. 自动备份 jobs.json
backup_jobs() {
    if [ -f "$JOBS_FILE" ]; then
        cp "$JOBS_FILE" "$BACKUP_DIR/jobs.json.bak"
        log "✅ jobs.json 已备份"
    fi
}

# 1. Gateway 基础检查
check_gateway() {
    if ! pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
        log "⚠️ Gateway 未运行"
        return 1
    fi
    
    if curl -s --max-time 3 http://127.0.0.1:15846/health 2>/dev/null | grep -q "ok"; then
        log "✅ Gateway 正常"
    else
        log "⚠️ Gateway 响应慢"
    fi
}

# 2. 内存清理
clean_memory() {
    [ ! -d "$MEMORY_DIR" ] && return
    
    deleted=$(find "$MEMORY_DIR" -name "*.md" -type f -mtime +7 -delete 2>/dev/null | wc -l)
    [ "$deleted" -gt 0 ] && log "🗑️ 清理内存文件: $deleted 个"
}

# 3. 日志轮转 (增强)
rotate_logs() {
    # 清理压缩日志
    find /tmp/openclaw -name "*.log.*.gz" -mtime +7 -delete 2>/dev/null
    
    # 截断大日志 (15MB 阈值)
    for logf in /tmp/openclaw/openclaw-*.log; do
        [ -f "$logf" ] || continue
        size=$(stat -c %s "$logf" 2>/dev/null || echo 0)
        if [ "$size" -gt 15728640 ]; then
            tail -n 8000 "$logf" > "$logf.tmp" && mv "$logf.tmp" "$logf"
            log "📝 轮转日志: $(basename $logf) ($(($size/1024/1024))MB)"
        fi
    done
}

# 4. 临时文件清理
clean_temp() {
    rm -rf /tmp/openclaw/tmp/* /tmp/openclaw/cache/* 2>/dev/null
    rm -rf /tmp/agent-browser* 2>/dev/null
}

# 5. 资源记录
log_resources() {
    pid=$(pgrep -f "openclaw-gateway" 2>/dev/null | head -1)
    [ -n "$pid" ] && mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
    disk=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    log "📊 内存: ${mem:-0}MB | 磁盘: ${disk:-0}%"
}

# 6. 任务汇总报告
report_tasks() {
    log "=== 定时任务汇总 ==="
    
    # 只在每天8点发送汇总
    [ "$(date +%H)" != "08" ] && return
    
    result=$(timeout 5 python3 -c "
import json
with open('$JOBS_FILE') as f:
    data = json.load(f)
    jobs = data.get('jobs', [])
    
    summary = '📋 定时任务汇总\n\n'
    for j in jobs:
        name = j.get('name', '?')
        enabled = '✅' if j.get('enabled') else '❌'
        expr = j.get('schedule', {}).get('expr', 'N/A')
        state = j.get('state', {})
        last_status = state.get('lastRunStatus', 'N/A')
        
        summary += f'{enabled} {name}\n'
        summary += f'   时间: {expr}\n'
        summary += f'   上次: {last_status}\n\n'
    
    print(summary)
" 2>/dev/null)
    
    [ -n "$result" ] && log "$result"
}

# 主函数
main() {
    log "========== 维护开始 =========="
    backup_jobs
    check_gateway
    clean_memory
    rotate_logs
    clean_temp
    log_resources
    report_tasks
    log "========== 维护完成 =========="
}

main
