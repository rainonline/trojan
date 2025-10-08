# Docker 部署方案功能对比分析

## 📋 功能完整性对比

### 原有 CLI 命令（20 个）vs Docker 管理脚本

| 原有命令 | 功能描述 | Docker 方案 | 实现方式 | 状态 |
|---------|---------|------------|---------|------|
| **服务管理** |
| `trojan` | 交互式主菜单 | `./docker/manage.sh` | 管理脚本主入口 | ✅ 已实现 |
| `trojan start` | 启动 trojan | `./docker/manage.sh start` | docker-compose up -d | ✅ 已实现 |
| `trojan stop` | 停止 trojan | `./docker/manage.sh stop` | docker-compose down | ✅ 已实现 |
| `trojan restart` | 重启 trojan | `./docker/manage.sh restart` | docker-compose restart | ✅ 已实现 |
| `trojan status` | 查看状态 | `./docker/manage.sh status` | docker-compose ps + health check | ✅ 已实现 |
| **用户管理** |
| `trojan add` | 添加用户 | `./docker/manage.sh user add` | docker exec trojan add | ⚠️ 需增强 |
| `trojan del` | 删除用户 | `./docker/manage.sh user del` | docker exec trojan del | ⚠️ 需增强 |
| `trojan info` | 用户信息列表 | `./docker/manage.sh user list` | docker exec trojan info | ⚠️ 需增强 |
| `trojan clean` | 清空用户流量 | `./docker/manage.sh user clean` | docker exec trojan clean | ⚠️ 需增强 |
| **配置管理** |
| `trojan port` | 修改端口 | `./docker/manage.sh config port` | 修改 .env + 重启 | ⚠️ 需增强 |
| `trojan tls` | 证书安装 | `./docker/manage.sh tls install` | docker exec trojan tls | ⚠️ 需增强 |
| **数据管理** |
| `trojan export` | 导出 SQL | `./docker/manage.sh backup` | mysqldump | ✅ 已实现 |
| `trojan import` | 导入 SQL | `./docker/manage.sh restore` | mysql import | ✅ 已实现 |
| **更新管理** |
| `trojan update` | 更新 trojan | `./docker/manage.sh update` | 重新构建镜像 | ✅ 已实现 |
| `trojan updateWeb` | 更新 Web | `./docker/manage.sh update` | 包含在 update 中 | ✅ 已实现 |
| `trojan upgrade` | 升级配置/DB | `./docker/manage.sh upgrade` | docker exec 执行 | ⚠️ 需增强 |
| **日志管理** |
| `trojan log` | 查看日志 | `./docker/manage.sh logs` | docker-compose logs | ✅ 已实现 |
| **其他功能** |
| `trojan web` | 启动 Web 服务 | 自动启动（docker-compose） | 默认启用 | ✅ 已优化 |
| `trojan version` | 显示版本号 | `./docker/manage.sh version` | 读取环境变量 | ⚠️ 需增强 |
| `trojan completion` | 命令补全 | N/A | 管理脚本自带 | ✅ 无需实现 |

### 统计

- ✅ **已完整实现**: 9/20 (45%)
- ⚠️ **需要增强**: 11/20 (55%)
- ❌ **无法实现**: 0/20 (0%)

---

## 🔍 详细分析

### ✅ 已完整实现的功能

#### 1. 服务管理（5/5）
```bash
# 原有方式
trojan start / stop / restart / status

# Docker 方式
./docker/manage.sh start
./docker/manage.sh stop
./docker/manage.sh restart
./docker/manage.sh status
```

**优势**：
- Docker 方式更标准化
- 包含健康检查
- 支持滚动更新

#### 2. 数据备份恢复（2/2）
```bash
# 原有方式
trojan export /path/to/backup.sql
trojan import /path/to/backup.sql

# Docker 方式
./docker/manage.sh backup
./docker/manage.sh restore /path/to/backup.sql.gz
```

**优势**：
- 自动压缩备份（gzip）
- 按时间戳命名
- 支持定时备份（cron）

#### 3. 版本更新（2/2）
```bash
# 原有方式
trojan update v1.0.0
trojan updateWeb

# Docker 方式
./docker/manage.sh update v1.0.0
```

**优势**：
- 自动备份后更新
- 支持版本回滚
- 镜像版本控制

---

### ⚠️ 需要增强的功能（11 项）

#### 1. 用户管理（4 项）
**问题**：当前管理脚本缺少用户管理命令

**解决方案**：添加用户管理子命令
```bash
./docker/manage.sh user add <username> <password>
./docker/manage.sh user del <username>
./docker/manage.sh user list
./docker/manage.sh user clean <username>
```

**实现方式**：
```bash
# 方式 1: 通过 docker exec 调用原有命令
docker-compose exec trojan trojan add

# 方式 2: 直接调用 Web API
curl -X POST http://localhost:8080/trojan/user \
  -H "Authorization: Bearer $TOKEN" \
  -d "username=xxx&password=xxx"

# 方式 3: 直接操作数据库
docker-compose exec mariadb mysql -u trojan -p trojan \
  -e "INSERT INTO users ..."
```

#### 2. 配置管理（2 项）
**问题**：端口修改、TLS 证书管理未实现

**解决方案**：
```bash
# 端口修改
./docker/manage.sh config port <new-port>
# 实现：修改 .env 中的端口 → 重启服务

# TLS 证书
./docker/manage.sh tls install <domain>
./docker/manage.sh tls renew
# 实现：docker exec trojan trojan tls
```

#### 3. 升级功能（1 项）
```bash
./docker/manage.sh upgrade db      # 升级数据库
./docker/manage.sh upgrade config  # 升级配置文件
```

#### 4. 版本信息（1 项）
```bash
./docker/manage.sh version
# 显示：trojan 版本、镜像版本、构建日期等
```

#### 5. 交互式菜单（1 项）
**需求**：保留原有的交互式体验

**解决方案**：
```bash
./docker/manage.sh menu  # 进入交互式菜单
# 或直接 ./docker/manage.sh（无参数时）
```

---

## 🎯 增强方案

### 方案 1: 完全兼容模式（推荐⭐）

**目标**：100% 兼容原有 CLI 命令

**实现**：
1. 保留容器内的 `trojan` CLI 工具
2. `manage.sh` 作为 wrapper，转发所有命令到容器内
3. 用户体验完全一致

```bash
# 用户使用（完全兼容原有命令）
./docker/manage.sh add <username>        # 添加用户
./docker/manage.sh info                  # 查看用户
./docker/manage.sh port 8443             # 修改端口
./docker/manage.sh tls                   # 安装证书

# 内部实现
# ./docker/manage.sh add → docker-compose exec trojan trojan add
```

**优势**：
- ✅ 零学习成本
- ✅ 完全兼容现有文档
- ✅ 支持所有原有功能

**劣势**：
- ⚠️ 需要容器运行中

### 方案 2: 混合模式

**目标**：Docker 原生 + CLI 兼容

**实现**：
1. 核心服务管理用 docker-compose
2. 业务操作转发到容器内 CLI
3. 提供快捷命令

```bash
# Docker 原生操作
./docker/manage.sh start/stop/restart/logs/backup

# 转发到容器内
./docker/manage.sh exec add <username>
./docker/manage.sh exec info

# 快捷方式（可选）
./docker/manage.sh user:add <username>
./docker/manage.sh user:list
```

### 方案 3: 纯 Docker 模式

**目标**：完全 Docker 化，不依赖容器内 CLI

**实现**：
1. 所有操作通过 Web API 或直接操作数据库
2. 完全脱离原有 CLI
3. 更符合容器化理念

```bash
# 用户管理（通过 API）
./docker/manage.sh user add <username> <password>
# 内部: curl API

# 配置管理（通过环境变量 + 重启）
./docker/manage.sh config set TROJAN_PORT 8443
# 内部: 修改 .env → docker-compose restart
```

**优势**：
- ✅ 完全容器化
- ✅ 更易于自动化
- ✅ 适合云原生部署

**劣势**：
- ❌ 与原有命令不兼容
- ❌ 需要重新编写文档

---

## 💡 推荐实现：方案 1（完全兼容）

### 立即增强 manage.sh

添加以下功能，实现 100% 兼容：

```bash
# 1. 用户管理
user:add, user:del, user:list, user:clean

# 2. 配置管理
config:port, tls:install, tls:renew

# 3. 信息查询
version, info

# 4. 升级功能
upgrade:db, upgrade:config

# 5. 交互式菜单
menu (或无参数时默认进入)
```

### 实现优先级

#### P0 - 立即实现（核心功能）
- [ ] 用户管理（add/del/list/clean）
- [ ] 版本信息（version）
- [ ] 交互式菜单（menu）

#### P1 - 近期实现（常用功能）
- [ ] TLS 证书管理（tls）
- [ ] 端口修改（port）
- [ ] 数据库升级（upgrade db）

#### P2 - 后续优化（增强功能）
- [ ] Web API 直接调用（无需进入容器）
- [ ] 批量用户导入
- [ ] 监控告警集成

---

## 📝 向后兼容性

### 完全兼容
所有原有命令在 Docker 环境中都可以通过以下方式使用：

```bash
# 方式 1: 进入容器（完全兼容）
./docker/manage.sh shell
trojan add         # 原有命令
trojan info        # 原有命令

# 方式 2: 一行命令（推荐）
./docker/manage.sh exec add <username>
./docker/manage.sh exec info

# 方式 3: 快捷方式（增强后）
./docker/manage.sh user add <username>
./docker/manage.sh user list
```

### 迁移指南
从一键脚本迁移到 Docker 的用户：

| 原有命令 | Docker 等效命令 | 说明 |
|---------|----------------|------|
| `trojan add user1` | `./docker/manage.sh exec add user1` | 完全一致 |
| `trojan restart` | `./docker/manage.sh restart` | 更快速 |
| `trojan export db.sql` | `./docker/manage.sh backup` | 自动压缩 |
| `trojan update v1.1` | `./docker/manage.sh update v1.1` | 支持回滚 |

---

## 🚀 下一步行动

### 立即行动
1. **增强 manage.sh 脚本**
   - 添加用户管理命令
   - 添加版本信息命令
   - 添加交互式菜单

2. **更新文档**
   - 命令对照表
   - 迁移指南
   - 最佳实践

3. **测试验证**
   - 所有命令功能测试
   - 与原有方式对比
   - 性能基准测试

### 中期规划
1. **完善功能**
   - TLS 证书自动续期
   - 监控指标收集
   - 自动化运维脚本

2. **优化体验**
   - 命令自动补全
   - 错误提示优化
   - 日志美化输出

---

## 📊 总结

### 当前状态
- ✅ 核心服务管理功能完整（100%）
- ⚠️ 业务管理功能需增强（45% → 100%）
- ✅ Docker 化优势明显

### 推荐方案
采用**方案 1（完全兼容模式）**：
- 保留所有原有命令
- 通过 `manage.sh` 统一入口
- 零学习成本迁移

### 预期成果
增强后的 `manage.sh` 将提供：
- ✅ 20+ 原有命令完全兼容
- ✅ 10+ Docker 原生增强功能
- ✅ 交互式 + 命令行双模式
- ✅ 完整的文档和示例

---

**最后更新**: 2025-10-08  
**状态**: 待增强实现
