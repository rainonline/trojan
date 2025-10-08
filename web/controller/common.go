package controller

import (
	"github.com/gin-gonic/gin"
	"github.com/shirou/gopsutil/cpu"
	"github.com/shirou/gopsutil/disk"
	"github.com/shirou/gopsutil/load"
	"github.com/shirou/gopsutil/mem"
	"github.com/shirou/gopsutil/net"
	"time"
	"trojan/asset"
	"trojan/core"
	"trojan/trojan"
)

// ResponseBody 结构体
type ResponseBody struct {
	Duration string
	Data     interface{}
	Msg      string
}

type speedInfo struct {
	Up   uint64
	Down uint64
}

var si *speedInfo

// TimeCost web函数执行用时统计方法
func TimeCost(start time.Time, body *ResponseBody) {
	body.Duration = time.Since(start).String()
}

func clashRules() string {
	rules, _ := core.GetValue("clash-rules")
	if rules == "" {
		rules = string(asset.GetAsset("clash-rules.yaml"))
	}
	return rules
}

// Version 获取版本信息
func Version() *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	responseBody.Data = map[string]string{
		"version":       trojan.MVersion,
		"buildDate":     trojan.BuildDate,
		"goVersion":     trojan.GoVersion,
		"gitVersion":    trojan.GitVersion,
		"trojanVersion": trojan.Version(),
		"trojanUptime":  trojan.UpTime(),
		"trojanType":    trojan.Type(),
	}
	return &responseBody
}

// SetLoginInfo 设置登录页信息
func SetLoginInfo(title string) *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	err := core.SetValue("login_title", title)
	if err != nil {
		responseBody.Msg = err.Error()
	}
	return &responseBody
}

// SetDomain 设置域名
func SetDomain(domain string) *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	trojan.SetDomain(domain)
	return &responseBody
}

// SetClashRules 设置clash规则
func SetClashRules(rules string) *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	core.SetValue("clash-rules", rules)
	return &responseBody
}

// ResetClashRules 重置clash规则
func ResetClashRules() *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	core.DelValue("clash-rules")
	responseBody.Data = clashRules()
	return &responseBody
}

// GetClashRules 获取clash规则
func GetClashRules() *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	responseBody.Data = clashRules()
	return &responseBody
}

// SetTrojanType 设置trojan类型
func SetTrojanType(tType string) *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	err := trojan.SwitchType(tType)
	if err != nil {
		responseBody.Msg = err.Error()
	}
	return &responseBody
}

// CollectTask 启动收集主机信息任务
func CollectTask() {
	var recvCount, sentCount uint64
	lastIO, _ := net.IOCounters(true)
	var lastRecvCount, lastSentCount uint64
	for _, k := range lastIO {
		lastRecvCount = lastRecvCount + k.BytesRecv
		lastSentCount = lastSentCount + k.BytesSent
	}
	si = &speedInfo{}
	
	// 使用统一的调度器
	scheduler := core.GetScheduler()
	scheduler.AddTask("network_speed_collect", "@every 2s", func() error {
		result, err := net.IOCounters(true)
		if err != nil {
			return err
		}
		recvCount, sentCount = 0, 0
		for _, k := range result {
			recvCount = recvCount + k.BytesRecv
			sentCount = sentCount + k.BytesSent
		}
		si.Up = (sentCount - lastSentCount) / 2
		si.Down = (recvCount - lastRecvCount) / 2
		lastSentCount = sentCount
		lastRecvCount = recvCount
		lastIO = result
		return nil
	})
}

// Health 健康检查端点（用于 Docker/Kubernetes）
func Health(c *gin.Context) {
	// 检查数据库连接
	mysql := core.GetMysql()
	db := mysql.GetDB()
	if err := db.Ping(); err != nil {
		c.JSON(503, gin.H{
			"status":  "unhealthy",
			"error":   "database connection failed",
			"message": err.Error(),
		})
		return
	}
	
	c.JSON(200, gin.H{
		"status":    "healthy",
		"version":   trojan.MVersion,
		"buildDate": trojan.BuildDate,
		"timestamp": time.Now().Unix(),
	})
}

// ServerInfo 获取服务器信息
func ServerInfo() *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	cpuPercent, _ := cpu.Percent(0, false)
	vmInfo, _ := mem.VirtualMemory()
	smInfo, _ := mem.SwapMemory()
	diskInfo, _ := disk.Usage("/")
	loadInfo, _ := load.Avg()
	tcpCon, _ := net.Connections("tcp")
	udpCon, _ := net.Connections("udp")
	netCount := map[string]int{
		"tcp": len(tcpCon),
		"udp": len(udpCon),
	}
	responseBody.Data = map[string]interface{}{
		"cpu":      cpuPercent,
		"memory":   vmInfo,
		"swap":     smInfo,
		"disk":     diskInfo,
		"load":     loadInfo,
		"speed":    si,
		"netCount": netCount,
	}
	return &responseBody
}

// GetTaskStats 获取定时任务统计信息
func GetTaskStats() *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	scheduler := core.GetScheduler()
	responseBody.Data = scheduler.GetTaskStats()
	return &responseBody
}

// GetSchedulerHealth 获取调度器健康状态
func GetSchedulerHealth() *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	scheduler := core.GetScheduler()
	responseBody.Data = map[string]interface{}{
		"healthy":   scheduler.Health(),
		"running":   scheduler.IsRunning(),
		"taskCount": len(scheduler.GetTaskStats()),
	}
	return &responseBody
}
