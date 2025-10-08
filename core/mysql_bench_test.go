package core

import (
	"testing"
	"time"
)

// BenchmarkGetDataWithoutCache 测试无缓存的GetData性能
func BenchmarkGetDataWithoutCache(b *testing.B) {
	// 清空缓存确保测试准确性
	userCache.Clear()
	
	mysql := &Mysql{
		Enabled:    true,
		ServerAddr: "localhost",
		ServerPort: 3306,
		Database:   "trojan",
		Username:   "root",
		Password:   "trojan",
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		mysql.GetData()
	}
}

// BenchmarkGetDataWithCache 测试有缓存的GetData性能
func BenchmarkGetDataWithCache(b *testing.B) {
	mysql := &Mysql{
		Enabled:    true,
		ServerAddr: "localhost",
		ServerPort: 3306,
		Database:   "trojan",
		Username:   "root",
		Password:   "trojan",
	}
	
	// 预热缓存
	mysql.GetData()
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		mysql.GetData()
	}
}

// BenchmarkDatabaseConnectionPool 测试连接池性能
func BenchmarkDatabaseConnectionPool(b *testing.B) {
	mysql := &Mysql{
		Enabled:    true,
		ServerAddr: "localhost",
		ServerPort: 3306,
		Database:   "trojan",
		Username:   "root",
		Password:   "trojan",
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		db := mysql.GetDB()
		if db == nil {
			b.Fatal("Failed to get database connection")
		}
		// 不关闭连接，测试连接池复用
	}
}

// BenchmarkCacheOperations 测试缓存操作性能
func BenchmarkCacheOperations(b *testing.B) {
	cache := newCache(5 * time.Minute)
	
	testData := &User{
		ID:       1,
		Username: "test",
		Password: "password",
	}
	
	b.Run("Set", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			cache.Set("test_key", testData)
		}
	})
	
	b.Run("Get", func(b *testing.B) {
		cache.Set("test_key", testData)
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cache.Get("test_key")
		}
	})
	
	b.Run("Delete", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			cache.Set("test_key", testData)
			cache.Delete("test_key")
		}
	})
}
