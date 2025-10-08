package core

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/robfig/cron/v3"
)

var (
	schedulerInstance *TaskScheduler
	schedulerOnce     sync.Once
)

// TaskStats 任务执行统计
type TaskStats struct {
	Name         string        `json:"name"`
	Spec         string        `json:"spec"`
	LastRun      time.Time     `json:"last_run"`
	NextRun      time.Time     `json:"next_run"`
	ExecuteCount int64         `json:"execute_count"`
	ErrorCount   int64         `json:"error_count"`
	LastError    string        `json:"last_error,omitempty"`
	TotalDuration time.Duration `json:"total_duration"`
	AvgDuration  time.Duration `json:"avg_duration"`
}

// Task 任务定义
type Task struct {
	Name    string
	Spec    string
	Func    func() error
	EntryID cron.EntryID
	Stats   *TaskStats
}

// TaskScheduler 统一的任务调度器
type TaskScheduler struct {
	cron   *cron.Cron
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
	tasks  map[string]*Task
	mu     sync.RWMutex
	logger *log.Logger
}

// GetScheduler 获取调度器单例
func GetScheduler() *TaskScheduler {
	schedulerOnce.Do(func() {
		ctx, cancel := context.WithCancel(context.Background())
		loc, _ := time.LoadLocation("Asia/Shanghai")
		
		schedulerInstance = &TaskScheduler{
			cron:   cron.New(cron.WithLocation(loc), cron.WithSeconds()),
			ctx:    ctx,
			cancel: cancel,
			tasks:  make(map[string]*Task),
			logger: log.New(log.Writer(), "[TaskScheduler] ", log.LstdFlags),
		}
	})
	return schedulerInstance
}

// Start 启动调度器
func (s *TaskScheduler) Start() {
	s.mu.Lock()
	defer s.mu.Unlock()
	
	if len(s.cron.Entries()) > 0 {
		s.logger.Println("Starting task scheduler with", len(s.tasks), "tasks")
		s.cron.Start()
	}
}

// Stop 优雅停止调度器
func (s *TaskScheduler) Stop(timeout time.Duration) error {
	s.logger.Println("Stopping task scheduler...")
	
	// 停止接受新任务
	stopCtx := s.cron.Stop()
	
	// 取消所有正在执行的任务的 context
	s.cancel()
	
	// 等待所有任务完成（带超时）
	done := make(chan struct{})
	go func() {
		s.wg.Wait()
		close(done)
	}()
	
	// 等待 cron 停止和任务完成
	select {
	case <-stopCtx.Done():
		s.logger.Println("Cron stopped")
	case <-time.After(timeout):
		s.logger.Println("Warning: Cron stop timeout")
	}
	
	select {
	case <-done:
		s.logger.Println("All tasks completed gracefully")
		return nil
	case <-time.After(timeout):
		s.logger.Println("Warning: Task completion timeout, some tasks may be interrupted")
		return fmt.Errorf("shutdown timeout after %v", timeout)
	}
}

// AddTask 添加任务
func (s *TaskScheduler) AddTask(name, spec string, fn func() error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	
	// 检查任务是否已存在
	if _, exists := s.tasks[name]; exists {
		return fmt.Errorf("task %s already exists", name)
	}
	
	// 创建任务统计
	stats := &TaskStats{
		Name: name,
		Spec: spec,
	}
	
	// 包装任务函数
	wrappedFunc := s.wrapTask(name, fn, stats)
	
	// 添加到 cron
	entryID, err := s.cron.AddFunc(spec, wrappedFunc)
	if err != nil {
		return fmt.Errorf("failed to add task %s: %w", name, err)
	}
	
	// 保存任务信息
	s.tasks[name] = &Task{
		Name:    name,
		Spec:    spec,
		Func:    fn,
		EntryID: entryID,
		Stats:   stats,
	}
	
	s.logger.Printf("Task added: %s (spec: %s)", name, spec)
	return nil
}

// RemoveTask 移除任务
func (s *TaskScheduler) RemoveTask(name string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	
	task, exists := s.tasks[name]
	if !exists {
		return fmt.Errorf("task %s not found", name)
	}
	
	s.cron.Remove(task.EntryID)
	delete(s.tasks, name)
	
	s.logger.Printf("Task removed: %s", name)
	return nil
}

// wrapTask 包装任务，添加错误处理和统计
func (s *TaskScheduler) wrapTask(name string, fn func() error, stats *TaskStats) func() {
	return func() {
		s.wg.Add(1)
		defer s.wg.Done()
		
		// 检查是否已取消
		select {
		case <-s.ctx.Done():
			s.logger.Printf("Task %s cancelled", name)
			return
		default:
		}
		
		start := time.Now()
		
		// Panic 恢复
		defer func() {
			if r := recover(); r != nil {
				s.recordError(stats, fmt.Errorf("panic: %v", r))
				s.logger.Printf("Task %s panicked: %v", name, r)
			}
		}()
		
		// 执行任务
		s.logger.Printf("Task %s started", name)
		if err := fn(); err != nil {
			s.recordError(stats, err)
			s.logger.Printf("Task %s failed: %v", name, err)
		} else {
			s.recordSuccess(stats, time.Since(start))
			s.logger.Printf("Task %s completed in %v", name, time.Since(start))
		}
	}
}

// recordSuccess 记录成功执行
func (s *TaskScheduler) recordSuccess(stats *TaskStats, duration time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	
	stats.LastRun = time.Now()
	stats.ExecuteCount++
	stats.TotalDuration += duration
	stats.AvgDuration = time.Duration(int64(stats.TotalDuration) / stats.ExecuteCount)
	stats.LastError = ""
}

// recordError 记录错误
func (s *TaskScheduler) recordError(stats *TaskStats, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	
	stats.LastRun = time.Now()
	stats.ExecuteCount++
	stats.ErrorCount++
	stats.LastError = err.Error()
}

// GetTaskStats 获取所有任务统计
func (s *TaskScheduler) GetTaskStats() []TaskStats {
	s.mu.RLock()
	defer s.mu.RUnlock()
	
	stats := make([]TaskStats, 0, len(s.tasks))
	entries := s.cron.Entries()
	
	for _, task := range s.tasks {
		taskStats := *task.Stats
		
		// 查找下次执行时间
		for _, entry := range entries {
			if entry.ID == task.EntryID {
				taskStats.NextRun = entry.Next
				break
			}
		}
		
		stats = append(stats, taskStats)
	}
	
	return stats
}

// Health 健康检查
func (s *TaskScheduler) Health() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	
	// 检查是否有任务
	if len(s.tasks) == 0 {
		return false
	}
	
	// 检查是否有任务执行失败率过高
	for _, task := range s.tasks {
		if task.Stats.ExecuteCount > 0 {
			errorRate := float64(task.Stats.ErrorCount) / float64(task.Stats.ExecuteCount)
			if errorRate > 0.5 { // 失败率超过 50%
				s.logger.Printf("Warning: Task %s has high error rate: %.2f%%", task.Name, errorRate*100)
				return false
			}
		}
	}
	
	return true
}

// GetContext 获取调度器的 context（用于任务中）
func (s *TaskScheduler) GetContext() context.Context {
	return s.ctx
}

// IsRunning 检查调度器是否正在运行
func (s *TaskScheduler) IsRunning() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	
	entries := s.cron.Entries()
	return len(entries) > 0
}
