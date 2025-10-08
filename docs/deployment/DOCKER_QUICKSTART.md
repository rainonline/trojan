# Docker 快速开始指南

## 🚀 快速部署（3 分钟）

### 前置要求
- Docker 20.10+
- Docker Compose 2.0+
- 一个可用的域名（用于 TLS 证书）

### 步骤 1: 克隆代码
```bash
git clone https://github.com/Jrohy/trojan.git
cd trojan
```

### 步骤 2: 配置环境变量
```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置（必须修改！）
vim .env
```

**必须修改的配置**：
```bash
# 数据库密码（至少 16 个字符）
MYSQL_ROOT_PASSWORD=your_secure_root_password_here
MYSQL_PASSWORD=your_secure_trojan_password_here

# 你的域名
TROJAN_DOMAIN=your.domain.com

# JWT 密钥（至少 32 个字符）
JWT_SECRET=your_jwt_secret_minimum_32_characters_long
```

### 步骤 3: 启动服务
```bash
./docker/manage.sh start
```

### 步骤 4: 访问管理界面
打开浏览器访问：
- Web 管理界面: `http://your.domain.com:8080`
- Trojan 服务: `your.domain.com:443`

默认管理员账号（首次启动后请立即修改）：
- 用户名: `admin`
- 密码: 查看日志获取初始密码

---

## 📋 常用命令

### 服务管理
```bash
# 启动服务
./docker/manage.sh start

# 停止服务
./docker/manage.sh stop

# 重启服务
./docker/manage.sh restart

# 查看状态
./docker/manage.sh status

# 查看日志
./docker/manage.sh logs          # 所有日志
./docker/manage.sh logs trojan   # Trojan 日志
./docker/manage.sh logs mariadb  # 数据库日志
```

### 数据备份与恢复
```bash
# 备份数据库
./docker/manage.sh backup

# 恢复数据库
./docker/manage.sh restore backup/trojan_20251008_120000.sql.gz
```

### 版本管理
```bash
# 更新到新版本
./docker/manage.sh update v1.0.1

# 回滚到旧版本
./docker/manage.sh rollback v1.0.0

# 构建镜像
./docker/manage.sh build
```

### 进入容器
```bash
# 进入 Trojan 容器
./docker/manage.sh shell

# 进入数据库容器
docker-compose exec mariadb bash
```

---

## 🔧 高级配置

### 启用 Redis 缓存（可选）
适用于高并发场景（>1000 用户）

1. 编辑 `.env` 文件：
```bash
COMPOSE_PROFILES=with-redis
```

2. 重启服务：
```bash
./docker/manage.sh restart
```

### 自定义端口
编辑 `docker-compose.yml`:
```yaml
ports:
  - "8443:443"    # 修改 Trojan 端口
  - "9090:8080"   # 修改 Web 管理端口
```

### 配置 TLS 证书
```bash
# 进入容器
./docker/manage.sh shell

# 申请证书
trojan tls
```

---

## 🔍 故障排查

### 1. 服务无法启动
```bash
# 查看详细日志
./docker/manage.sh logs

# 检查端口占用
netstat -tlnp | grep -E '443|8080|3306'

# 检查容器状态
docker-compose ps
```

### 2. 数据库连接失败
```bash
# 检查数据库健康状态
docker-compose exec mariadb healthcheck.sh --connect

# 手动连接测试
docker-compose exec mariadb mysql -u trojan -p
```

### 3. 健康检查失败
```bash
# 测试健康检查端点
curl http://localhost:8080/health

# 应该返回：
# {"status":"healthy","version":"v1.0.0","buildDate":"...","timestamp":...}
```

### 4. 无法访问 Web 界面
```bash
# 检查防火墙
sudo ufw status
sudo ufw allow 8080/tcp

# 或使用 iptables
sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
```

---

## 📊 监控与维护

### 查看资源使用
```bash
# Docker 资源统计
docker stats trojan-app trojan-mariadb

# 容器日志大小
docker-compose logs trojan | wc -l
```

### 定期备份
建议使用 cron 定时备份：
```bash
# 编辑 crontab
crontab -e

# 添加每日凌晨 3 点备份
0 3 * * * cd /path/to/trojan && ./docker/manage.sh backup
```

### 清理旧数据
```bash
# 清理 Docker 缓存
docker system prune -a

# 清理旧备份（保留最近 7 天）
find backup/ -name "*.sql.gz" -mtime +7 -delete
```

---

## 🔄 从旧版本迁移

### 从一键脚本迁移到 Docker

**步骤 1: 备份数据**
```bash
# 备份配置
cp /usr/local/etc/trojan/config.json ~/config.json.bak

# 备份数据库
mysqldump -u root -p trojan > ~/trojan_backup.sql
```

**步骤 2: 停止旧服务**
```bash
systemctl stop trojan trojan-web
systemctl disable trojan trojan-web
```

**步骤 3: 部署 Docker 版本**
```bash
git clone https://github.com/Jrohy/trojan.git
cd trojan
cp .env.example .env
vim .env  # 配置环境变量
./docker/manage.sh start
```

**步骤 4: 恢复数据**
```bash
./docker/manage.sh restore ~/trojan_backup.sql
```

### 从旧 Docker 版本迁移

**步骤 1: 备份数据**
```bash
docker exec trojan-mariadb mysqldump -u root -p trojan > backup.sql
```

**步骤 2: 停止并删除旧容器**
```bash
docker stop trojan trojan-mariadb
docker rm trojan trojan-mariadb
```

**步骤 3: 使用新 docker-compose 部署**
```bash
cd /path/to/trojan
cp .env.example .env
vim .env
./docker/manage.sh start
./docker/manage.sh restore backup.sql
```

---

## 🆘 获取帮助

### 常见问题
查看 [FAQ 文档](../deployment/DOCKER_DEPLOYMENT.md#常见问题)

### 查看完整文档
```bash
# 管理脚本帮助
./docker/manage.sh

# 详细部署文档
cat docs/deployment/DOCKER_DEPLOYMENT.md
```

### 提交问题
遇到问题请访问：https://github.com/Jrohy/trojan/issues

---

## 📈 性能优化建议

### 小规模部署（<100 用户）
- 使用默认配置即可
- 无需启用 Redis

### 中等规模（100-1000 用户）
- 启用 sync.Map 缓存（已默认启用）
- 考虑增加数据库连接池

### 大规模部署（>1000 用户）
- 启用 Redis 缓存
- 配置数据库读写分离
- 使用 Kubernetes 部署

---

**最后更新**: 2025-10-08
