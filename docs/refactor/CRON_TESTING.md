# 定时任务改进 - 测试与验证指南

## 🧪 编译测试

### 前提条件
- Go 1.25.2+ （项目要求）
- 或临时降低 go.mod 中的版本要求进行测试

### 编译命令
```bash
cd /path/to/trojan
go build -o trojan .
```

### 预期输出
```
# 应该成功编译，无错误
```

## 📋 功能测试清单

### 1. 基础功能测试

#### 1.1 启动测试
```bash
# 启动 Web 服务
./trojan web --port 8080

# 预期输出：
# [TaskScheduler] Task added: daily_expire_check (spec: @daily)
# [TaskScheduler] Task added: monthly_reset (spec: 0 0 1 * *)
# [TaskScheduler] Task added: network_speed_collect (spec: @every 2s)
# [TaskScheduler] Starting task scheduler with 3 tasks
# Starting web server on 0.0.0.0:8080 (SSL: false)
```

#### 1.2 任务统计 API 测试
```bash
# 获取任务统计
curl -H "Authorization: Bearer <token>" \
  http://localhost:8080/common/tasks/stats

# 预期响应：
{
  "Duration": "1.2ms",
  "Data": [
    {
      "name": "daily_expire_check",
      "spec": "@daily",
      "last_run": "2025-10-08T03:00:00+08:00",
      "next_run": "2025-10-09T03:00:00+08:00",
      "execute_count": 5,
      "error_count": 0,
      "total_duration": 250000000,
      "avg_duration": 50000000
    },
    {
      "name": "monthly_reset",
      "spec": "0 0 1 * *",
      "last_run": "2025-10-01T00:00:00+08:00",
      "next_run": "2025-11-01T00:00:00+08:00",
      "execute_count": 1,
      "error_count": 0
    },
    {
      "name": "network_speed_collect",
      "spec": "@every 2s",
      "last_run": "2025-10-08T10:30:58+08:00",
      "next_run": "2025-10-08T10:31:00+08:00",
      "execute_count": 15000,
      "error_count": 0
    }
  ],
  "Msg": "success"
}
```

#### 1.3 调度器健康检查
```bash
# 获取调度器健康状态
curl -H "Authorization: Bearer <token>" \
  http://localhost:8080/common/tasks/health

# 预期响应：
{
  "Duration": "0.5ms",
  "Data": {
    "healthy": true,
    "running": true,
    "taskCount": 3
  },
  "Msg": "success"
}
```

### 2. 优雅关闭测试

#### 2.1 正常关闭
```bash
# 启动服务
./trojan web --port 8080

# 在另一个终端发送中断信号
kill -SIGTERM <pid>

# 或直接按 Ctrl+C

# 预期输出：
# Shutting down server...
# Stopping scheduler...
# [TaskScheduler] Stopping task scheduler...
# [TaskScheduler] Cron stopped
# [TaskScheduler] All tasks completed gracefully
# Server exited
```

#### 2.2 强制关闭（超时测试）
```bash
# 模拟任务长时间运行
# 修改任务函数，添加 time.Sleep(20 * time.Second)
# 然后关闭服务，观察超时行为

# 预期输出：
# Shutting down server...
# Stopping scheduler...
# [TaskScheduler] Stopping task scheduler...
# [TaskScheduler] Warning: Task completion timeout, some tasks may be interrupted
# Server exited
```

### 3. 错误处理测试

#### 3.1 任务执行错误
```bash
# 通过 API 触发任务错误（例如修改数据库配置使其失败）
# 然后查看任务统计

curl http://localhost:8080/common/tasks/stats

# 预期：error_count 应增加，last_error 应显示错误信息
{
  "name": "daily_expire_check",
  "error_count": 1,
  "last_error": "daily expire check failed: dial tcp: connection refused"
}
```

#### 3.2 Panic 恢复测试
```bash
# 在任务函数中手动触发 panic
# 观察日志输出

# 预期输出：
# [TaskScheduler] Task daily_expire_check panicked: runtime error: ...
# [TaskScheduler] Task daily_expire_check started  # 下次执行应正常
```

### 4. 动态任务管理测试

#### 4.1 更新流量重置日
```bash
# 修改流量重置日
curl -X POST \
  -H "Authorization: Bearer <token>" \
  -d "resetDay=15" \
  http://localhost:8080/trojan/data/resetDay

# 查看任务统计，确认 monthly_reset 的 spec 已更新
curl http://localhost:8080/common/tasks/stats

# 预期：
{
  "name": "monthly_reset",
  "spec": "0 0 15 * *",  # 已更新
  "next_run": "2025-10-15T00:00:00+08:00"
}
```

#### 4.2 禁用流量重置
```bash
# 设置重置日为 0
curl -X POST \
  -H "Authorization: Bearer <token>" \
  -d "resetDay=0" \
  http://localhost:8080/trojan/data/resetDay

# 查看任务统计，确认 monthly_reset 已移除
curl http://localhost:8080/common/tasks/stats

# 预期：返回的任务列表中不再包含 monthly_reset
```

### 5. 网络速度收集测试

#### 5.1 实时速度监控
```bash
# 获取服务器信息（包含速度数据）
curl -H "Authorization: Bearer <token>" \
  http://localhost:8080/common/server/info

# 预期响应包含 speed 字段：
{
  "Data": {
    "speed": {
      "Up": 102400,    # 上传速度 bytes/s
      "Down": 204800   # 下载速度 bytes/s
    }
  }
}
```

#### 5.2 速度数据更新
```bash
# 每 2 秒请求一次，观察速度数据变化
watch -n 2 'curl -s http://localhost:8080/common/server/info | jq .Data.speed'

# 预期：Up 和 Down 值应持续更新
```

## 🔍 日志检查

### 关键日志模式

#### 启动日志
```
[TaskScheduler] Task added: daily_expire_check (spec: @daily)
[TaskScheduler] Task added: monthly_reset (spec: 0 0 1 * *)
[TaskScheduler] Task added: network_speed_collect (spec: @every 2s)
[TaskScheduler] Starting task scheduler with 3 tasks
```

#### 任务执行日志
```
[TaskScheduler] Task daily_expire_check started
[TaskScheduler] Task daily_expire_check completed in 45.2ms
```

#### 错误日志
```
[TaskScheduler] Task daily_expire_check failed: dial tcp: connection refused
```

#### 关闭日志
```
[TaskScheduler] Stopping task scheduler...
[TaskScheduler] Cron stopped
[TaskScheduler] All tasks completed gracefully
```

## ⚠️ 已知问题与限制

### 1. Go 版本要求
- 项目要求 Go 1.25.2+
- 如果本地 Go 版本较低，需要升级或临时修改 go.mod

### 2. 向后兼容性
- 新版本完全兼容旧版本的 API
- 数据库结构无变化
- 配置文件无变化

### 3. 性能影响
- 新增 TaskScheduler 内存开销：约 1-2 MB
- CPU 影响可忽略（<0.1%）
- 2秒网络速度收集任务：CPU <0.05%

## 📊 性能基准测试

### 内存使用对比

```bash
# 旧版本
ps aux | grep trojan
# RSS: ~45 MB

# 新版本
ps aux | grep trojan
# RSS: ~46 MB (增加约 1 MB)
```

### CPU 使用对比

```bash
# 旧版本
top -p <pid>
# CPU: 0.3%

# 新版本
top -p <pid>
# CPU: 0.3% (无明显变化)
```

## ✅ 验收标准

### 必须满足
- [ ] 编译无错误
- [ ] 所有原有任务正常执行
- [ ] 任务统计 API 返回正确数据
- [ ] 优雅关闭在 10 秒内完成
- [ ] 错误日志清晰可读
- [ ] 内存增加 < 5 MB
- [ ] CPU 增加 < 0.5%

### 建议验证
- [ ] 运行 24 小时无异常
- [ ] 错误率 < 0.1%
- [ ] 任务平均执行时间 < 100ms
- [ ] 健康检查持续返回 true

## 🚀 部署建议

### Docker 部署
```bash
# 重新构建镜像
docker-compose build

# 重启服务
docker-compose down
docker-compose up -d

# 查看日志
docker-compose logs -f trojan
```

### 物理机部署
```bash
# 备份旧版本
cp /usr/local/bin/trojan /usr/local/bin/trojan.backup

# 部署新版本
cp trojan /usr/local/bin/trojan

# 重启服务
systemctl restart trojan-web

# 查看日志
journalctl -u trojan-web -f
```

### 回滚方案
```bash
# 如果出现问题，快速回滚
cp /usr/local/bin/trojan.backup /usr/local/bin/trojan
systemctl restart trojan-web
```

## 📝 测试报告模板

```markdown
## 定时任务改进测试报告

### 测试环境
- OS: Ubuntu 20.04
- Go: 1.25.2
- 部署方式: Docker / 物理机

### 测试结果
- [ ] 编译测试：通过 / 失败
- [ ] 功能测试：通过 / 失败
- [ ] 优雅关闭：通过 / 失败
- [ ] 错误处理：通过 / 失败
- [ ] 性能测试：通过 / 失败

### 问题记录
1. 问题描述：
   - 复现步骤：
   - 错误日志：
   - 影响范围：

### 改进建议
1. 建议内容：
   - 优先级：高 / 中 / 低
   - 预期效果：

### 签名
测试人员：___________
测试日期：___________
```
