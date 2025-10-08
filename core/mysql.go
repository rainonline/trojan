package core

import (
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	mysqlDriver "github.com/go-sql-driver/mysql"
	"io"
	"log"
	"sync"
	"time"

	"strconv"
	"strings"

	// mysql sql驱动
	_ "github.com/go-sql-driver/mysql"
)

// cacheEntry 缓存条目
type cacheEntry struct {
	data      interface{}
	expiresAt time.Time
}

// simpleCache 简单的内存缓存
type simpleCache struct {
	items sync.Map
	ttl   time.Duration
}

// newCache 创建新的缓存实例
func newCache(ttl time.Duration) *simpleCache {
	cache := &simpleCache{
		ttl: ttl,
	}
	// 启动清理协程
	go cache.cleanup()
	return cache
}

// Set 设置缓存
func (c *simpleCache) Set(key string, value interface{}) {
	c.items.Store(key, &cacheEntry{
		data:      value,
		expiresAt: time.Now().Add(c.ttl),
	})
}

// Get 获取缓存
func (c *simpleCache) Get(key string) (interface{}, bool) {
	val, ok := c.items.Load(key)
	if !ok {
		return nil, false
	}
	
	entry := val.(*cacheEntry)
	if time.Now().After(entry.expiresAt) {
		c.items.Delete(key)
		return nil, false
	}
	
	return entry.data, true
}

// Delete 删除缓存
func (c *simpleCache) Delete(key string) {
	c.items.Delete(key)
}

// Clear 清空所有缓存
func (c *simpleCache) Clear() {
	c.items.Range(func(key, value interface{}) bool {
		c.items.Delete(key)
		return true
	})
}

// cleanup 定期清理过期缓存
func (c *simpleCache) cleanup() {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()
	
	for range ticker.C {
		now := time.Now()
		c.items.Range(func(key, value interface{}) bool {
			entry := value.(*cacheEntry)
			if now.After(entry.expiresAt) {
				c.items.Delete(key)
			}
			return true
		})
	}
}

// 全局缓存实例
var (
	userCache   = newCache(5 * time.Minute) // 用户信息缓存5分钟
	configCache = newCache(10 * time.Minute) // 配置缓存10分钟
)


// Mysql 结构体
type Mysql struct {
	Enabled    bool   `json:"enabled"`
	ServerAddr string `json:"server_addr"`
	ServerPort int    `json:"server_port"`
	Database   string `json:"database"`
	Username   string `json:"username"`
	Password   string `json:"password"`
	Cafile     string `json:"cafile"`
	db         *sql.DB // 数据库连接池（私有字段）
}

// User 用户表记录结构体
type User struct {
	ID          uint
	Username    string
	Password    string
	EncryptPass string
	Quota       int64
	Download    uint64
	Upload      uint64
	UseDays     uint
	ExpiryDate  string
}

// PageQuery 分页查询的结构体
type PageQuery struct {
	PageNum  int
	CurPage  int
	Total    int
	PageSize int
	DataList []*User
}

// CreateTableSql 创表sql
var CreateTableSql = `
CREATE TABLE IF NOT EXISTS users (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    password CHAR(56) NOT NULL,
    passwordShow VARCHAR(255) NOT NULL,
    quota BIGINT NOT NULL DEFAULT 0,
    download BIGINT UNSIGNED NOT NULL DEFAULT 0,
    upload BIGINT UNSIGNED NOT NULL DEFAULT 0,
    useDays int(10) DEFAULT 0,
    expiryDate char(10) DEFAULT '',
    PRIMARY KEY (id),
    INDEX idx_password (password),
    INDEX idx_username (username),
    INDEX idx_expiry (expiryDate)
) DEFAULT CHARSET=utf8mb4;
`

// GetDB 获取mysql数据库连接
// 使用单例模式，复用连接池
func (mysql *Mysql) GetDB() *sql.DB {
	// 如果连接池已存在且可用，直接返回
	if mysql.db != nil {
		if err := mysql.db.Ping(); err == nil {
			return mysql.db
		}
		// 连接失效，关闭旧连接
		mysql.db.Close()
	}

	// 屏蔽mysql驱动包的日志输出
	mysqlDriver.SetLogger(log.New(io.Discard, "", 0))
	conn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s", mysql.Username, mysql.Password, mysql.ServerAddr, mysql.ServerPort, mysql.Database)
	db, err := sql.Open("mysql", conn)
	if err != nil {
		fmt.Println(err.Error())
		return nil
	}

	// 配置连接池参数
	db.SetMaxOpenConns(25)               // 最大打开连接数
	db.SetMaxIdleConns(10)               // 最大空闲连接数
	db.SetConnMaxLifetime(5 * time.Minute) // 连接最大生命周期
	db.SetConnMaxIdleTime(3 * time.Minute) // 空闲连接最大生命周期

	// 测试连接
	if err := db.Ping(); err != nil {
		fmt.Println("数据库连接失败:", err.Error())
		db.Close()
		return nil
	}

	mysql.db = db
	return db
}

// CreateTable 不存在trojan user表则自动创建
func (mysql *Mysql) CreateTable() {
	db := mysql.GetDB()
	if _, err := db.Exec(CreateTableSql); err != nil {
		fmt.Println(err)
	}
}

func queryUserList(db *sql.DB, query string, args ...interface{}) ([]*User, error) {
	var (
		username    string
		encryptPass string
		passShow    string
		download    uint64
		upload      uint64
		quota       int64
		id          uint
		useDays     uint
		expiryDate  string
	)
	var userList []*User
	rows, err := db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		if err := rows.Scan(&id, &username, &encryptPass, &passShow, &quota, &download, &upload, &useDays, &expiryDate); err != nil {
			return nil, err
		}
		userList = append(userList, &User{
			ID:          id,
			Username:    username,
			Password:    passShow,
			EncryptPass: encryptPass,
			Download:    download,
			Upload:      upload,
			Quota:       quota,
			UseDays:     useDays,
			ExpiryDate:  expiryDate,
		})
	}
	return userList, nil
}

func queryUser(db *sql.DB, query string, args ...interface{}) (*User, error) {
	var (
		username    string
		encryptPass string
		passShow    string
		download    uint64
		upload      uint64
		quota       int64
		id          uint
		useDays     uint
		expiryDate  string
	)
	row := db.QueryRow(query, args...)
	if err := row.Scan(&id, &username, &encryptPass, &passShow, &quota, &download, &upload, &useDays, &expiryDate); err != nil {
		return nil, err
	}
	return &User{ID: id, Username: username, Password: passShow, EncryptPass: encryptPass, Download: download, Upload: upload, Quota: quota, UseDays: useDays, ExpiryDate: expiryDate}, nil
}

// CreateUser 创建Trojan用户
func (mysql *Mysql) CreateUser(username string, base64Pass string, originPass string) error {
	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	encryPass := sha256.Sum224([]byte(originPass))
	if _, err := db.Exec("INSERT INTO users(username, password, passwordShow, quota) VALUES (?, ?, ?, -1)", username, fmt.Sprintf("%x", encryPass), base64Pass); err != nil {
		fmt.Println(err)
		return err
	}
	// 清除缓存
	userCache.Clear()
	return nil
}

// UpdateUser 更新Trojan用户名和密码
func (mysql *Mysql) UpdateUser(id uint, username string, base64Pass string, originPass string) error {
	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	encryPass := sha256.Sum224([]byte(originPass))
	if _, err := db.Exec("UPDATE users SET username=?, password=?, passwordShow=? WHERE id=?", username, fmt.Sprintf("%x", encryPass), base64Pass, id); err != nil {
		fmt.Println(err)
		return err
	}
	// 清除缓存
	userCache.Clear()
	return nil
}

// DeleteUser 删除用户
func (mysql *Mysql) DeleteUser(id uint) error {
	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	if userList, err := mysql.GetData(strconv.Itoa(int(id))); err != nil {
		return err
	} else if userList != nil && len(userList) == 0 {
		return fmt.Errorf("不存在id为%d的用户", id)
	}
	if _, err := db.Exec("DELETE FROM users WHERE id=?", id); err != nil {
		fmt.Println(err)
		return err
	}
	// 清除缓存
	userCache.Clear()
	return nil
}

// MonthlyResetData 设置了过期时间的用户，每月定时清空使用流量
func (mysql *Mysql) MonthlyResetData() error {
	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	userList, err := queryUserList(db, "SELECT * FROM users WHERE useDays != 0 AND quota != 0")
	if err != nil {
		return err
	}
	
	// 批量更新优化：收集所有ID然后一次性更新
	if len(userList) > 0 {
		ids := make([]string, 0, len(userList))
		for _, user := range userList {
			ids = append(ids, strconv.Itoa(int(user.ID)))
		}
		// 使用 IN 子句批量更新
		sql := fmt.Sprintf("UPDATE users SET download=0, upload=0 WHERE id IN (%s)", strings.Join(ids, ","))
		if _, err := db.Exec(sql); err != nil {
			return err
		}
	}
	// 清除缓存
	userCache.Clear()
	return nil
}

// DailyCheckExpire 检查是否有过期，过期了设置流量上限为0
func (mysql *Mysql) DailyCheckExpire() (bool, error) {
	needRestart := false
	now := time.Now()
	utc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return false, err
	}
	addDay, _ := time.ParseDuration("-24h")
	yesterdayStr := now.Add(addDay).In(utc).Format("2006-01-02")
	yesterday, _ := time.Parse("2006-01-02", yesterdayStr)
	db := mysql.GetDB()
	if db == nil {
		return false, errors.New("can't connect mysql")
	}
	userList, err := queryUserList(db, "SELECT * FROM users WHERE quota != 0")
	if err != nil {
		return false, err
	}
	
	// 批量更新优化：收集过期用户ID
	expiredIDs := make([]string, 0)
	for _, user := range userList {
		if expireDate, err := time.Parse("2006-01-02", user.ExpiryDate); err == nil {
			if yesterday.Sub(expireDate).Seconds() >= 0 {
				expiredIDs = append(expiredIDs, strconv.Itoa(int(user.ID)))
				if !needRestart {
					needRestart = true
				}
			}
		}
	}
	
	// 批量更新过期用户
	if len(expiredIDs) > 0 {
		sql := fmt.Sprintf("UPDATE users SET quota=0 WHERE id IN (%s)", strings.Join(expiredIDs, ","))
		if _, err := db.Exec(sql); err != nil {
			return false, err
		}
		// 清除缓存
		userCache.Clear()
	}
	
	return needRestart, nil
}

// CancelExpire 取消过期时间
func (mysql *Mysql) CancelExpire(id uint) error {
	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	if _, err := db.Exec("UPDATE users SET useDays=0, expiryDate='' WHERE id=?", id); err != nil {
		fmt.Println(err)
		return err
	}
	return nil
}

// SetExpire 设置过期时间
func (mysql *Mysql) SetExpire(id uint, useDays uint) error {
	now := time.Now()
	utc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		fmt.Println(err)
		return err
	}
	addDay, _ := time.ParseDuration(strconv.Itoa(int(24*useDays)) + "h")
	expiryDate := now.Add(addDay).In(utc).Format("2006-01-02")

	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	if _, err := db.Exec("UPDATE users SET useDays=?, expiryDate=? WHERE id=?", useDays, expiryDate, id); err != nil {
		fmt.Println(err)
		return err
	}
	return nil
}

// SetQuota 限制流量
func (mysql *Mysql) SetQuota(id uint, quota int) error {
	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	if _, err := db.Exec("UPDATE users SET quota=? WHERE id=?", quota, id); err != nil {
		fmt.Println(err)
		return err
	}
	// 清除缓存
	userCache.Clear()
	return nil
}

// CleanData 清空流量统计
func (mysql *Mysql) CleanData(id uint) error {
	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	if _, err := db.Exec("UPDATE users SET download=0, upload=0 WHERE id=?", id); err != nil {
		fmt.Println(err)
		return err
	}
	// 清除缓存
	userCache.Clear()
	return nil
}

// CleanDataByName 清空指定用户名流量统计数据
func (mysql *Mysql) CleanDataByName(usernames []string) error {
	db := mysql.GetDB()
	if db == nil {
		return errors.New("can't connect mysql")
	}
	runSql := "UPDATE users SET download=0, upload=0 WHERE BINARY username in ("
	for i, name := range usernames {
		runSql = runSql + "'" + name + "'"
		if i == len(usernames)-1 {
			runSql = runSql + ")"
		} else {
			runSql = runSql + ","
		}
	}
	if _, err := db.Exec(runSql); err != nil {
		fmt.Println(err)
		return err
	}
	return nil
}

// GetUserByName 通过用户名来获取用户
func (mysql *Mysql) GetUserByName(name string) *User {
	db := mysql.GetDB()
	if db == nil {
		return nil
	}
	user, err := queryUser(db, "SELECT * FROM users WHERE BINARY username=?", name)
	if err != nil {
		return nil
	}
	return user
}

// GetUserByPass 通过密码来获取用户
func (mysql *Mysql) GetUserByPass(pass string) *User {
	db := mysql.GetDB()
	if db == nil {
		return nil
	}
	user, err := queryUser(db, "SELECT * FROM users WHERE BINARY passwordShow=?", pass)
	if err != nil {
		return nil
	}
	return user
}

// PageList 通过分页获取用户记录
func (mysql *Mysql) PageList(curPage int, pageSize int) (*PageQuery, error) {
	var (
		total int
	)

	db := mysql.GetDB()
	if db == nil {
		return nil, errors.New("连接mysql失败")
	}
	offset := (curPage - 1) * pageSize
	querySQL := "SELECT * FROM users LIMIT ?, ?"
	userList, err := queryUserList(db, querySQL, offset, pageSize)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}
	db.QueryRow("SELECT COUNT(id) FROM users").Scan(&total)
	return &PageQuery{
		CurPage:  curPage,
		PageSize: pageSize,
		Total:    total,
		DataList: userList,
		PageNum:  (total + pageSize - 1) / pageSize,
	}, nil
}

// GetData 获取用户记录（带缓存）
func (mysql *Mysql) GetData(ids ...string) ([]*User, error) {
	// 如果查询所有用户，尝试从缓存获取
	cacheKey := "all_users"
	if len(ids) == 0 {
		if cached, ok := userCache.Get(cacheKey); ok {
			return cached.([]*User), nil
		}
	}

	querySQL := "SELECT * FROM users"
	db := mysql.GetDB()
	if db == nil {
		return nil, errors.New("连接mysql失败")
	}
	if len(ids) > 0 {
		querySQL = querySQL + " WHERE id in (" + strings.Join(ids, ",") + ")"
	}
	userList, err := queryUserList(db, querySQL)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}

	// 缓存结果（仅缓存全量查询）
	if len(ids) == 0 {
		userCache.Set(cacheKey, userList)
	}

	return userList, nil
}

// Close 关闭数据库连接池
func (mysql *Mysql) Close() error {
	if mysql.db != nil {
		err := mysql.db.Close()
		mysql.db = nil
		return err
	}
	return nil
}
