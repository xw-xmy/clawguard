#!/bin/bash
# 运维控制脚本

PID_FILE="/tmp/openclaw/monitor.pid"
LOG_FILE="/tmp/openclaw/monitor.log"
HEARTBEAT_FILE="/tmp/openclaw/monitor.heartbeat"

case "$1" in
    status)
        if [[ -f "$HEARTBEAT_FILE" ]]; then
            last=$(tail -1 "$HEARTBEAT_FILE" 2>/dev/null | awk '{print $2}')
            if [[ -n "$last" ]]; then
                now=$(date +%s)
                age=$((now - last))
                if (( age < 120 )); then
                    echo "✅ 监控系统正常 (${age}秒前)"
                    echo "---"
                    tail -5 "$LOG_FILE"
                else
                    echo "⚠️ 监控系统上次运行: ${age}秒前"
                fi
            fi
        else
            echo "❌ 监控系统未运行"
        fi
        ;;
        
    start)
        echo "运行监控系统..."
        /root/.openclaw/scripts/openclaw-monitor.sh > /dev/null 2>&1
        sleep 1
        $0 status
        ;;
        
    stop)
        # 杀死所有监控进程
        pkill -f "openclaw-monitor.sh" 2>/dev/null
        rm -f "$PID_FILE"
        echo "✅ 已停止"
        ;;
        
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
        
    log)
        tail -30 "$LOG_FILE"
        ;;
        
    *)
        echo "用法: $0 {status|start|stop|restart|log}"
        ;;
esac
