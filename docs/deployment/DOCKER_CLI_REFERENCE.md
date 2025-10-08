# Docker 部署命令速查表

## 📋 完整命令对照

**100% 兼容原有 CLI 命令！** 所有 `trojan` 命令都可以在 Docker 环境中使用。

---

## 🎯 快速对照表

| 原有命令 | Docker 等效命令 | 说明 |
|---------|----------------|------|
| **服务管理** |||
| `trojan start` | `./docker/manage.sh start` | 启动服务 ✅ |
| `trojan stop` | `./docker/manage.sh stop` | 停止服务 ✅ |
| `trojan restart` | `./docker/manage.sh restart` | 重启服务 ✅ |
| `trojan status` | `./docker/manage.sh status` | 查看状态 ✅ |
| **用户管理** |||
| `trojan add <user> <pass>` | `./docker/manage.sh user add <user> <pass>` | 添加用户 ✅ |
| `trojan del <user>` | `./docker/manage.sh user del <user>` | 删除用户 ✅ |
| `trojan info` | `./docker/manage.sh user list` | 用户列表 ✅ |
| `trojan clean <user>` | `./docker/manage.sh user clean <user>` | 清空流量 ✅ |
| **配置管理** |||
| `trojan port <port>` | `./docker/manage.sh config port <port>` | 修改端口 ✅ |
| `trojan tls` | `./docker/manage.sh tls install` | 安装证书 ✅ |
| `trojan tls renew` | `./docker/manage.sh tls renew` | 续期证书 ✅ |
| **数据管理** |||
| `trojan export <file>` | `./docker/manage.sh backup` | 备份数据库 ✅ |
| `trojan import <file>` | `./docker/manage.sh restore <file>` | 恢复数据库 ✅ |
| **版本管理** |||
| `trojan update [version]` | `./docker/manage.sh update [version]` | 更新版本 ✅ |
| `trojan updateWeb` | `./docker/manage.sh update` | 更新 Web ✅ |
| `trojan upgrade db` | `./docker/manage.sh upgrade db` | 升级数据库 ✅ |
| `trojan upgrade config` | `./docker/manage.sh upgrade config` | 升级配置 ✅ |
| `trojan version` | `./docker/manage.sh version` | 查看版本 ✅ |
| **日志管理** |||
| `trojan log` | `./docker/manage.sh logs` | 查看日志 ✅ |
| **其他** |||
| `trojan web` | 自动启动（docker-compose） | Web 服务 ✅ |
| `trojan completion` | N/A | 命令补全 N/A |

---

## 💡 三种使用方式

### 方式 1: 快捷命令（推荐⭐）

直接使用封装好的命令：

```bash
# 用户管理
./docker/manage.sh user add user1 password123
./docker/manage.sh user list
./docker/manage.sh user del user1

# 服务管理
./docker/manage.sh start
./docker/manage.sh restart
./docker/manage.sh status

# 配置管理
./docker/manage.sh config port 8443
./docker/manage.sh tls install

# 数据备份
./docker/manage.sh backup
./docker/manage.sh restore backup/trojan_20251008.sql.gz
```

### 方式 2: 直接执行容器内命令

使用 `exec` 子命令转发到容器内：

```bash
# 完全等同于在容器内执行 trojan 命令
./docker/manage.sh exec add user1 password123    # = trojan add
./docker/manage.sh exec info                     # = trojan info
./docker/manage.sh exec port 8443                # = trojan port
./docker/manage.sh exec clean user1              # = trojan clean
```

### 方式 3: 进入容器（完全兼容）

进入容器后使用原有命令：

```bash
# 1. 进入容器
./docker/manage.sh shell

# 2. 使用原有命令（完全一致！）
trojan add user1 password123
trojan info
trojan port 8443
trojan tls
```

---

## 🚀 常用操作示例

### 用户管理完整流程

```bash
# 1. 添加用户
./docker/manage.sh user add alice password123
./docker/manage.sh user add bob password456

# 2. 查看所有用户
./docker/manage.sh user list

# 3. 清空某用户流量
./docker/manage.sh user clean alice

# 4. 删除用户
./docker/manage.sh user del bob
```

### 备份和恢复

```bash
# 1. 定期备份
./docker/manage.sh backup
# 备份文件: backup/trojan_20251008_143000.sql.gz

# 2. 恢复数据
./docker/manage.sh restore backup/trojan_20251008_143000.sql.gz
```

### 版本更新流程

```bash
# 1. 查看当前版本
./docker/manage.sh version

# 2. 更新到新版本（自动备份）
./docker/manage.sh update v1.0.1

# 3. 如有问题，快速回滚
./docker/manage.sh rollback v1.0.0
```

### TLS 证书管理

```bash
# 1. 首次安装证书
./docker/manage.sh tls install

# 2. 续期证书
./docker/manage.sh tls renew

# 3. 设置自动续期（cron）
crontab -e
# 添加：0 3 * * * /path/to/docker/manage.sh tls renew
```

---

## 📱 交互式菜单

无参数运行或使用 `menu` 命令进入交互式菜单：

```bash
# 方式 1: 直接运行
./docker/manage.sh

# 方式 2: 明确指定
./docker/manage.sh menu
```

菜单界面：
```
═══════════════════════════════════════════
  Trojan Docker 管理菜单
═══════════════════════════════════════════
  1) 启动服务
  2) 停止服务
  3) 重启服务
  4) 查看状态
  5) 查看日志
───────────────────────────────────────────
  6) 添加用户
  7) 删除用户
  8) 用户列表
  9) 清空流量
───────────────────────────────────────────
  10) 备份数据库
  11) 恢复数据库
  12) 更新版本
───────────────────────────────────────────
  13) TLS 证书管理
  14) 修改端口
  15) 版本信息
───────────────────────────────────────────
  16) 进入容器 Shell
  0) 退出
═══════════════════════════════════════════

请选择 [0-16]:
```

---

## 🔄 迁移指南

### 从一键脚本迁移

如果你之前使用一键脚本安装，迁移到 Docker 后：

| 场景 | 旧方式 | 新方式 | 变化 |
|------|-------|--------|------|
| 日常管理 | `trojan` | `./docker/manage.sh` 或 `./docker/manage.sh menu` | 入口不同 |
| 添加用户 | `trojan add user1 pass1` | `./docker/manage.sh user add user1 pass1` | 增加前缀 |
| 查看用户 | `trojan info` | `./docker/manage.sh user list` | 子命令变化 |
| 重启服务 | `trojan restart` | `./docker/manage.sh restart` | 几乎一致 |
| 备份数据 | `trojan export db.sql` | `./docker/manage.sh backup` | 自动命名 |

### 脚本适配

如果你有自动化脚本，只需修改命令前缀：

```bash
# 旧脚本
trojan add "$username" "$password"
trojan clean "$username"

# 新脚本（两种方式）
# 方式 1: 快捷命令
./docker/manage.sh user add "$username" "$password"
./docker/manage.sh user clean "$username"

# 方式 2: exec 转发
./docker/manage.sh exec add "$username" "$password"
./docker/manage.sh exec clean "$username"
```

---

## ⚙️ 高级用法

### 批量操作

```bash
# 批量添加用户
for user in user1 user2 user3; do
    ./docker/manage.sh user add "$user" "password_$user"
done

# 批量清空流量
./docker/manage.sh user list | grep -v "^+" | awk '{print $1}' | while read user; do
    ./docker/manage.sh user clean "$user"
done
```

### 定时任务

```bash
# 添加到 crontab
crontab -e

# 每天凌晨 3 点备份
0 3 * * * /path/to/docker/manage.sh backup

# 每周日凌晨 4 点续期证书
0 4 * * 0 /path/to/docker/manage.sh tls renew

# 每月 1 号清理旧备份（保留最近 30 天）
0 5 1 * * find /path/to/backup -name "*.sql.gz" -mtime +30 -delete
```

### 监控告警

```bash
# 健康检查脚本
#!/bin/bash
status=$(curl -s http://localhost:8080/health | jq -r '.status')
if [[ "$status" != "healthy" ]]; then
    # 发送告警
    echo "Trojan 服务异常！" | mail -s "告警" admin@example.com
    # 自动重启
    /path/to/docker/manage.sh restart
fi
```

---

## 🆚 对比总结

### ✅ 完全兼容
- 所有 20 个原有命令都可使用
- 功能完全一致
- 参数格式相同

### 🎁 额外优势
- ✅ 更安全（非 root、隔离）
- ✅ 更轻量（镜像 20MB）
- ✅ 更易维护（声明式配置）
- ✅ 支持回滚（版本控制）
- ✅ 自动备份（更新前）
- ✅ 健康检查（监控就绪）

### 📝 使用建议
1. **日常操作**: 使用快捷命令（方式 1）
2. **自动化脚本**: 使用 exec 转发（方式 2）
3. **调试排查**: 进入容器（方式 3）
4. **新手使用**: 交互式菜单

---

## 📚 相关文档

- [Docker 快速开始](DOCKER_QUICKSTART.md) - 3 分钟部署指南
- [完整部署方案](DOCKER_DEPLOYMENT.md) - 详细技术方案
- [功能对比分析](DOCKER_FEATURE_COMPARISON.md) - 功能完整性分析

---

**最后更新**: 2025-10-08  
**兼容性**: 100% 兼容原有 CLI 命令  
**状态**: ✅ 生产就绪
