# ClawGuard - OpenClaw 看门狗监控系统
# 基于轻量级 Alpine Linux

FROM alpine:3.19

LABEL maintainer="ClawGuard <https://github.com/xw-xmy/clawguard>"
LABEL description="OpenClaw Monitoring System"

# 安装必要工具
RUN apk add --no-cache \
    bash \
    curl \
    coreutils \
    grep \
    awk \
    sed \
    jq \
    ps \
    findutils \
    python3 \
    py3-pip

# 创建工作目录
WORKDIR /app

# 复制监控脚本
COPY openclaw-monitor.sh /usr/local/bin/
COPY monitor-ctl.sh /usr/local/bin/
COPY checkers/ /app/checkers/
COPY config.d/ /app/config.d/
COPY monitor.conf.example /app/monitor.conf.example

# 创建必要的目录
RUN mkdir -p /tmp/openclaw /var/log/clawguard

# 设置执行权限
RUN chmod +x /usr/local/bin/openclaw-monitor.sh \
             /usr/local/bin/monitor-ctl.sh

# 健康检查
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/openclaw-monitor.sh > /dev/null 2>&1 || exit 1

# 默认命令
CMD ["/usr/local/bin/openclaw-monitor.sh"]
