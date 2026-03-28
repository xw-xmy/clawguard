# 🐕 ClawGuard - OpenClaw 看门狗监控系统

<p align="center">
  <img src="https://img.shields.io/badge/version-5.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/bash-3.2%2B-green" alt="Bash">
  <img src="https://img.shields.io/badge/license-MIT-orange" alt="License">
</p>

> OpenClaw 自动监控系统，定时任务调度与健康检查守护者

## ✨ 特性

- 🚀 **自动监控**: Gateway 进程健康检测
- ⏰ **定时任务**: 支持cron表达式，智能任务检测
- 📊 **资源监控**: 内存、CPU、磁盘实时监控
- 🔔 **智能告警**: 异常自动告警，支持QQ/企微/Webhook
- 🛡️ **自动修复**: 进程崩溃自动重启
- 📈 **趋势分析**: 历史数据记录与趋势报告

## 📋 系统要求

- Linux (Ubuntu/Debian/CentOS)
- OpenClaw 已安装运行
- Bash 3.2+
- curl, ps, grep, free 等基础命令

## 🚀 快速开始

```bash
# 1. 克隆项目
git clone https://github.com/your-repo/clawguard.git
cd clawguard

# 2. 配置
cp monitor.conf.example monitor.conf
# 编辑配置文件，填入你的QQ号

# 3. 安装
sudo ./install.sh

# 4. 测试
./openclaw-monitor.sh
```

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `openclaw-monitor.sh` | 看门狗主脚本 |
| `maintenance.sh` | 系统维护脚本 |
| `monitor.conf` | 配置文件 |
| `install.sh` | 安装脚本 |

## ⚙️ 配置说明

```bash
# 告警目标 (QQ号)
ALERT_TARGET="qqbot:c2c:YOUR_QQ_ID"

# 阈值配置
MEMORY_THRESHOLD=1500      # Gateway内存阈值(MB)
RESPONSE_THRESHOLD=3000    # 响应时间阈值(ms)
DISK_THRESHOLD=85          # 磁盘使用阈值(%)

# 已知任务 (空格分隔)
KNOWN_JOBS="每日新闻简报 每日AI早报 cron-monitor openclaw-maintenance"
```

## 📊 监控指标

| 指标 | 说明 |
|------|------|
| Gateway状态 | 进程是否存在 + HTTP响应 |
| 响应时间 | Gateway健康检查耗时 |
| 定时任务 | 执行状态 + 投递成功率 |
| 内存使用 | Gateway + 系统总内存 |
| 磁盘使用 | 根分区使用率 |
| 错误日志 | ERROR/FATAL 统计 |

## 🔧 使用方法

```bash
# 手动运行
./openclaw-monitor.sh

# 添加定时任务 (每小时)
crontab -e
0 * * * * /path/to/openclaw-monitor.sh >> /var/log/clawguard.log 2>&1

# 查看日志
tail -f /tmp/openclaw/monitor.log

# 热重载配置
kill -SIGHUP $(pgrep -f openclaw-monitor.sh)
```

## 🎯 定时任务配置

创建定时任务示例：

```bash
# 新闻简报: 6:50抓取 → 7:00推送
openclaw cron add --name "新闻简报" \
  --cron "50 6 * * *" \
  --tz "Asia/Shanghai" \
  --message "推送今日全球新闻简报" \
  --channel qqbot --to "qqbot:c2c:YOUR_QQ_ID" \
  --announce
```

## 📈 版本历史

- **v5.0**: 配置文件外部化、智能去重、集群支持
- **v4.0**: 错误聚合、通道健康评分
- **v3.0**: 动态日志、投递状态检测
- **v2.0**: 自动修复、告警机制
- **v1.0**: 基础监控

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License - 请自由使用和修改

---

Made with ❤️ for OpenClaw
