package controller

import (
	"fmt"
	"strconv"
	"trojan/core"
	"trojan/trojan"
)

// SetData 设置流量限制
func SetData(id uint, quota int) *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	mysql := core.GetMysql()
	if err := mysql.SetQuota(id, quota); err != nil {
		responseBody.Msg = err.Error()
	}
	return &responseBody
}

// CleanData 清空流量
func CleanData(id uint) *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	mysql := core.GetMysql()
	if err := mysql.CleanData(id); err != nil {
		responseBody.Msg = err.Error()
	}
	return &responseBody
}

// GetResetDay 获取重置日
func GetResetDay() *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	dayStr, _ := core.GetValue("reset_day")
	day, _ := strconv.Atoi(dayStr)
	responseBody.Data = map[string]interface{}{
		"resetDay": day,
	}
	return &responseBody
}

// UpdateResetDay 更新重置流量日
func UpdateResetDay(day uint) *ResponseBody {
	responseBody := ResponseBody{Msg: "success"}
	defer TimeCost(time.Now(), &responseBody)
	if day > 31 || day < 0 {
		responseBody.Msg = fmt.Sprintf("%d为非正常日期", day)
		return &responseBody
	}
	dayStr, _ := core.GetValue("reset_day")
	oldDay, _ := strconv.Atoi(dayStr)
	if day == uint(oldDay) {
		return &responseBody
	}
	
	// 使用统一的调度器
	scheduler := core.GetScheduler()
	
	// 移除旧的月度重置任务
	scheduler.RemoveTask("monthly_reset")
	
	// 如果设置了重置日，添加新任务
	if day != 0 {
		spec := fmt.Sprintf("0 0 %d * *", day)
		scheduler.AddTask("monthly_reset", spec, func() error {
			mysql := core.GetMysql()
			return mysql.MonthlyResetData()
		})
	}
	
	core.SetValue("reset_day", strconv.Itoa(int(day)))
	return &responseBody
}

// ScheduleTask 定时任务
func ScheduleTask() {
	scheduler := core.GetScheduler()
	
	// 每日过期检查任务
	scheduler.AddTask("daily_expire_check", "@daily", func() error {
		mysql := core.GetMysql()
		needRestart, err := mysql.DailyCheckExpire()
		if err != nil {
			return fmt.Errorf("daily expire check failed: %w", err)
		}
		if needRestart {
			trojan.Restart()
		}
		return nil
	})

	// 月度流量重置任务
	dayStr, _ := core.GetValue("reset_day")
	if dayStr == "" {
		dayStr = "1"
		core.SetValue("reset_day", dayStr)
	}
	day, _ := strconv.Atoi(dayStr)
	if day != 0 {
		spec := fmt.Sprintf("0 0 %d * *", day)
		scheduler.AddTask("monthly_reset", spec, func() error {
			mysql := core.GetMysql()
			return mysql.MonthlyResetData()
		})
	}
	
	scheduler.Start()
}
