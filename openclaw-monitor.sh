#!/bin/bash
# OpenClaw 监控系统 - 完整版

# ==================== 初始化 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKERS_DIR="/root/.openclaw/workspace/clawguard/checkers"
CONFIG_FILE="/root/.openclaw/workspace/clawguard/monitor.conf"

# 加载配置
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "错误：配置文件不存在: $CONFIG_FILE" >&2
    exit 1
fi

PID_FILE="${PID_FILE:-/tmp/openclaw/monitor.pid}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-/tmp/openclaw/monitor.heartbeat}"
mkdir -p "$(dirname "$HEARTBEAT_FILE")"

# 锁
if [[ -f "$PID_FILE" ]]; then
    old_pid=$(cat "$PID_FILE")
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
        exit 1
    fi
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -Iseconds)
    printf '{"ts":"%s","level":"%s","service":"monitor","message":"%s"}\n' \
        "$timestamp" "$level" "$message" >> "$LOG_FILE"
}

# 加载插件
load_plugins() {
    for plugin in "$CHECKERS_DIR"/*.sh; do
        [[ -f "$plugin" && -r "$plugin" ]] && source "$plugin"
    done
}

# 自愈函数
auto_heal() {
    case "$1" in
        gateway_down) log "WARN" "Gateway无响应";;
        high_memory) log "WARN" "内存过高";;
        log_full) cleanup_logs ;;
        webui_down) 
            log "WARN" "Web UI未运行"
            pkill -f web-ui.py 2>/dev/null
            python3 /root/.openclaw/scripts/web-ui.py &>/dev/null &
            ;;
    esac
}

# 更新心跳
update_heartbeat() {
    echo "$$ $(date +%s)" > "$HEARTBEAT_FILE"
}

# 加载插件
load_plugins

# 执行
update_heartbeat
log "INFO" "监控系统启动"

# 运行所有检测
check_gateway
check_cron
check_memory
check_disk
check_logs
# Web UI 检测（可选）
if [[ "$WEBUI_CHECK_ENABLED" != "false" ]]; then
    check_webui
fi
check_channel
    check_cpu
    check_network
    check_services

# 定时清理 (每小时有10%概率执行，或日志过大时)
if [[ -f "$LOG_DIR/openclaw-$(date +%Y-%m-%d).log" ]]; then
    size_mb=$(($(stat -c%s "$LOG_DIR/openclaw-$(date +%Y-%m-%d).log" 2>/dev/null || echo 0) / 1024 / 1024))
    if (( size_mb > LOG_MAX_SIZE_MB )) || (( RANDOM % 10 == 0 )); then
        cleanup_logs
    fi
fi

# Prometheus
/root/.openclaw/scripts/output-prometheus.py 2>/dev/null

update_heartbeat
log "INFO" "监控完成"
