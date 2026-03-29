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
EMAIL_ENABLED=false
EMAIL_TO=""
SELF_CHECK=true
KNOWN_JOBS="cron-monitor openclaw-maintenance 看门狗"
ALERT_TARGET="qqbot:c2c:YOUR_QQ_ID"

# 新增：慢响应重启阈值（原3秒改为30秒）
SLOW_RESPONSE_THRESHOLD=30000
SLOW_RESPONSE_COUNT=3
slow_response_counter=0

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
    
    # P5: 环境变量优先（仅当环境变量非空时覆盖）
    [ -n "${MONITOR_MEMORY_THRESHOLD:-}" ] && MEMORY_THRESHOLD=$MONITOR_MEMORY_THRESHOLD
    [ -n "${MONITOR_RESPONSE_THRESHOLD:-}" ] && RESPONSE_THRESHOLD=$MONITOR_RESPONSE_THRESHOLD
    [ -n "${MONITOR_DISK_THRESHOLD:-}" ] && DISK_THRESHOLD=$MONITOR_DISK_THRESHOLD
    
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
        slow_response_counter=0  # 重置计数器
        check_restart_limit && send_alert "Gateway 宕机" "启动中..." && openclaw gateway start | tee -a "$LOG_FILE" && record_restart
        return 1
    fi
    
    start=$(date +%s%3N)
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:15846/health 2>/dev/null)
    time=$(( $(date +%s%3N) - start ))
    
    if [ "$code" = "200" ]; then
        log "✅ Gateway 正常 (${time}ms)"
        echo "$(date +%s),$time" >> /tmp/openclaw/monitor-history.log
        
        # 慢响应告警（不重启）
        if [ "$time" -gt "$RESPONSE_THRESHOLD" ]; then
            send_alert "响应慢" "${time}ms"
        fi
        
        # 重置慢响应计数器
        slow_response_counter=0
    else
        log "⚠️ 异常 HTTP $code"
        
        # 慢响应计数 + 重启逻辑
        if [ "$time" -gt "$SLOW_RESPONSE_THRESHOLD" ] || [ "$code" != "200" ]; then
            slow_response_counter=$((slow_response_counter + 1))
            log "⚠️ 慢响应/异常第 ${slow_response_counter} 次 (阈值: ${SLOW_RESPONSE_COUNT}次)"
            
            if [ "$slow_response_counter" -ge "$SLOW_RESPONSE_COUNT" ]; then
                log "⚠️ 连续${slow_response_counter}次异常，触发重启"
                check_restart_limit && send_alert "Gateway 持续异常" "正在重启..." && openclaw gateway restart | tee -a "$LOG_FILE" && record_restart
                slow_response_counter=0
            fi
        fi
    fi
}

# ========== 任务检测 ==========
check_cron_jobs() {
    log "=== 定时任务 ==="
    
    # 投递失败持久化文件
    DELIVERY_FAIL_FILE="/tmp/openclaw/delivery_failures.json"
    CRON_RUNS_DIR="/root/.openclaw/cron/runs"
    
    result=$(timeout 5 openclaw cron list 2>&1)
    
    # 方法1: API 模式 - 检查是否返回有效 JSON
    if echo "$result" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        log "   ✅ API 响应正常"
        check_cron_jobs_via_api "$result" "$DELIVERY_FAIL_FILE"
    
    # 方法2: 直接读取 cron runs 日志文件
    elif [ -d "$CRON_RUNS_DIR" ]; then
        log "   ⚠️ API 无响应，使用 cron runs 日志"
        check_cron_jobs_via_log "$CRON_RUNS_DIR" "$DELIVERY_FAIL_FILE"
    
    # 方法3: 回退到旧日志
    else
        log "   ⚠️ API 失败，使用 Gateway 日志"
        check_known_jobs_from_log
    fi
}

check_known_jobs_from_log() {
    log "  📋 检测已知任务 (日志模式)..."
    TODAY=$(date +%Y-%m-%d)
    YESTERDAY=$(date -d yesterday +%Y-%m-%d)
    
    # 查找最新的日志文件
    LOG=""
    for day in $TODAY $YESTERDAY; do
        [ -f "/tmp/openclaw/openclaw-${day}.log" ] && LOG="/tmp/openclaw/openclaw-${day}.log" && break
    done
    
    if [ -z "$LOG" ]; then
        log "  ⚠️ 未找到日志文件"
        return
    fi
    
    log "  📄 使用日志: $LOG"
    
    # 统计任务运行状态
    for job in $KNOWN_JOBS; do
        # 检查任务是否有运行记录
        run_count=$(grep -c "jobId\|$job" "$LOG" 2>/dev/null | head -1 || echo 0)
        [ "$run_count" -gt 0 ] && log "    ✅ $job" || log "    ⚠️ $job (无记录)"
    done
    
    # 统计投递成功/失败
    d=$(grep -c '"delivered":true' "$LOG" 2>/dev/null | head -1 || echo 0)
    f=$(grep -c '"delivered":false' "$LOG" 2>/dev/null | head -1 || echo 0)
    log "  📬 投递: ✅$d ❌$f"
    
    # 检查连续投递失败
    delivery_fail_file="/tmp/openclaw/delivery_failures.json"
    [ -f "$delivery_fail_file" ] || return
    
    # 读取并更新失败计数
    fail_count=$(grep -o '"not-delivered"' "$LOG" 2>/dev/null | wc -l)
    if [ "$fail_count" -ge 3 ]; then
        send_alert "投递失败" "检测到 $fail_count 次投递失败"
    fi
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

# ========== 任务检测：API 模式 ==========
check_cron_jobs_via_api() {
    local result="$1"
    local fail_file="$2"
    local alert_msg=""
    
    result_json=$(echo "$result" | python3 -c "
import json,sys
import datetime

try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    
    # 读取历史状态
    import os
    history = {}
    if os.path.exists('$fail_file'):
        with open('$fail_file', 'r') as f:
            history = json.load(f)
    
    alerts = []
    
    for j in jobs:
        s = j.get('state', {})
        e = s.get('consecutiveErrors', 0)
        st = s.get('lastRunStatus', 'N/A')
        d = s.get('lastDelivered', None)
        ds = s.get('lastDeliveryStatus', 'N/A')
        n = j.get('name', '?')
        
        # 配置校验
        target = j.get('sessionTarget', '')
        kind = j.get('payload', {}).get('kind', '')
        
        if target == 'main' and kind == 'systemEvent':
            print(f'   ⚠️ 配置错误: {n} (main+systemEvent不支持投递)')
            alerts.append(f'CONFIG_ERROR:{n}')
        elif target == 'isolated' and kind and kind != 'agentTurn':
            print(f'   ⚠️ 配置错误: {n} (isolated需agentTurn)')
            alerts.append(f'CONFIG_ERROR:{n}')
        
        # 状态显示
        status_icon = '✅' if j.get('enabled') else '❌'
        print(f'{status_icon} {n}')
        
        if st == 'ok':
            t = s.get('lastRunAtMs')
            if t:
                dt = datetime.datetime.fromtimestamp(t/1000)
                print(f'   ✓ {dt.strftime(\"%m-%d %H:%M\")}')
        elif e > 0:
            print(f'   ✗ 错误{e}次')
            alerts.append(f'ALERT:{n} 错误{e}次')
        
        # 投递状态监控（持久化）
        key = n
        if d == False or ds == 'not-delivered':
            history[key] = history.get(key, 0) + 1
            if history[key] >= 3:
                print(f'   🚨 投递失败{history[key]}次!')
                alerts.append(f'DELIVERY_FAIL:{n} 连续{history[key]}次失败')
        else:
            history[key] = 0
    
    # 写入更新后的历史
    with open('$fail_file', 'w') as f:
        json.dump(history, f)
    
    # 输出告警
    if alerts:
        print('---ALERTS---')
        for a in alerts:
            print(a)
            
except Exception as ex:
    print(f'Error: {ex}', file=sys.stderr)
" 2>&1)
    
    # 提取告警
    alert_msg=$(echo "$result_json" | sed -n '/---ALERTS---/,/$/p' 2>/dev/null | sed '1d')
    
    # 输出结果
    echo "$result_json" | grep -v "^---ALERTS---" | grep -v "^ALERT:" | grep -v "^CONFIG_ERROR:" | grep -v "^DELIVERY_FAIL:"
    
    # 发送告警
    if [ -n "$alert_msg" ]; then
        send_alert "任务异常" "$alert_msg"
    fi
}

# ========== 任务检测：日志模式（不依赖 API） ==========
check_cron_jobs_via_log() {
    local runs_dir="$1"
    local fail_file="$2"
    
    log "   📂 扫描 cron runs 目录 (优化模式)..."
    
    # 优化：只扫描最近修改的 3 个文件（提高效率）
    local recent_files
    recent_files=$(ls -t "$runs_dir"/*.jsonl 2>/dev/null | head -5)
    
    if [ -z "$recent_files" ]; then
        log "   ⚠️ 无运行记录"
        return
    fi
    
    # 缓存 jobs.json
    local jobs_json="/root/.openclaw/cron/jobs.json"
    local jobs_map=""
    if [ -f "$jobs_json" ]; then
        jobs_map=$(python3 -c "
import json
with open('$jobs_json') as f:
    jobs = json.load(f).get('jobs', [])
    for j in jobs:
        print(f\"{j.get('id','')}:{j.get('name','?')}\")
" 2>/dev/null)
    fi
    
    # 遍历最近文件
    for log_file in $recent_files; do
        [ -f "$log_file" ] || continue
        
        # 从文件名提取 job ID
        job_id=$(basename "$log_file" .jsonl)
        
        # 优先从 jobs_map 查找，回退到从 jsonl 获取
        job_name=$(echo "$jobs_map" | grep "^${job_id}:" | cut -d':' -f2)
        if [ -z "$job_name" ]; then
            job_name=$(tail -1 "$log_file" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('name','?'))" 2>/dev/null || echo "?")
        fi
        [ -z "$job_name" ] && job_name="?"
        
        # 检查最近运行状态（优化：只读最后一行）
        last_line=$(tail -1 "$log_file" 2>/dev/null)
        last_status=$(echo "$last_line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
        last_delivered=$(echo "$last_line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('delivered',False))" 2>/dev/null || echo "False")
        last_run=$(echo "$last_line" | python3 -c "import json,sys; d=json.load(sys.stdin); t=d.get('ts',0)/1000; from datetime import datetime; print(datetime.fromtimestamp(t).strftime('%m-%d %H:%M'))" 2>/dev/null || echo "?")
        
        # 统计投递失败次数（优化：只统计最近10行，去除换行）
        fail_count=$(tail -10 "$log_file" 2>/dev/null | grep -c '"delivered":false' | tr -d '[:space:]' || echo 0)
        [ -z "$fail_count" ] && fail_count=0
        
        # 显示状态
        if [ "$last_status" = "ok" ]; then
            echo "   ✅ $job_name (上次: $last_run)"
        else
            echo "   ❌ $job_name (状态: $last_status)"
        fi
        
        # 告警逻辑
        if [ "$fail_count" -ge 3 ]; then
            echo "   🚨 投递失败 $fail_count 次!"
            send_alert "投递失败" "$job_name 连续 $fail_count 次投递失败"
        fi
    done
    
    log "   ✅ 扫描完成"
}

# ========== 错误检查（增强版） ==========
check_errors() {
    log "=== 错误检查 ==="
    TODAY=$(date +%Y-%m-%d)
    YESTERDAY=$(date -d yesterday +%Y-%m-%d)
    GATEWAY_LOG="/tmp/openclaw/openclaw-${TODAY}.log"
    [ -f "$GATEWAY_LOG" ] || GATEWAY_LOG="/tmp/openclaw/openclaw-${YESTERDAY}.log"
    [ -f "$GATEWAY_LOG" ] || return
    
    # 优化：分类统计错误（改进正则，避免误报）
    local conn_timeout
    conn_timeout=$(tail -2000 "$GATEWAY_LOG" 2>/dev/null | grep -cE "connection.*timeout|ConnectionError|ETIMEDOUT|ECONNREFUSED" | tr -d '[:space:]' || echo 0)
    [ -z "$conn_timeout" ] && conn_timeout=0
    
    local api_err
    api_err=$(tail -2000 "$GATEWAY_LOG" 2>/dev/null | grep -cE "\"(error|Error|ERROR)" | tr -d '[:space:]' || echo 0)
    [ -z "$api_err" ] && api_err=0
    
    # 认证错误：只在实际错误消息中查找，不是路径中的数字
    local auth_err
    auth_err=$(tail -2000 "$GATEWAY_LOG" 2>/dev/null | grep -cE "authentication.*fail|invalid.*token|invalid.*auth|auth.*denied" | tr -d '[:space:]' || echo 0)
    [ -z "$auth_err" ] && auth_err=0
    
    local plugin_err
    plugin_err=$(tail -2000 "$GATEWAY_LOG" 2>/dev/null | grep -cE "plugin.*error|Plugin.*fail|load.*fail" | tr -d '[:space:]' || echo 0)
    [ -z "$plugin_err" ] && plugin_err=0
    
    [ "$conn_timeout" -gt 0 ] && log "    🔌 连接超时: $conn_timeout"
    [ "$api_err" -gt 0 ] && log "    🌐 API错误: $api_err"
    [ "$auth_err" -gt 0 ] && log "    🔐 认证错误: $auth_err"
    [ "$plugin_err" -gt 0 ] && log "    🔌 插件错误: $plugin_err"
    
    # 智能错误趋势分析
    local total_err=$((conn_timeout + api_err + auth_err + plugin_err))
    local severity="normal"
    
    if [ "$total_err" -gt 50 ]; then
        severity="critical"
    elif [ "$total_err" -gt 20 ]; then
        severity="warning"
    fi
    
    # 记录趋势
    echo "$(date +%s),$total_err,$severity" >> "$ERROR_TREND_FILE"
    
    # 分析趋势（去除换行符）
    local trend_cnt
    trend_cnt=$(wc -l < "$ERROR_TREND_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
    [ -z "$trend_cnt" ] && trend_cnt=0
    
    if [ "$trend_cnt" -ge "$ERROR_TREND_THRESHOLD" ]; then
        # 读取最近 N 条记录（去除换行符）
        local critical_count
        critical_count=$(tail -n "$ERROR_TREND_WINDOW" "$ERROR_TREND_FILE" 2>/dev/null | grep -c "critical" | tr -d '[:space:]' || echo 0)
        [ -z "$critical_count" ] && critical_count=0
        
        local warning_count
        warning_count=$(tail -n "$ERROR_TREND_WINDOW" "$ERROR_TREND_FILE" 2>/dev/null | grep -c "warning" | tr -d '[:space:]' || echo 0)
        [ -z "$warning_count" ] && warning_count=0
        
        if [ "$critical_count" -ge 3 ]; then
            send_alert "严重错误趋势" "连续 $critical_count 次严重错误，建议检查网络/网关"
        elif [ "$warning_count" -ge 4 ]; then
            send_alert "错误趋势" "连续 $warning_count 次错误，请关注"
        fi
    fi
    
    # 清理过旧的趋势文件（只保留最近100条）
    if [ "$trend_cnt" -gt 100 ]; then
        tail -100 "$ERROR_TREND_FILE" > "${ERROR_TREND_FILE}.tmp" && mv "${ERROR_TREND_FILE}.tmp" "$ERROR_TREND_FILE"
    fi
}

# ========== 通道状态 ==========
check_channels() {
    log "=== 通道状态 ==="
    TODAY=$(date +%Y-%m-%d)
    YESTERDAY=$(date -d yesterday +%Y-%m-%d)
    LOG="/tmp/openclaw/openclaw-${TODAY}.log"
    [ -f "$LOG" ] || LOG="/tmp/openclaw/openclaw-${YESTERDAY}.log"
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
    local alert_type="$1"
    local alert_detail="$2"
    
    # 告警冷却
    [ -f "$LAST_ALERT_FILE" ] && [ $(($(date +%s) - $(cat $LAST_ALERT_FILE))) -lt 1800 ] && return
    
    log "📤 告警: $alert_type - $alert_detail"
    date +%s > "$LAST_ALERT_FILE"
    
    # 构建详细告警内容（包含上下文）
    local context_info=""
    case "$alert_type" in
        "任务异常"|"投递失败")
            context_info="
📋 详情: $alert_detail
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
🔧 来源: 看门狗监控系统"
            ;;
        "Gateway 异常"|"Gateway 持续异常")
            context_info="
📋 详情: $alert_detail
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
💡 建议: 检查 Gateway 进程状态和日志"
            ;;
        "响应慢")
            context_info="
📋 详情: $alert_detail
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
💡 建议: 检查系统负载和网络"
            ;;
        *)
            context_info="
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
            ;;
    esac
    
    # 主通道：QQ
    message action=send target="$ALERT_TARGET" message="🚨 $alert_type

$alert_detail$context_info" 2>/dev/null
    
    # 备用通道1：Webhook
    if [ "$WEBHOOK_ENABLED" = "true" ] && [ -n "$WEBHOOK_URL" ]; then
        curl -s -X POST "$WEBHOOK_URL" -H "Content-Type:application/json" \
            -d "{\"title\":\"[OpenClaw] $alert_type\",\"content\":\"$alert_detail\",\"time\":\"$(date '+%H:%M:%S')\"}" 2>/dev/null &
        log "📤 Webhook 已推送"
    fi
    
    # 备用通道2：邮件 (简单 mailx)
    if [ "$EMAIL_ENABLED" = "true" ] && [ -n "$EMAIL_TO" ]; then
        echo "[OpenClaw] $alert_type - $alert_detail" | mailx -s "[告警] $alert_type" "$EMAIL_TO" 2>/dev/null &
        log "📤 邮件已推送"
    fi
}

# ========== 指标 (Prometheus 格式) ==========
output_metrics() {
    # 获取当前资源状态（避免依赖前面函数）
    local mem="" disk="" load="" 
    local pid=$(pgrep -f "openclaw-gateway" 2>/dev/null | head -1)
    [ -n "$pid" ] && mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
    disk=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    local gateway_status=0
    pgrep -f "openclaw-gateway" > /dev/null && gateway_status=1
    
    # Prometheus 格式输出
    cat > "$METRICS_FILE" << EOF
# HELP openclaw_gateway_up Gateway 进程运行状态
# TYPE openclaw_gateway_up gauge
openclaw_gateway_up ${gateway_status}

# HELP openclaw_gateway_memory_bytes Gateway 内存使用 (MB)
# TYPE openclaw_gateway_memory_bytes gauge
openclaw_gateway_memory_bytes ${mem:-0}

# HELP openclaw_disk_usage_percent 磁盘使用率
# TYPE openclaw_disk_usage_percent gauge
openclaw_disk_usage_percent ${disk:-0}

# HELP openclaw_system_load 系统负载
# TYPE openclaw_system_load gauge
openclaw_system_load ${load:-0}

# HELP openclaw_last_run_timestamp 最后运行时间
# TYPE openclaw_last_run_timestamp gauge
openclaw_last_run_timestamp $(date +%s)
EOF

    # 同时输出到日志方便调试
    log "📈 指标已更新 (Prometheus格式)"
}

# ========== 趋势报告（增强版） ==========
report_trend() {
    # 只在整点执行
    [ "$(date +%M)" != "00" ] && return
    
    log "=== 趋势 ==="
    
    # 内存趋势
    if [ -f /tmp/openclaw/memory.log ]; then
        local mem_avg_1h=$(tail -60 /tmp/openclaw/memory.log 2>/dev/null | awk -F',' '{s+=$2;c++} END {print int(s/c)}')
        local mem_avg_24h=$(tail -1440 /tmp/openclaw/memory.log 2>/dev/null | awk -F',' '{s+=$2;c++} END {print int(s/c)}')
        
        if [ -n "$mem_avg_1h" ] && [ -n "$mem_avg_24h" ]; then
            local mem_diff=$((mem_avg_1h - mem_avg_24h))
            local trend_icon="➡️"
            [ "$mem_diff" -gt 50 ] && trend_icon="⬆️"
            [ "$mem_diff" -lt -50 ] && trend_icon="⬇️"
            log "📈 内存: ${mem_avg_1h}MB (1h) vs ${mem_avg_24h}MB (24h) $trend_icon"
        fi
    fi
    
    # 响应时间趋势
    if [ -f /tmp/openclaw/monitor-history.log ]; then
        local resp_avg=$(tail -60 /tmp/openclaw/monitor-history.log 2>/dev/null | awk -F',' '{s+=$2;c++} END {print int(s/c)}')
        [ -n "$resp_avg" ] && log "📈 响应时间: ${resp_avg}ms (平均)"
    fi
    
    # 任务执行趋势
    if [ -d /root/.openclaw/cron/runs ]; then
        local total_runs=$(ls -1 /root/.openclaw/cron/runs/*.jsonl 2>/dev/null | wc -l)
        local today_runs=$(find /root/.openclaw/cron/runs -name "*.jsonl" -mtime 0 2>/dev/null | wc -l)
        log "📈 任务运行: $today_runs 次 (今日) / $total_runs 个任务"
    fi
    
    # 错误趋势总结
    if [ -f "$ERROR_TREND_FILE" ]; then
        local total_trend=$(wc -l < "$ERROR_TREND_FILE")
        log "📈 错误趋势: $total_trend 次检测记录"
    fi
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
