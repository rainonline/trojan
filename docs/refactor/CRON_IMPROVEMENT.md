# 定时任务改进方案

## 📊 当前实现分析

### 存在的问题

#### 1. **资源泄漏风险**
```go
// web/controller/common.go:118
func CollectTask() {
    c := cron.New()
    // ... 
    c.Start()  // ❌ 没有 Stop 机制，无法优雅关闭
}

// web/controller/data.go:83
var c *cron.Cron  // ❌ 全局变量，无生命周期管理

func ScheduleTask() {
    c = cron.New(cron.WithLocation(loc))
    // ...
    c.Start()  // ❌ 没有 Stop 机制
}
```

**问题**：
- 程序退出时 cron goroutine 无法正常停止
- 可能导致任务执行到一半被强制终止
- 资源无法正确释放（数据库连接、文件句柄等）

#### 2. **多个独立 cron 实例**
```go
// common.go 中一个 cron 实例
c := cron.New()

// data.go 中另一个 cron 实例
var c *cron.Cron
c = cron.New(cron.WithLocation(loc))
```

**问题**：
- 两个独立的 cron 实例，管理复杂
- 无法统一控制和监控
- 内存占用增加（每个实例都有独立的 goroutine 池）

#### 3. **错误处理不足**
```go
// web/controller/data.go:88
c.AddFunc("@daily", func() {
    mysql := core.GetMysql()
    if needRestart, err := mysql.DailyCheckExpire(); err != nil {
        fmt.Println("DailyCheckError: " + err.Error())  // ❌ 仅打印到控制台
    }
})
```

**问题**：
- 错误仅通过 fmt.Println 输出，可能被忽略
- 没有日志记录、告警机制
- 无法追踪任务执行历史

#### 4. **缺少监控和可观测性**
- 无法查看任务执行状态
- 无法统计任务执行次数、耗时
- 没有任务执行失败重试机制

#### 5. **时区处理不一致**
```go
// common.go 没有指定时区
c := cron.New()

// data.go 指定了上海时区
loc, _ := time.LoadLocation("Asia/Shanghai")
c = cron.New(cron.WithLocation(loc))
```

## 🎯 改进方案

### 核心思路

创建统一的 **定时任务管理器**，提供以下能力：

1. ✅ **统一管理**：单例模式，所有任务在一个 cron 实例中
2. ✅ **优雅关闭**：支持 context 取消和超时控制
3. ✅ **错误处理**：完善的日志记录和错误恢复机制
4. ✅ **监控能力**：任务执行统计、健康检查
5. ✅ **可扩展性**：易于添加新任务，支持动态配置

### 实现架构

```
┌──────────────────────────────────────────┐
│          TaskScheduler (单例)             │
├──────────────────────────────────────────┤
│ - cron *cron.Cron                        │
│ - ctx context.Context                    │
│ - cancel context.CancelFunc              │
│ - wg sync.WaitGroup                      │
│ - tasks map[string]*TaskStats            │
│ - mu sync.RWMutex                        │
├──────────────────────────────────────────┤
│ + Start()                                │
│ + Stop(timeout)                          │
│ + AddTask(name, spec, func)              │
│ + RemoveTask(name)                       │
│ + GetTaskStats() []TaskStats             │
│ + Health() bool                          │
└──────────────────────────────────────────┘
```

### 核心特性

#### 1. 优雅关闭机制
```go
func (s *TaskScheduler) Stop(timeout time.Duration) error {
    s.cancel()  // 取消 context
    
    // 等待所有任务完成（带超时）
    done := make(chan struct{})
    go func() {
        s.wg.Wait()
        close(done)
    }()
    
    select {
    case <-done:
        return nil
    case <-time.After(timeout):
        return ErrShutdownTimeout
    }
}
```

#### 2. 任务包装器（带错误恢复）
```go
func (s *TaskScheduler) wrapTask(name string, fn func() error) func() {
    return func() {
        s.wg.Add(1)
        defer s.wg.Done()
        
        // 检查是否已取消
        select {
        case <-s.ctx.Done():
            return
        default:
        }
        
        start := time.Now()
        
        // Panic 恢复
        defer func() {
            if r := recover(); r != nil {
                s.recordError(name, fmt.Errorf("panic: %v", r))
            }
        }()
        
        // 执行任务
        if err := fn(); err != nil {
            s.recordError(name, err)
        } else {
            s.recordSuccess(name, time.Since(start))
        }
    }
}
```

#### 3. 任务统计
```go
type TaskStats struct {
    Name         string
    Spec         string
    LastRun      time.Time
    NextRun      time.Time
    ExecuteCount int64
    ErrorCount   int64
    LastError    string
    AvgDuration  time.Duration
}
```

## 📝 实施步骤

### 步骤 1：创建任务调度器模块
创建 `core/scheduler.go`：
- 实现 TaskScheduler 结构
- 提供单例访问
- 实现优雅关闭

### 步骤 2：迁移现有任务
更新 `web/controller/common.go` 和 `data.go`：
- 使用统一的调度器
- 添加错误处理
- 记录任务统计

### 步骤 3：集成到 Web 启动流程
更新 `web/web.go`：
- 在启动时初始化调度器
- 在关闭时优雅停止

### 步骤 4：添加监控端点
添加 API 端点：
- `GET /admin/tasks` - 查看任务列表
- `GET /admin/tasks/stats` - 任务执行统计

## 🔍 对比分析

| 维度 | 当前实现 | 改进方案 |
|------|---------|---------|
| **cron 实例数** | 2 个独立实例 | 1 个统一实例 |
| **优雅关闭** | ❌ 不支持 | ✅ 支持 context 取消 + 超时等待 |
| **错误处理** | fmt.Println | ✅ 结构化日志 + 错误统计 |
| **Panic 恢复** | ❌ 无 | ✅ defer recover |
| **任务监控** | ❌ 无 | ✅ 执行次数、耗时、错误率 |
| **时区一致性** | ❌ 不一致 | ✅ 统一使用 Asia/Shanghai |
| **资源管理** | ❌ 可能泄漏 | ✅ WaitGroup + Context |
| **可测试性** | ❌ 难以测试 | ✅ 接口化，易于 mock |

## 📦 依赖升级建议

当前使用 `github.com/robfig/cron/v3 v3.0.1`（2020 年发布）

**建议升级到 v3.0.4+**（支持更多特性）：
- 更好的 context 支持
- 改进的错误处理
- 性能优化

或者考虑其他方案：
1. **gocron** - `github.com/go-co-op/gocron`
   - 更现代的 API
   - 内置任务标签、单例执行
   - 更好的监控支持

2. **asynq** - `github.com/hibiken/asynq`
   - 基于 Redis 的分布式任务队列
   - 支持任务重试、优先级
   - 适合分布式部署

## 🚀 快速开始（改进后）

```go
// 初始化
scheduler := core.GetScheduler()
defer scheduler.Stop(10 * time.Second)

// 添加任务
scheduler.AddTask("collect_speed", "@every 2s", func() error {
    // 网络速度收集
    return collectNetworkSpeed()
})

scheduler.AddTask("daily_expire_check", "@daily", func() error {
    mysql := core.GetMysql()
    needRestart, err := mysql.DailyCheckExpire()
    if err != nil {
        return err
    }
    if needRestart {
        trojan.Restart()
    }
    return nil
})

// 启动
scheduler.Start()

// 查看统计
stats := scheduler.GetTaskStats()
for _, stat := range stats {
    fmt.Printf("Task: %s, Runs: %d, Errors: %d\n", 
        stat.Name, stat.ExecuteCount, stat.ErrorCount)
}
```

## 🔗 相关文档

- [robfig/cron 官方文档](https://pkg.go.dev/github.com/robfig/cron/v3)
- [Go 并发模式：Context](https://go.dev/blog/context)
- [优雅关闭最佳实践](https://www.rudderstack.com/blog/implementing-graceful-shutdown-in-go/)

## 📋 后续优化

1. **任务持久化**：将任务配置存储到数据库
2. **分布式锁**：多实例部署时避免重复执行
3. **WebSocket 推送**：任务状态实时推送到前端
4. **告警集成**：任务失败时发送通知（邮件/Webhook）
5. **任务链**：支持任务依赖和顺序执行
