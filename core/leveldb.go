package core

import (
	"github.com/syndtr/goleveldb/leveldb"
	"github.com/syndtr/goleveldb/leveldb/opt"
)

var dbPath = "/var/lib/trojan-manager"

// GetValue 获取leveldb值
func GetValue(key string) (string, error) {
	db, err := leveldb.OpenFile(dbPath, nil)
	if err != nil {
		return "", err
	}
	defer db.Close()
	result, err := db.Get([]byte(key), nil)
	if err != nil {
		return "", err
	}
	return string(result), nil
}

// SetValue 设置leveldb值（强制同步到磁盘）
func SetValue(key string, value string) error {
	db, err := leveldb.OpenFile(dbPath, nil)
	if err != nil {
		return err
	}
	defer db.Close()
	
	// 使用 Sync 选项确保数据立即持久化到磁盘
	// 避免系统崩溃或重启时数据丢失（如管理员密码）
	wo := &opt.WriteOptions{Sync: true}
	return db.Put([]byte(key), []byte(value), wo)
}

// DelValue 删除值（强制同步到磁盘）
func DelValue(key string) error {
	db, err := leveldb.OpenFile(dbPath, nil)
	if err != nil {
		return err
	}
	defer db.Close()
	
	// 删除操作也应该同步，确保删除立即生效
	wo := &opt.WriteOptions{Sync: true}
	return db.Delete([]byte(key), wo)
}
