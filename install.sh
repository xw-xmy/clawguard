#!/bin/bash
# 🐕 ClawGuard 安装脚本

set -e

echo "🐕 ClawGuard 安装程序"
echo "===================="

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️ 建议使用 sudo 运行"
fi

# 检查OpenClaw
if ! command -v openclaw &> /dev/null; then
    echo "❌ 未检测到 OpenClaw，请先安装 OpenClaw"
    exit 1
fi

echo "✅ OpenClaw 已安装"

# 检查配置文件
if [ ! -f "monitor.conf" ]; then
    echo "📝 创建配置文件..."
    cp monitor.conf.example monitor.conf
    echo "⚠️ 请编辑 monitor.conf 填入你的QQ号"
fi

# 检查OpenClaw目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_SCRIPT_DIR="/root/.openclaw/scripts"

# 复制脚本
echo "📦 安装脚本..."
cp -f openclaw-monitor.sh "$OPENCLAW_SCRIPT_DIR/"
cp -f maintenance.sh "$OPENCLAW_SCRIPT_DIR/"

# 设置权限
chmod +x openclaw-monitor.sh
chmod +x maintenance.sh

# 添加定时任务 (可选)
echo ""
echo "是否添加每小时定时任务? (y/n)"
read -r add_cron

if [ "$add_cron" = "y" ] || [ "$add_cron" = "Y" ]; then
    # 检查是否已有定时任务
    if crontab -l 2>/dev/null | grep -q "openclaw-monitor.sh"; then
        echo "⚠️ 定时任务已存在，跳过"
    else
        (crontab -l 2>/dev/null || true; echo "0 * * * * $OPENCLAW_SCRIPT_DIR/openclaw-monitor.sh >> /tmp/openclaw/monitor.log 2>&1") | crontab -
        echo "✅ 已添加定时任务 (每小时整点)"
    fi
fi

echo ""
echo "===================="
echo "🎉 安装完成!"
echo ""
echo "📋 使用方法:"
echo "   手动运行: $OPENCLAW_SCRIPT_DIR/openclaw-monitor.sh"
echo "   查看日志: tail -f /tmp/openclaw/monitor.log"
echo "   配置告警: 编辑 monitor.conf"
echo ""
echo "⚠️ 记得修改 monitor.conf 中的 ALERT_TARGET 为你的QQ号!"
