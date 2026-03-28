#!/bin/bash
# 🐕 看门狗5.0 - OpenClaw 监控系统 (生产版)
# 配置文件：/root/.openclaw/scripts/monitor.conf

trap 'log "♻️ SIGHUP 收到，重新加载配置"; load_config' SIGHUP

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${MONITOR_CONFIG:-$SCRIPT_DIR/monitor.conf}"
LOG_FILE="/tmp/openclaw/monitor.log"
METRICS_FILE="/tmp/openclaw/metrics.log"
LAST_ALERT_FILE="/tmp/openclaw/last_alert.time"
RESTART_COUNT_FILE="/tmp/openclaw/restart_count.log"
LAST_RUN_FILE="/tmp/openclaw/last_run.time"
ERROR_TREND_FILE="/tmp/openclaw/error_trend.log"

# 默认配置
MEMORY_THRESHOLD=1500
RESPONSE_THRESHOLD=3000
DISK_THRESHOLD=85
ERROR_THRESHOLD=10
ERROR_TREND_WINDOW=5
ERROR_TREND_THRESHOLD=3
CHANNEL_HEALTH_WEIGHT_ERROR=30
CHANNEL_HEALTH_WEIGHT_TIMEOUT=50
CLUSTER_MODE=false
CLUSTER_INSTANCES=""
WEBHOOK_ENABLED=false
WEBHOOK_URL=""
SELF_CHECK=true
KNOWN_JOBS="每日新闻简报 每日AI早报 cron-monitor openclaw-maintenance 看门狗"
ALERT_TARGET="qqbot:c2c:YOUR_QQ_ID"

# P1: 配置校验
validate_config() {
    local valid=true
    
    # 数字校验
    for var in MEMORY_THRESHOLD RESPONSE_THRESHOLD DISK_THRESHOLD ERROR_THRESHOLD ERROR_TREND_WINDOW ERROR_TREND_THRESHOLD; do
        val=${!var}
        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            log "⚠️ $var 应为数字: $val"
            valid=false
        fi
    done
    
    # 范围校验
    if [ "$MEMORY_THRESHOLD" -lt 100 ] || [ "$MEMORY_THRESHOLD" -gt 10000 ]; then
        log "⚠️ MEMORY_THRESHOLD 建议 100-10000"
    fi
    
    return 0
}

# P2: 配置加载（带降级）
load_config() {
    # 先设默认值
    MEMORY_THRESHOLD=1500
    RESPONSE_THRESHOLD=3000
    DISK_THRESHOLD=85
    
    # P5: 环境变量优先
    [ -n "$MEMORY_THRESHOLD" ] && MEMORY_THRESHOLD=$MEMORY_THRESHOLD
    
    # 加载配置文件
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" 2>/dev/null && log "✅ 配置加载: $CONFIG_FILE" || log "⚠️ 配置加载失败"
    fi
    
    validate_config
}

mkdir -p /tmp/openclaw

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ========== 自监控 ==========
self_check() {
    [ "$SELF_CHECK" != "true" ] && return
    log "=== 自监控 ==="
    
    if [ -f "$LAST_RUN_FILE" ]; then
        last=$(cat "$LAST_RUN_FILE" 2>/dev/null)
        if [ -n "$last" ]; then
            gap=$(( $(date +%s) - last ))
            [ "$gap" -gt 2700 ] && log "⚠️ 上次运行异常 (${gap}s前)"
        fi
    fi
    
    date +%s > "$LAST_RUN_FILE"
}

# ========== 重启限制 ==========
check_restart_limit() {
    now=$(date +%s)
    [ -f "$RESTART_COUNT_FILE" ] && {
        grep ",restart$" "$RESTART_COUNT_FILE" | while read -r line; do
            ts=$(echo "$line" | cut -d',' -f1)
            [ $((now - ts)) -lt 3600 ] && echo "$line"
        done > "${RESTART_COUNT_FILE}.tmp"
        mv "${RESTART_COUNT_FILE}.tmp" "$RESTART_COUNT_FILE"
    }
    
    count=$(grep -c "restart$" "$RESTART_COUNT_FILE" 2>/dev/null || echo 0)
    [ "$count" -ge 3 ] && return 1
    return 0
}

record_restart() {
    echo "$(date +%s),restart" >> "$RESTART_COUNT_FILE"
}

# ========== 健康检查 ==========
check_gateway() {
    log "=== 健康检查 ==="
    
    if ! pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
        log "❌ Gateway 未运行"
        check_restart_limit && send_alert "Gateway 宕机" "启动中..." && openclaw gateway start | tee -a "$LOG_FILE" && record_restart
        return 1
    fi
    
    start=$(date +%s%3N)
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:15846/health 2>/dev/null)
    time=$(( $(date +%s%3N) - start ))
    
    if [ "$code" = "200" ]; then
        log "✅ Gateway 正常 (${time}ms)"
        echo "$(date +%s),$time" >> /tmp/openclaw/monitor-history.log
        [ "$time" -gt "$RESPONSE_THRESHOLD" ] && send_alert "响应慢" "${time}ms"
    else
        log "⚠️ 异常 HTTP $code"
        check_restart_limit && send_alert "Gateway 异常" "重启..." && openclaw gateway restart | tee -a "$LOG_FILE" && record_restart
    fi
}

# ========== 任务检测 ==========
check_cron_jobs() {
    log "=== 定时任务 ==="
    
    result=$(timeout 2 openclaw cron list 2>&1 || echo "TIMEOUT")
    
    if echo "$result" | grep -q "TIMEOUT"; then
        check_known_jobs_from_log
    else
        echo "$result" | python3 -c "
import json,sys
from datetime import datetime
try:
    for j in json.load(sys.stdin).get('jobs',[]):
        s=j.get('state',{})
        e=s.get('consecutiveErrors',0)
        st=s.get('lastRunStatus','N/A')
        n=j.get('name','?')
        print(f'{\"✅\" if j.get(\"enabled\") else \"❌\"} {n}')
        if st=='ok':
            t=s.get('lastRunAtMs')
            print(f'   ✓ {datetime.fromtimestamp(t/1000).strftime(\"%m-%d %H:%M\")}') if t else ''
        elif e>0:
            print(f'   ✗ 错误{e}次')
            print(f'   🚨 ALERT:{n}失败{e}次')
except:pass
" 2>/dev/null
        
        grep "🚨 ALERT" "$LOG_FILE" | tail -1 | sed 's/.*🚨 ALERT://' | read -r alert && send_alert "任务失败" "$alert"
    fi
}

check_known_jobs_from_log() {
    log "  📋 检测已知任务..."
    LOG="/tmp/openclaw/openclaw-2026-03-29.log"
    [ -f "$LOG" ] || LOG="/tmp/openclaw/openclaw-2026-03-28.log"
    [ -f "$LOG" ] || return
    
    for job in $KNOWN_JOBS; do
        c=$(grep -c "$job" "$LOG" 2>/dev/null | head -1 || echo 0)
        [ "$c" -gt 0 ] && log "    ✅ $job"
    done
    
    d=$(grep -c "lastDelivered.*true" "$LOG" 2>/dev/null | head -1 || echo 0)
    f=$(grep -c "error\|failed" "$LOG" 2>/dev/null | head -1 || echo 0)
    log "  📬 投递: ✅$d ❌$f"
}

# ========== 资源监控 ==========
check_resources() {
    log "=== 资源监控 ==="
    
    pid=$(pgrep -f "openclaw-gateway" 2>/dev/null | head -1)
    [ -n "$pid" ] && mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
    
    if [ -n "$mem" ]; then
        echo "$(date +%s),$mem" >> /tmp/openclaw/memory.log
        avg=$(tail -5 /tmp/openclaw/memory.log 2>/dev/null | awk -F',' '{s+=$2;c++} END {print int(s/c)}')
        trend=""
        [ -n "$avg" ] && [ "$mem" -gt $((avg+100)) ] && trend=" ↑"
        [ -n "$avg" ] && [ "$mem" -lt $((avg-100)) ] && trend=" ↓"
        log "📊 Gateway 内存: ${mem}MB (均:${avg:-0}MB)${trend}"
        [ "$mem" -gt "$MEMORY_THRESHOLD" ] && send_alert "内存过高" "${mem}MB"
    fi
    
    log "📊 系统进程: $(ps aux | wc -l)"
    log "📊 系统负载: $(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')"
    
    mem_t=$(free -m | awk 'NR==2{print $2}')
    mem_u=$(free -m | awk 'NR==2{print $3}')
    log "📊 系统内存: ${mem_u}MB / ${mem_t}MB ($((mem_u*100/mem_t))%)"
    
    disk=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    log "💾 磁盘: ${disk}%"
    [ "$disk" -gt "$DISK_THRESHOLD" ] && send_alert "磁盘不足" "${disk}%"
}

# ========== 错误检查 ==========
check_errors() {
    log "=== 错误检查 ==="
    LOG="/tmp/openclaw/openclaw-2026-03-29.log"
    [ -f "$LOG" ] || LOG="/tmp/openclaw/openclaw-2026-03-28.log"
    [ -f "$LOG" ] || return
    
    conn=$(tail -2000 "$LOG" 2>/dev/null | grep -c "connection\|timeout" | head -1 || echo 0)
    api=$(tail -2000 "$LOG" 2>/dev/null | grep -c "API.*error" | head -1 || echo 0)
    [ "$conn" -gt 0 ] && log "    🔌 连接: $conn"
    [ "$api" -gt 0 ] && log "    🌐 API: $api"
    
    # 错误趋势
    cur=$(tail -100 "$LOG_FILE" 2>/dev/null | grep -c "ERROR" | head -1 || echo 0)
    echo "$(date +%s),$cur" >> "$ERROR_TREND_FILE"
    cnt=$(wc -l < "$ERROR_TREND_FILE" 2>/dev/null || echo 0)
    [ "$cnt" -ge "$ERROR_TREND_THRESHOLD" ] && send_alert "错误趋势" "连续 $cnt 次"
}

# ========== 通道状态 ==========
check_channels() {
    log "=== 通道状态 ==="
    LOG="/tmp/openclaw/openclaw-2026-03-29.log"
    [ -f "$LOG" ] || LOG="/tmp/openclaw/openclaw-2026-03-28.log"
    [ -f "$LOG" ] || return
    
    qt=$(tail -1000 "$LOG" 2>/dev/null | grep -c "No response" | head -1 || echo 0)
    qs=$(tail -1000 "$LOG" 2>/dev/null | grep -c "onMessageSent" | head -1 || echo 0)
    qe=$(tail -1000 "$LOG" 2>/dev/null | grep -c "ERROR.*qqbot" | head -1 || echo 0)
    
    [ "$qs" -gt 0 ] && log "📬 QQ 发送: $qs"
    [ "$qt" -gt 0 ] && log "⚠️ QQ 超时: $qt"
    [ "$qe" -gt 0 ] && log "❌ QQ 错误: $qe"
    
    # 健康评分
    total=$((qs + qt + qe))
    [ "$total" -eq 0 ] && total=1
    score=$((100 - qe*30/100 - qt*50/100))
    [ "$score" -lt 0 ] && score=0
    log "📊 通道健康: $score/100"
    [ "$score" -lt 50 ] && send_alert "通道差" "$score/100"
    
    [ "$qt" -gt 3 ] && send_alert "QQ超时" "${qt}次"
}

# ========== 集群 ==========
check_cluster() {
    [ "$CLUSTER_MODE" != "true" ] && return
    log "=== 集群 ==="
    for ins in $CLUSTER_INSTANCES; do
        status=$(curl -s --max-time 3 "http://$ins/health" 2>/dev/null || echo down)
        [ "$status" = "down" ] && log "    ❌ $ins" && send_alert "集群异常" "$ins 离线" || log "    ✅ $ins"
    done
}

# ========== 维护 ==========
maintain() {
    find /tmp/openclaw -name "*.gz" -mtime +7 -delete 2>/dev/null
    for f in /tmp/openclaw/openclaw-*.log; do
        [ -f "$f" ] && [ $(stat -c%s "$f" 2>/dev/null || echo 0) -gt 10485760 ] && tail -5000 "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
}

# ========== 告警 ==========
send_alert() {
    [ -f "$LAST_ALERT_FILE" ] && [ $(($(date +%s) - $(cat $LAST_ALERT_FILE))) -lt 1800 ] && return
    
    log "📤 告警: $1 - $2"
    date +%s > "$LAST_ALERT_FILE"
    
    message action=send target="$ALERT_TARGET" message="🚨 $1

$2

$(date '+%H:%M:%S')" 2>/dev/null
    
    [ "$WEBHOOK_ENABLED" = "true" ] && [ -n "$WEBHOOK_URL" ] && curl -s -X POST "$WEBHOOK_URL" -H "Content-Type:application/json" -d "{\"title\":\"$1\",\"content\":\"$2\"}" 2>/dev/null
}

# ========== 指标 ==========
output_metrics() {
    {
        pgrep -f openclaw-gateway > /dev/null && echo "openclaw_gateway_health 1" || echo "openclaw_gateway_health 0"
        [ -n "$mem" ] && echo "openclaw_gateway_memory $mem"
        echo "openclaw_disk_usage $disk"
    } > "$METRICS_FILE"
}

# ========== 趋势 ==========
report_trend() {
    [ "$(date +%M)" != "00" ] && return
    log "=== 趋势 ==="
    [ -f /tmp/openclaw/memory.log ] && log "📈 内存: $(tail -60 /tmp/openclaw/memory.log | awk -F',' '{s+=$2}END{print int(s/NR)}')MB"
}

# 主函数
main() {
    load_config
    log "========== 🐕 看门狗5.0 巡逻 =========="
    self_check
    check_gateway
    check_cron_jobs
    check_resources
    check_errors
    check_channels
    check_cluster
    maintain
    report_trend
    output_metrics
    log "========== 完成 =========="
}

main
