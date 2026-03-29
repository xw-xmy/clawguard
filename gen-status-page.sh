#!/bin/bash
# 简单 Web 状态页生成器

OUTPUT_FILE="/tmp/openclaw/status.html"
METRICS_FILE="/tmp/openclaw/metrics.log"
LOG_FILE="/tmp/openclaw/monitor.log"

# 读取指标
if [ -f "$METRICS_FILE" ]; then
    gateway_up=$(grep "openclaw_gateway_up" "$METRICS_FILE" | awk '{print $2}')
    gateway_mem=$(grep "openclaw_gateway_memory_bytes" "$METRICS_FILE" | awk '{print $2}')
    disk_usage=$(grep "openclaw_disk_usage_percent" "$METRICS_FILE" | awk '{print $2}')
    system_load=$(grep "openclaw_system_load" "$METRICS_FILE" | awk '{print $2}')
    last_run=$(grep "openclaw_last_run_timestamp" "$METRICS_FILE" | awk '{print $2}')
fi

# 默认值
[ -z "$gateway_up" ] && gateway_up=0
[ -z "$gateway_mem" ] && gateway_mem=0
[ -z "$disk_usage" ] && disk_usage=0
[ -z "$system_load" ] && system_load=0
[ -z "$last_run" ] && last_run=$(date +%s)

# 格式化时间
last_run_human=$(date -d "@$last_run" "+%Y-%m-%d %H:%M:%S")

# 生成 HTML
cat > "$OUTPUT_FILE" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ClawGuard 监控状态</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { 
            color: #fff; 
            text-align: center; 
            margin-bottom: 30px;
            font-size: 2rem;
        }
        .status-card {
            background: rgba(255,255,255,0.1);
            border-radius: 15px;
            padding: 20px;
            margin-bottom: 15px;
            backdrop-filter: blur(10px);
        }
        .status-card h2 {
            color: #4fc3f7;
            margin-bottom: 15px;
            font-size: 1.2rem;
        }
        .metric {
            display: flex;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .metric:last-child { border-bottom: none; }
        .metric-label { color: #aaa; }
        .metric-value { 
            color: #fff; 
            font-weight: bold;
        }
        .status-ok { color: #4caf50 !important; }
        .status-error { color: #f44336 !important; }
        .status-warning { color: #ff9800 !important; }
        .footer {
            text-align: center;
            color: #666;
            margin-top: 30px;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🐕 ClawGuard 监控状态</h1>
        
        <div class="status-card">
            <h2>📊 系统状态</h2>
            <div class="metric">
                <span class="metric-label">Gateway 状态</span>
                <span class="metric-value $([ "$gateway_up" = "1" ] && echo "status-ok" || echo "status-error")">
                    $([ "$gateway_up" = "1" ] && echo "✅ 运行中" || echo "❌ 已停止")
                </span>
            </div>
            <div class="metric">
                <span class="metric-label">Gateway 内存</span>
                <span class="metric-value">${gateway_mem} MB</span>
            </div>
            <div class="metric">
                <span class="metric-label">系统负载</span>
                <span class="metric-value">${system_load}</span>
            </div>
            <div class="metric">
                <span class="metric-label">磁盘使用</span>
                <span class="metric-value $([ "$disk_usage" -gt 85 ] && echo "status-warning" || echo "")">
                    ${disk_usage}%
                </span>
            </div>
        </div>
        
        <div class="status-card">
            <h2>⏰ 运行信息</h2>
            <div class="metric">
                <span class="metric-label">最后更新</span>
                <span class="metric-value">${last_run_human}</span>
            </div>
            <div class="metric">
                <span class="metric-label">版本</span>
                <span class="metric-value">v6.1</span>
            </div>
        </div>
        
        <div class="footer">
            Powered by <a href="https://github.com/xw-xmy/clawguard" style="color: #4fc3f7;">ClawGuard</a>
        </div>
    </div>
</body>
</html>
EOF

echo "✅ 状态页已生成: $OUTPUT_FILE"
