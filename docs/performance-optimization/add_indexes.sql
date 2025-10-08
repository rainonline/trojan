-- Trojan 性能优化 SQL 脚本
-- 用于现有数据库添加索引
-- 执行日期: 2025-10-08

-- 添加 username 索引（如果不存在）
ALTER TABLE users ADD INDEX IF NOT EXISTS idx_username (username);

-- 添加 expiryDate 索引（如果不存在）
ALTER TABLE users ADD INDEX IF NOT EXISTS idx_expiry (expiryDate);

-- 为 password 索引重命名（如果需要）
-- ALTER TABLE users DROP INDEX password;
-- ALTER TABLE users ADD INDEX idx_password (password);

-- 显示当前表的索引
SHOW INDEX FROM users;
