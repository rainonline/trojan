# Trojan 项目翻新计划

## 📋 项目现状分析

### 技术栈
- **Go版本**: 1.21 (当前LTS: 1.23)
- **Web框架**: Gin v1.9.1 (最新: v1.11.0)
- **数据库**: MySQL + LevelDB
- **认证**: JWT (gin-jwt v2.9.1)
- **特点**: CLI + Web 双界面管理

### 主要问题
1. ❌ **无测试覆盖** - 整个项目没有任何单元测试
2. ⚠️ **SQL注入风险** - 多处使用字符串拼接SQL
3. ⚠️ **错误处理不规范** - 大量使用`fmt.Println`输出错误
4. ⚠️ **依赖版本过时** - 多个依赖需要更新
5. ⚠️ **硬编码配置** - 配置路径写死在代码中
6. ⚠️ **数据库连接低效** - 每次查询都创建新连接
7. ⚠️ **缺少API文档** - Web API无Swagger文档
8. ⚠️ **无CI/CD** - 缺少自动化测试和发布流程

---

## 🎯 翻新目标

### 短期目标 (1-2个月)
- 修复安全漏洞
- 建立测试框架
- 标准化错误处理
- 更新依赖版本

### 中期目标 (3-4个月)
- 重构代码架构
- 性能优化
- API文档化
- CI/CD建立

### 长期目标 (5-6个月)
- 国际化支持
- 可观测性增强
- 云原生改造

---

## 📊 翻新计划详解

### Phase 1: 安全加固与基础设施 (优先级: 🔴 高)

#### 1.1 SQL注入漏洞修复
**问题位置**:
- `core/mysql.go`: `CreateUser()`, `UpdateUser()`
- `web/controller/trojan.go`: `ImportCsv()`
- `core/tools.go`: `DumpSql()`

**修复方案**:
```go
// ❌ 当前写法 (有SQL注入风险)
fmt.Sprintf("INSERT INTO users(username, password) VALUES ('%s', '%s');", username, password)

// ✅ 改进写法 (使用参数化查询)
db.Exec("INSERT INTO users(username, password) VALUES (?, ?)", username, password)
```

**工作量**: 2-3天

#### 1.2 依赖更新
```bash
# 主要更新
go 1.21 -> 1.23
github.com/gin-gonic/gin v1.9.1 -> v1.11.0
golang.org/x/crypto v0.13.0 -> latest

# 安全检查
go mod tidy
go list -m -u all
govulncheck ./...
```

**工作量**: 1天

#### 1.3 JWT安全增强
**改进点**:
- [ ] 密钥轮换机制
- [ ] 刷新令牌实现
- [ ] 令牌撤销/黑名单
- [ ] HTTPS强制
- [ ] CORS配置

**工作量**: 3-4天

---

### Phase 2: 代码质量提升 (优先级: 🔴 高)

#### 2.1 错误处理标准化
**当前问题**:
```go
// ❌ 到处都是
fmt.Println(err)
fmt.Println("操作失败")
```

**改进方案**:
```go
// ✅ 使用结构化日志
import "go.uber.org/zap"

logger.Error("操作失败", 
    zap.Error(err),
    zap.String("operation", "createUser"),
    zap.String("username", username))

// ✅ 统一错误包装
return fmt.Errorf("创建用户失败: %w", err)
```

**工作量**: 5-7天

#### 2.2 单元测试覆盖
**目标覆盖率**: 核心模块 50%+

**测试框架**:
```go
import (
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
)
```

**优先测试模块**:
1. `core/mysql.go` - 数据库操作
2. `core/server.go` - 配置管理
3. `web/auth.go` - 认证逻辑
4. `trojan/install.go` - 安装逻辑

**工作量**: 10-12天

#### 2.3 代码组织重构
**当前结构**:
```
trojan/
├── cmd/          # Cobra命令
├── core/         # 配置+数据库(混合)
├── trojan/       # 业务逻辑(混合)
├── web/          # Web API
└── util/         # 工具函数
```

**改进结构**:
```
trojan/
├── cmd/          # CLI入口
├── internal/     # 私有包
│   ├── config/   # 配置管理
│   ├── domain/   # 领域模型
│   ├── repo/     # 数据访问层
│   ├── service/  # 业务逻辑层
│   └── handler/  # HTTP处理层
├── pkg/          # 可导出包
└── api/          # API定义
```

**工作量**: 7-10天

---

### Phase 3: 性能与可靠性 (优先级: 🟡 中)

#### 3.1 数据库连接池
**问题**:
```go
// ❌ 每次查询都创建新连接
func (mysql *Mysql) GetDB() *sql.DB {
    db, err := sql.Open("mysql", conn)
    // ...
}
```

**解决方案**:
```go
// ✅ 单例连接池
var (
    dbInstance *sql.DB
    dbOnce     sync.Once
)

func GetDB() *sql.DB {
    dbOnce.Do(func() {
        dbInstance, _ = sql.Open("mysql", dsn)
        dbInstance.SetMaxOpenConns(25)
        dbInstance.SetMaxIdleConns(5)
        dbInstance.SetConnMaxLifetime(5 * time.Minute)
    })
    return dbInstance
}
```

**工作量**: 2-3天

#### 3.2 配置管理重构
**替换硬编码**:
```go
// ❌ 硬编码路径
var configPath = "/usr/local/etc/trojan/config.json"
var dbPath = "/var/lib/trojan-manager"

// ✅ 使用环境变量 + viper
viper.SetDefault("config.path", "/usr/local/etc/trojan/config.json")
viper.BindEnv("config.path", "TROJAN_CONFIG_PATH")
```

**工作量**: 3-4天

#### 3.3 缓存层添加
**场景**:
- 用户信息缓存
- 配置缓存
- 流量统计缓存

**技术选型**:
```go
import "github.com/go-redis/redis/v8"

// 或轻量级内存缓存
import "github.com/patrickmn/go-cache"
```

**工作量**: 4-5天

---

### Phase 4: DevOps与可观测性 (优先级: 🟡 中)

#### 4.1 CI/CD流程
**GitHub Actions**:
```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'
      - run: go test -v -race -coverprofile=coverage.out ./...
      - run: golangci-lint run
      - run: gosec ./...
```

**工作量**: 2-3天

#### 4.2 API文档自动化
**Swagger集成**:
```go
import (
    _ "trojan/docs" // swag init生成
    swaggerFiles "github.com/swaggo/files"
    ginSwagger "github.com/swaggo/gin-swagger"
)

// @title Trojan管理API
// @version 2.0
// @description Trojan多用户管理系统API
router.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
```

**工作量**: 3-4天

#### 4.3 监控与日志
**Prometheus指标**:
```go
import "github.com/prometheus/client_golang/prometheus"

var (
    userCount = prometheus.NewGauge(...)
    apiDuration = prometheus.NewHistogramVec(...)
)

router.GET("/metrics", gin.WrapH(promhttp.Handler()))
```

**结构化日志**:
```go
// 统一日志格式 (JSON)
logger.Info("用户登录",
    zap.String("username", username),
    zap.String("ip", ip),
    zap.Duration("duration", elapsed))
```

**工作量**: 5-6天

---

### Phase 5: 云原生改造 (优先级: 🟢 低)

#### 5.1 Docker优化
**多阶段构建**:
```dockerfile
# 构建阶段
FROM golang:1.23-alpine AS builder
WORKDIR /build
COPY . .
RUN go build -ldflags="-s -w" -o trojan .

# 运行阶段
FROM alpine:latest
RUN adduser -D -u 1000 trojan
USER trojan
COPY --from=builder /build/trojan /app/trojan
HEALTHCHECK --interval=30s CMD wget -q --spider http://localhost:8080/health
ENTRYPOINT ["/app/trojan"]
```

**工作量**: 2天

#### 5.2 Kubernetes部署
```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trojan-manager
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: trojan
        image: trojan:v2.0
        env:
        - name: MYSQL_HOST
          valueFrom:
            configMapKeyRef:
              name: trojan-config
              key: mysql.host
```

**工作量**: 3-4天

#### 5.3 国际化支持
```go
import "github.com/nicksnyder/go-i18n/v2/i18n"

// 提取所有中文字符串
// 创建翻译文件
// active.zh.toml
// active.en.toml

localizer := i18n.NewLocalizer(bundle, "en")
msg := localizer.MustLocalize(&i18n.LocalizeConfig{
    MessageID: "welcome",
})
```

**工作量**: 7-10天

---

## 📅 时间线规划

### 第1-2周: 紧急安全修复
- [x] SQL注入漏洞修复
- [x] 依赖更新
- [x] JWT安全加固

### 第3-4周: 代码质量
- [x] 错误处理标准化
- [x] 添加核心模块单元测试
- [x] 代码静态分析修复

### 第5-6周: 性能优化
- [x] 数据库连接池
- [x] 配置管理重构
- [x] 缓存层添加

### 第7-8周: 基础设施
- [x] CI/CD建立
- [x] API文档生成
- [x] 日志监控集成

### 第9-12周: 架构重构
- [x] 代码组织优化
- [x] 接口抽象
- [x] Docker优化

### 第13-16周: 高级功能
- [x] Kubernetes部署
- [x] 国际化支持
- [x] 性能测试优化

---

## 🔧 技术选型更新

### 新增依赖推荐
```go
// 日志
"go.uber.org/zap"

// 配置
"github.com/spf13/viper"

// 测试
"github.com/stretchr/testify"
"github.com/DATA-DOG/go-sqlmock"

// 监控
"github.com/prometheus/client_golang"

// API文档
"github.com/swaggo/swag"
"github.com/swaggo/gin-swagger"

// 缓存
"github.com/go-redis/redis/v8"

// 国际化
"github.com/nicksnyder/go-i18n/v2"
```

---

## ✅ 验收标准

### 代码质量
- [ ] 单元测试覆盖率 ≥ 50%
- [ ] golangci-lint 无错误
- [ ] gosec 安全扫描通过
- [ ] 所有SQL使用参数化查询

### 性能
- [ ] API响应时间 P95 < 200ms
- [ ] 数据库连接池化
- [ ] 关键路径有缓存

### 可维护性
- [ ] 完整的API文档
- [ ] 结构化日志
- [ ] 错误追踪
- [ ] 健康检查端点

### DevOps
- [ ] CI自动运行测试
- [ ] CD自动发布
- [ ] Docker镜像 < 50MB
- [ ] K8s部署配置完整

---

## 🚀 快速开始

### 开发环境准备
```bash
# 1. 更新Go版本
go version  # 确保 >= 1.23

# 2. 安装开发工具
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
go install github.com/securego/gosec/v2/cmd/gosec@latest
go install github.com/swaggo/swag/cmd/swag@latest

# 3. 运行测试
go test -v -race ./...

# 4. 代码检查
golangci-lint run
gosec ./...
```

### 参与贡献
1. Fork项目
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启Pull Request

---

## 📝 备注

### 兼容性承诺
- 保持CLI命令向后兼容
- Web API使用版本控制 (v1, v2)
- 配置文件平滑迁移脚本

### 风险评估
- **高风险**: SQL注入修复可能引入新bug → 需要充分测试
- **中风险**: 架构重构可能影响现有功能 → 分阶段进行
- **低风险**: 日志和监控添加 → 非侵入式

### 资源需求
- **开发人员**: 2-3人
- **测试人员**: 1人
- **时间**: 3-4个月
- **服务器**: 测试环境 + 预发布环境

---

**更新时间**: 2025年10月8日  
**版本**: v1.0  
**维护者**: @rainonline
