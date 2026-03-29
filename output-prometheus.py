#!/usr/bin/env python3
import os, subprocess, json, re, time

metrics = []

# Gateway 内存
try:
    pid = subprocess.check_output(['pgrep', '-f', 'openclaw-gateway']).decode().strip().split()[0]
    mem = int(subprocess.check_output(['ps', '-o', 'rss=', '-p', pid]).decode().strip()) // 1024
    metrics.append(f"openclaw_gateway_memory_bytes {mem * 1024 * 1024}")
except:
    pass

# Gateway 进程数
try:
    procs = len(subprocess.check_output(['pgrep', '-f', 'openclaw-gateway']).decode().strip().split())
    metrics.append(f"openclaw_gateway_processes {procs}")
except:
    metrics.append("openclaw_gateway_processes 0")

# Cron 任务数
try:
    with open('/root/.openclaw/cron/jobs.json') as f:
        jobs = json.load(f).get('jobs', [])
    total = len(jobs)
    enabled = sum(1 for j in jobs if j.get('enabled', False))
    metrics.append(f"openclaw_cron_jobs_total {total}")
    metrics.append(f"openclaw_cron_jobs_enabled {enabled}")
except:
    pass

# 通道健康
try:
    with open('/tmp/openclaw/monitor.log') as f:
        for line in f:
            if '通道健康' in line:
                m = re.search(r'(\d+)/100', line)
                if m:
                    metrics.append(f"openclaw_channel_health {m.group(1)}")
                break
except:
    pass

# 系统负载
try:
    load = subprocess.check_output(['uptime']).decode()
    m = re.search(r'load average:\s*([0-9.]+)', load)
    if m:
        metrics.append(f"openclaw_system_load {m.group(1)}")
except:
    pass

# 系统内存
try:
    mem = subprocess.check_output(['free', '-m']).decode()
    parts = mem.strip().split('\n')[1].split()
    mem_used = int(parts[2])
    mem_total = int(parts[1])
    metrics.append(f"openclaw_system_memory_bytes {mem_used * 1024 * 1024}")
    metrics.append(f"openclaw_system_memory_total_bytes {mem_total * 1024 * 1024}")
except:
    pass

# 磁盘
try:
    disk = subprocess.check_output(['df', '/']).decode().strip().split('\n')[1].split()[4]
    disk_pct = int(disk.replace('%', ''))
    metrics.append(f"openclaw_disk_usage_percent {disk_pct}")
except:
    pass

metrics.append(f"openclaw_exporter_last_scrape {int(time.time())}")

with open('/tmp/openclaw/metrics.prom', 'w') as f:
    f.write('\n'.join(metrics) + '\n')
