# 管理员账号密码失效问题分析与解决方案

## 🔍 问题分析

### 问题描述
管理员账号过段时间就会失效，无法登录。

### 根本原因
在 `web/auth.go` 中的 JWT 配置存在问题：

```go
authMiddleware, err = jwt.New(&jwt.GinJWTMiddleware{
    Timeout:     time.Minute * time.Duration(timeout),  // 120分钟
    MaxRefresh:  time.Minute * time.Duration(timeout),  // 120分钟
    // ...
})
```

**问题点**：
1. **Timeout**: Token 有效期设置为 `timeout` 分钟（默认 120 分钟）
2. **MaxRefresh**: Token 最大刷新时间也是 `timeout` 分钟

**JWT 工作机制**：
- Token 签发后，在 `Timeout` 时间内有效
- 在 `Timeout` 到期后，可以通过 `/auth/refresh_token` 刷新
- 但刷新只能在 `MaxRefresh` 时间内进行
- **问题**：当 `Timeout == MaxRefresh` 时，Token 过期后无法刷新，必须重新登录

### 时间线示例
```
登录时间: 00:00
Token 有效期: 120分钟 (02:00到期)
可刷新期限: 120分钟 (02:00到期)

00:00 ──────────────────────────────────────> 02:00
        Token 有效                           Token 过期
                                             无法刷新（MaxRefresh也到期）
                                             ❌ 必须重新登录
```

### 正确的配置
```
登录时间: 00:00
Token 有效期: 120分钟 (02:00到期)
可刷新期限: 1440分钟 (24:00到期) ← MaxRefresh > Timeout

00:00 ──────────────────────────────────────> 02:00 ──────────> 24:00
        Token 有效                           Token 过期           刷新窗口结束
                                             ✅ 可刷新 ───────────>
```

## 🎯 解决方案

### 方案 1：增加 MaxRefresh 时间（推荐）

**修改 `web/auth.go`**：
```go
authMiddleware, err = jwt.New(&jwt.GinJWTMiddleware{
    Realm:       "trojan-manager",
    Key:         []byte(getSecretKey()),
    Timeout:     time.Minute * time.Duration(timeout),      // Token 有效期: 120分钟
    MaxRefresh:  time.Hour * 24 * 7,                        // 刷新窗口: 7天
    // MaxRefresh:  time.Hour * 24,                         // 或者 24小时
    IdentityKey: identityKey,
    // ...
})
```

**优点**：
- ✅ Token 120分钟后自动刷新（如果前端实现了自动刷新）
- ✅ 用户在7天内可以随时刷新，无需重新登录
- ✅ 平衡了安全性和用户体验

### 方案 2：延长 Token 有效期

**修改 `cmd/web.go` 的默认超时时间**：
```go
webCmd.Flags().IntVarP(&timeout, "timeout", "t", 1440, "登录超时时间(min)") // 24小时
```

**同时修改 `web/auth.go`**：
```go
authMiddleware, err = jwt.New(&jwt.GinJWTMiddleware{
    Timeout:     time.Minute * time.Duration(timeout),      // 24小时
    MaxRefresh:  time.Hour * 24 * 7,                        // 7天
    // ...
})
```

**优点**：
- ✅ Token 24小时内有效，减少刷新频率
- ✅ 用户体验更好
- ⚠️ 安全性略有降低（但对管理后台可接受）

### 方案 3：前端自动刷新 Token（最佳实践）

**后端保持现有配置**，前端实现自动刷新：

```javascript
// 前端代码示例
let tokenRefreshTimer = null;

function scheduleTokenRefresh() {
    // 在 Token 过期前 5 分钟刷新
    const refreshTime = (120 - 5) * 60 * 1000; // 115分钟
    
    tokenRefreshTimer = setTimeout(async () => {
        try {
            const response = await fetch('/auth/refresh_token', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${localStorage.getItem('token')}`
                }
            });
            
            if (response.ok) {
                const data = await response.json();
                localStorage.setItem('token', data.token);
                scheduleTokenRefresh(); // 继续调度下次刷新
            }
        } catch (error) {
            console.error('Token refresh failed:', error);
        }
    }, refreshTime);
}

// 登录成功后调用
scheduleTokenRefresh();
```

**优点**：
- ✅ 完全自动化，用户无感知
- ✅ Token 保持短有效期，安全性高
- ✅ 前端控制刷新逻辑，灵活性高

## 📋 推荐配置

### 适合管理后台的配置

```go
// web/auth.go
authMiddleware, err = jwt.New(&jwt.GinJWTMiddleware{
    Realm:       "trojan-manager",
    Key:         []byte(getSecretKey()),
    Timeout:     time.Hour * 2,           // Token 有效期: 2小时
    MaxRefresh:  time.Hour * 24,          // 刷新窗口: 24小时
    IdentityKey: identityKey,
    SendCookie:  true,
    // ...
})
```

**时间线**：
```
登录: 00:00
Token 有效期: 2小时 (02:00到期)
刷新窗口: 24小时 (24:00到期)

00:00 ──> 02:00 ────────────────────────> 24:00
   Token有效  Token过期但可刷新              刷新窗口关闭
              (22小时刷新窗口)
```

## 🔧 实施步骤

### 步骤 1：修改 JWT 配置（推荐方案 1）

**编辑 `web/auth.go`**：
```go
func jwtInit(timeout int) {
    authMiddleware, err = jwt.New(&jwt.GinJWTMiddleware{
        Realm:       "trojan-manager",
        Key:         []byte(getSecretKey()),
        Timeout:     time.Minute * time.Duration(timeout),  // 保持可配置
        MaxRefresh:  time.Hour * 24,                        // 固定24小时刷新窗口
        IdentityKey: identityKey,
        SendCookie:  true,
        // ...其他配置不变
    })
    // ...
}
```

### 步骤 2：测试验证

```bash
# 1. 重新编译
go build -o trojan .

# 2. 重启服务
systemctl restart trojan-web

# 3. 测试登录
curl -X POST http://localhost:8080/auth/login \
  -d "username=admin&password=your_password"

# 响应示例：
{
  "code": 200,
  "expire": "2025-10-08T12:00:00+08:00",  # Token 过期时间
  "token": "eyJhbGc..."
}

# 4. 等待 Token 过期后测试刷新
curl -X POST http://localhost:8080/auth/refresh_token \
  -H "Authorization: Bearer <token>"

# 应该返回新的 Token
```

### 步骤 3：监控日志

```bash
# 查看 JWT 相关日志
journalctl -u trojan-web -f | grep -i "jwt\|auth\|token"
```

## 📊 不同配置对比

| 配置方案 | Timeout | MaxRefresh | 适用场景 | 安全性 | 用户体验 |
|---------|---------|------------|----------|--------|---------|
| 当前配置 | 120分钟 | 120分钟 | ❌ 不推荐 | ⚠️ 中 | ❌ 差（频繁重登录） |
| 方案1 | 120分钟 | 24小时 | ✅ 推荐 | ✅ 高 | ✅ 好 |
| 方案2 | 24小时 | 7天 | ⚠️ 可选 | ⚠️ 中 | ✅ 很好 |
| 方案3 | 120分钟 | 24小时 + 前端自动刷新 | ✅✅ 最佳 | ✅✅ 很高 | ✅✅ 很好 |

## 🔒 安全建议

1. **使用 HTTPS**：JWT Token 通过 HTTPS 传输，防止中间人攻击
2. **强密钥**：确保 JWT 密钥足够复杂（至少 32 字符）
3. **刷新机制**：实现前端自动刷新，避免长期 Token
4. **撤销机制**：考虑实现 Token 黑名单或版本控制
5. **审计日志**：记录所有登录和刷新操作

## 📝 相关代码位置

- **JWT 配置**：`web/auth.go` 第 32-40 行
- **超时参数**：`cmd/web.go` 第 30 行
- **登录端点**：`web/auth.go` 第 150 行
- **刷新端点**：`web/auth.go` 第 174 行

## 🚀 快速修复（一键脚本）

```bash
#!/bin/bash
# fix-jwt-timeout.sh

# 备份原文件
cp web/auth.go web/auth.go.backup

# 修改 MaxRefresh 为 24 小时
sed -i 's/MaxRefresh:  time\.Minute \* time\.Duration(timeout),/MaxRefresh:  time.Hour * 24,  \/\/ 24小时刷新窗口/' web/auth.go

# 重新编译
go build -o trojan .

# 重启服务
systemctl restart trojan-web

echo "✅ JWT 配置已修复，Token 现在可以在 24 小时内刷新"
```

## 🔮 未来改进

1. **Redis 存储 Token**：实现分布式 Token 管理
2. **OAuth2 集成**：支持第三方登录
3. **多因素认证**：增加 TOTP/SMS 验证
4. **会话管理**：支持查看和撤销活跃会话
5. **IP 白名单**：限制管理后台访问来源

---

**总结**：当前问题是 `MaxRefresh` 等于 `Timeout`，导致 Token 过期后无法刷新。**推荐修改 `MaxRefresh` 为 24 小时**，这样用户在 Token 过期后仍有 22 小时的刷新窗口，无需频繁重新登录。
