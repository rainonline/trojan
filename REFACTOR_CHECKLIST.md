# Trojan 翻新计划 - 快速执行清单

## 🎯 Phase 1: 安全修复 (Week 1-2) - 🔴 紧急

### Week 1: SQL注入修复
- [ ] **Day 1-2**: 修复 `core/mysql.go` 中的SQL注入
  ```bash
  # 修改文件
  - CreateUser() - 使用 db.Exec("INSERT ... VALUES (?, ?)", ...)
  - UpdateUser() - 使用参数化查询
  - AddUser() - 使用参数化查询
  - DelUser() - 使用参数化查询
  - GetUserByName() - 使用参数化查询
  ```
  
- [ ] **Day 3**: 修复 `web/controller/trojan.go` ImportCsv()
  ```bash
  # 替换所有 fmt.Sprintf 拼接SQL为参数化查询
  ```

- [ ] **Day 4**: 修复 `core/tools.go` DumpSql()
  ```bash
  # 使用参数化查询生成SQL
  ```

- [ ] **Day 5**: SQL注入修复测试
  ```bash
  # 编写SQL注入攻击测试用例
  go test -v ./core -run TestSQL
  ```

### Week 2: 依赖更新与JWT加固
- [ ] **Day 1**: 依赖更新
  ```bash
  # 更新 go.mod
  go get -u github.com/gin-gonic/gin@v1.11.0
  go get -u golang.org/x/crypto@latest
  go mod tidy
  
  # 安全扫描
  go install golang.org/x/vuln/cmd/govulncheck@latest
  govulncheck ./...
  ```

- [ ] **Day 2-3**: JWT增强 `web/auth.go`
  ```go
  - [ ] 添加密钥轮换机制
  - [ ] 实现刷新令牌
  - [ ] 添加令牌黑名单 (LevelDB/Redis)
  ```

- [ ] **Day 4-5**: HTTPS与CORS配置
  ```go
  - [ ] 强制HTTPS中间件
  - [ ] CORS配置 (gin-contrib/cors)
  - [ ] 安全头部设置
  ```

---

## 🧪 Phase 2: 测试与质量 (Week 3-6)

### Week 3: 错误处理标准化
- [ ] **Day 1**: 添加日志库
  ```bash
  go get -u go.uber.org/zap
  
  # 创建 internal/logger/logger.go
  # 初始化全局logger
  ```

- [ ] **Day 2-5**: 替换所有 fmt.Println
  ```bash
  # 优先顺序：
  1. core/*.go
  2. trojan/*.go  
  3. web/controller/*.go
  4. util/*.go
  
  # 替换模式：
  fmt.Println(err) → logger.Error("operation failed", zap.Error(err))
  ```

### Week 4-5: 单元测试 (目标50%覆盖率)
- [ ] **测试框架搭建**
  ```bash
  go get -u github.com/stretchr/testify
  go get -u github.com/DATA-DOG/go-sqlmock
  ```

- [ ] **core/mysql_test.go**
  ```go
  - [ ] TestGetDB
  - [ ] TestCreateUser
  - [ ] TestUpdateUser
  - [ ] TestDelUser
  - [ ] TestGetData
  - [ ] TestPageList
  ```

- [ ] **core/server_test.go**
  ```go
  - [ ] TestLoad
  - [ ] TestSave
  - [ ] TestGetConfig
  - [ ] TestWritePort
  - [ ] TestWritePassword
  - [ ] TestWriteTls
  ```

- [ ] **web/auth_test.go**
  ```go
  - [ ] TestJWTAuth
  - [ ] TestLogin
  - [ ] TestRefreshToken
  - [ ] TestLogout
  ```

- [ ] **trojan/install_test.go**
  ```go
  - [ ] TestInstallTrojan
  - [ ] TestInstallTls
  - [ ] TestInstallMysql
  ```

### Week 6: 代码静态分析
- [ ] **安装工具**
  ```bash
  go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
  go install github.com/securego/gosec/v2/cmd/gosec@latest
  ```

- [ ] **修复问题**
  ```bash
  golangci-lint run --fix
  gosec -fmt=json -out=results.json ./...
  ```

---

## ⚡ Phase 3: 性能优化 (Week 7-8)

### Week 7: 数据库优化
- [ ] **Day 1-2**: 连接池重构 `core/mysql.go`
  ```go
  var (
      dbInstance *sql.DB
      dbOnce     sync.Once
  )
  
  func InitDB(config *Mysql) error {
      dbOnce.Do(func() {
          // 创建连接池
          dbInstance.SetMaxOpenConns(25)
          dbInstance.SetMaxIdleConns(5)
          dbInstance.SetConnMaxLifetime(5 * time.Minute)
      })
  }
  ```

- [ ] **Day 3**: 数据库索引优化
  ```sql
  -- 为常用查询添加索引
  CREATE INDEX idx_username ON users(username);
  CREATE INDEX idx_password ON users(password);
  ```

- [ ] **Day 4-5**: 查询优化
  ```go
  - [ ] 批量查询优化
  - [ ] N+1查询问题修复
  - [ ] 预编译语句缓存
  ```

### Week 8: 配置与缓存
- [ ] **Day 1-2**: Viper配置管理
  ```bash
  go get -u github.com/spf13/viper
  
  # 创建 internal/config/config.go
  # 支持环境变量、配置文件、命令行参数
  ```

- [ ] **Day 3-5**: Redis缓存层
  ```bash
  go get -u github.com/go-redis/redis/v8
  
  # 缓存场景：
  - [ ] 用户信息缓存 (TTL: 5min)
  - [ ] 配置缓存 (TTL: 1min)
  - [ ] 流量统计缓存
  ```

---

## 🚀 Phase 4: DevOps (Week 9-10)

### Week 9: CI/CD
- [ ] **Day 1-2**: GitHub Actions
  ```yaml
  # 创建 .github/workflows/ci.yml
  - [ ] 自动化测试
  - [ ] 代码覆盖率报告
  - [ ] golangci-lint检查
  - [ ] gosec安全扫描
  ```

- [ ] **Day 3-5**: 自动化发布
  ```yaml
  # 创建 .github/workflows/release.yml
  - [ ] 自动构建二进制
  - [ ] 生成changelog
  - [ ] Docker镜像构建
  - [ ] 发布到GitHub Release
  ```

### Week 10: 文档与监控
- [ ] **Day 1-3**: Swagger API文档
  ```bash
  go get -u github.com/swaggo/swag/cmd/swag
  go get -u github.com/swaggo/gin-swagger
  
  # 为所有API添加注释
  # @Summary, @Description, @Param, @Success, @Failure
  
  swag init
  ```

- [ ] **Day 4-5**: 监控集成
  ```bash
  go get -u github.com/prometheus/client_golang
  
  # 添加指标：
  - [ ] HTTP请求计数
  - [ ] 响应时间直方图
  - [ ] 数据库连接数
  - [ ] 活跃用户数
  - [ ] 流量统计
  ```

---

## 🏗️ Phase 5: 架构重构 (Week 11-14)

### Week 11-12: 代码重组
- [ ] **创建新结构**
  ```bash
  mkdir -p internal/{config,domain,repo,service,handler}
  mkdir -p pkg/{logger,validator,crypto}
  ```

- [ ] **迁移代码**
  ```bash
  # Week 11
  - [ ] core/mysql.go → internal/repo/user_repo.go
  - [ ] core/leveldb.go → internal/repo/kv_repo.go
  - [ ] core/server.go → internal/config/trojan_config.go
  
  # Week 12
  - [ ] trojan/*.go → internal/service/trojan_service.go
  - [ ] web/controller/*.go → internal/handler/http_handler.go
  - [ ] util/*.go → pkg/*
  ```

- [ ] **接口抽象**
  ```go
  // internal/repo/interface.go
  type UserRepository interface {
      Create(user *domain.User) error
      Update(user *domain.User) error
      Delete(id uint) error
      FindByID(id uint) (*domain.User, error)
      FindByUsername(username string) (*domain.User, error)
      List() ([]*domain.User, error)
  }
  ```

### Week 13: Docker优化
- [ ] **多阶段构建**
  ```dockerfile
  # 优化 asset/Dockerfile
  - [ ] Builder阶段
  - [ ] 最小运行镜像 (alpine)
  - [ ] 非root用户
  - [ ] 健康检查
  ```

- [ ] **Docker Compose**
  ```yaml
  # 创建 docker-compose.yml
  services:
    trojan:
      build: .
      ports:
        - "8080:8080"
    mysql:
      image: mariadb:10.11
    redis:
      image: redis:7-alpine
  ```

### Week 14: K8s部署
- [ ] **创建K8s配置**
  ```bash
  mkdir -p k8s
  
  # 创建文件：
  - [ ] deployment.yaml
  - [ ] service.yaml
  - [ ] configmap.yaml
  - [ ] secret.yaml
  - [ ] ingress.yaml
  ```

---

## 📋 每日执行模板

```bash
# 每天开始
git checkout -b feature/your-feature-name
git pull origin master

# 开发
# ... 编码 ...

# 提交前检查
go fmt ./...
go vet ./...
golangci-lint run
go test -v -race ./...

# 提交
git add .
git commit -m "feat: your feature description"
git push origin feature/your-feature-name

# 创建PR
```

---

## 🎯 里程碑验收

### Milestone 1: 安全修复完成 (Week 2)
- [ ] 所有SQL注入漏洞已修复
- [ ] 依赖全部更新到最新版本
- [ ] JWT安全机制完善
- [ ] govulncheck 扫描通过

### Milestone 2: 代码质量达标 (Week 6)
- [ ] 单元测试覆盖率 ≥ 50%
- [ ] golangci-lint 无错误
- [ ] gosec 安全扫描通过
- [ ] 错误处理全部使用结构化日志

### Milestone 3: 性能优化完成 (Week 8)
- [ ] 数据库连接池化
- [ ] 缓存层实现
- [ ] API响应时间 P95 < 200ms
- [ ] 配置管理支持多种来源

### Milestone 4: 基础设施完善 (Week 10)
- [ ] CI/CD流程运行正常
- [ ] API文档自动生成
- [ ] 监控指标完整
- [ ] 健康检查端点可用

### Milestone 5: 架构现代化 (Week 14)
- [ ] 代码结构清晰
- [ ] 接口抽象完成
- [ ] Docker镜像优化
- [ ] K8s部署配置完整

---

## 📞 问题反馈

遇到问题时：
1. 查看 `REFACTOR_PLAN.md` 详细方案
2. 提交 Issue 描述问题
3. 在 Discussion 中讨论设计决策

---

**持续更新中...**
