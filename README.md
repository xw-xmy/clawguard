# 🐕 ClawGuard - OpenClaw 看门狗监控系统

<p align="center">
  <img src="https://img.shields.io/badge/version-6.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/bash-3.2%2B-green" alt="Bash">
  <img src="https://img.shields.io/badge/license-MIT-orange" alt="License">
  <img src="https://img.shields.io/badge/OpenClaw-2026.3%2B-yellow" alt="OpenClaw">
</p>

> OpenClaw 自动监控系统，定时任务调度与健康检查守护者

## ✨ 特性

- 🚀 **自动监控**: Gateway 进程健康检测 + 自动重启
- ⏰ **定时任务**: 支持 cron 表达式，智能任务检测 + 投递追踪
- 📊 **资源监控**: 内存、CPU、磁盘、负载实时监控
- 🔔 **智能告警**: 多通道告警 (QQ/Webhook/邮件)
- 🛡️ **多级降级**: API超时自动回退到日志模式
- 📈 **趋势分析**: 历史数据记录 + Prometheus 指标导出
- 🧹 **自动维护**: 日志轮转、错误趋势智能分析

## 📋 系统要求

- Linux (Ubuntu/Debian/CentOS)
- OpenClaw 已安装运行
- Bash 3.2+
- curl, ps, grep, free 等基础命令

## 🚀 快速开始

```bash
# 1. 克隆项目
git clone https://github.com/xw-xmy/clawguard.git
cd clawguard

# 2. 配置
cp monitor.conf.example monitor.conf
# 编辑配置文件，填入你的告警目标

# 3. 测试
./openclaw-monitor.sh
```

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `openclaw-monitor.sh` | 看门狗主脚本 (v6.0) |
| `maintenance.sh` | 系统维护脚本 |
| `monitor.conf.example` | 配置文件示例 |
| `install.sh` | 安装脚本 |
| `checkers/` | 模块化检查器目录 |

## ⚙️ 配置说明

```bash
# 告警目标 (QQ号)
ALERT_TARGET="qqbot:c2c:YOUR_QQ_ID"

# 阈值配置
MEMORY_THRESHOLD=1500      # Gateway 内存阈值(MB)
RESPONSE_THRESHOLD=3000    # 响应时间阈值(ms)
DISK_THRESHOLD=85          # 磁盘使用阈值(%)

# 已知任务 (空格分隔)
KNOWN_JOBS="cron-monitor openclaw-maintenance 看门狗"

# 备用告警通道
WEBHOOK_ENABLED=true
WEBHOOK_URL="https://your-webhook-url"

EMAIL_ENABLED=true
EMAIL_TO="your@email.com"
```

## 📊 监控指标

| 指标 | 说明 |
|------|------|
| Gateway 状态 | 进程是否存在 + HTTP 响应 |
| 响应时间 | Gateway 健康检查耗时 |
| 定时任务 | 执行状态 + 投递成功率 + 配置校验 |
| 内存使用 | Gateway + 系统总内存 |
| 磁盘使用 | 根分区使用率 |
| 错误日志 | 连接超时/API 错误/认证错误分类统计 |
| 通道状态 | QQ 发送/超时/错误统计 |

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

# 查看 Prometheus 指标
cat /tmp/openclaw/metrics.log
```

## 🔄 多级降级策略

当 OpenClaw API 不可用时，自动降级：

1. **优先**: 调用 `openclaw cron list` API
2. **回退**: 读取 `/root/.openclaw/cron/runs/*.jsonl` 日志
3. **最终**: 读取 Gateway 日志文件

## 📈 Prometheus 指标

输出标准 Prometheus 格式：

```
# HELP openclaw_gateway_up Gateway 进程运行状态
# TYPE openclaw_gateway_up gauge
openclaw_gateway_up 1

# HELP openclaw_gateway_memory_bytes Gateway 内存使用 (MB)
# TYPE openclaw_gateway_memory_bytes gauge
openclaw_gateway_memory_bytes 684

# HELP openclaw_disk_usage_percent 磁盘使用率
# TYPE openclaw_disk_usage_percent gauge
openclaw_disk_usage_percent 45
```

## 📈 版本历史

- **v6.0**: 扫描效率优化 + 智能错误分析 + Prometheus 指标 + 趋势报告增强
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
