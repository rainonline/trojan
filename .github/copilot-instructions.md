# Trojan Multi-User Management System - AI Coding Guide

## Project Overview
Go-based trojan proxy multi-user management system with dual interfaces: CLI (cobra-based) and web (gin-based). Manages trojan/trojan-go server deployments with MySQL user storage, traffic monitoring, and TLS certificate automation.

## Architecture

### Core Modules (pkg-like structure)
- **`cmd/`**: Cobra command definitions (add, del, start, stop, etc.) - entry points only, delegate to `trojan/` package
- **`core/`**: Config management (`/usr/local/etc/trojan/config.json`), MySQL operations, LevelDB state storage (`/var/lib/trojan-manager`)
- **`trojan/`**: Business logic for user management, service control, TLS setup, installation workflows
- **`web/`**: Gin REST API + JWT auth + embedded Vue.js frontend (see `web.go` routers)
- **`util/`**: System utilities (systemctl wrappers, firewall/iptables, shell execution)
- **`asset/`**: Embedded files via `go:embed` (install scripts, client templates)

### Data Flow
1. **CLI Mode**: `main.go` → `cmd.Execute()` → Interactive menu (`trojan.UserMenu()`, etc.) → `core` operations
2. **Web Mode**: `web.Start()` → Gin routes → `web/controller` → `core.GetMysql()` → Database ops
3. **Config Sync**: All changes write to `/usr/local/etc/trojan/config.json`, trigger `util.SystemctlRestart("trojan")`

## Critical Patterns

### Service Management
Always follow this pattern when modifying trojan service:
```go
config := core.GetConfig()
// Modify config...
core.WritePort(newPort)  // or WritePassword, WriteTls, etc.
util.OpenPort(newPort)   // Update firewall
util.SystemctlRestart("trojan")
```

### Database Operations
MySQL is the source of truth for users. LevelDB stores app state (domain, reset day, clash rules):
```go
mysql := core.GetMysql()  // Reads from config.json mysql section
users, _ := mysql.GetData()  // Always returns []*core.User
mysql.AddUser(username, password)  // Auto-hashes with SHA224
```

### Embedded Assets
Never hardcode paths to scripts/templates. Use:
```go
data := asset.GetAsset("trojan-install.sh")  // Returns []byte
util.ExecCommand(string(data))  // Run embedded shell script
```

### Web API Routes
JWT required except `/trojan/user/subscribe` (Clash subscription). Key endpoints:
- `POST /trojan/user` - Create user (username, password)
- `GET /trojan/user?id=X` - List users (admin sees all, users see self)
- `POST /trojan/data` - Set quota (id, quota)
- `POST /trojan/restart` - Restart service
- `GET /trojan/log` - WebSocket log streaming (see `controller.Log()`)

## Development Workflows

### Build & Deploy
```bash
# Local build with version info
./build.sh  # Outputs to result/trojan-linux-{amd64,arm64}

# Install/Update on server
source <(curl -sL https://git.io/trojan-install)

# Docker development (推荐使用新版 docker-compose)
cd trojan
cp .env.example .env
./docker/manage.sh start
./docker/manage.sh menu  # Interactive CLI
```

### Testing Changes
1. Modify code in appropriate package (`core` for config, `trojan` for logic, `web/controller` for API)
2. Rebuild: `go build -o trojan .`
3. Replace binary: `cp trojan /usr/local/bin/`
4. Test CLI: `trojan` → Navigate menus
5. Test web: 访问 https://domain （Docker 方式：`./docker/manage.sh restart`）

### Adding New Commands
1. Create `cmd/newcmd.go` with cobra command
2. Add to `cmd/root.go` init: `rootCmd.AddCommand(newcmdCmd)`
3. Implement logic in `trojan/newfeature.go`
4. Update help text in command's `Short` field

## Project-Specific Conventions

### Error Handling
CLI uses print-and-return pattern (user-facing):
```go
if err != nil {
    fmt.Println(util.Red("操作失败: " + err.Error()))
    return
}
fmt.Println(util.Green("操作成功!"))
```

Web API uses controller response pattern:
```go
responseBody := ResponseBody{Msg: "success"}
defer TimeCost(time.Now(), &responseBody)  // Auto-calculates duration
if err != nil {
    responseBody.Msg = err.Error()
    return &responseBody
}
```

### User Authentication
- **CLI**: No auth (root access assumed)
- **Web**: JWT middleware in `web/auth.go`. Admin user stored in LevelDB. Check `RequestUsername(c)` for current user

### Trojan vs Trojan-Go
System supports switching between implementations. Check type: `trojan.Type()` returns "trojan" or "trojan-go". Switch via `trojan.SwitchType(newType)` (rewrites config + systemd unit).

### Config Persistence
Never edit `/usr/local/etc/trojan/config.json` directly. Use:
```go
core.WritePassword([]string{pass})  // Updates password array
core.WriteTls(cert, key, domain)    // Updates SSL + SNI
core.WritePort(port)                // Updates local_port
// All auto-save and format with tidwall/pretty
```

## Common Gotchas

1. **Systemctl in Docker**: `util.SystemctlRestart()` auto-detects `/.dockerenv` and downloads systemctl replacement if needed
2. **Firewall Rules**: `util.OpenPort()` tries firewalld first, falls back to iptables. Always call after port changes
3. **Password Hashing**: Web API accepts base64-encoded passwords, decodes, then SHA224. CLI directly uses plaintext
4. **Embedded FS**: Changes to `asset/*` files require rebuild. Test with `go:embed` means file must exist at compile time
5. **MySQL Connection**: Config defaults to `localhost:3306`. Docker setups use `host.docker.internal` or custom IP

## Quick Reference

**Key Files:**
- `cmd/root.go` - CLI entry & main menu
- `core/server.go` - Config load/save for `/usr/local/etc/trojan/config.json`
- `core/mysql.go` - All database operations
- `trojan/install.go` - Installation logic (TLS, MySQL, trojan binary)
- `web/web.go` - API route definitions
- `util/command.go` - Systemctl & shell execution wrappers

**Common Commands:**
```bash
trojan add          # Add user (CLI)
trojan info         # List users with traffic
trojan restart      # Restart trojan service
trojan web          # Start web UI (default port 8080)
trojan tls          # Install/renew TLS certificates
```

**Environment:**
- Go 1.21+
- Linux (systemd required)
- MySQL/MariaDB for user storage
- TLS certificates in `/usr/local/etc/trojan/` (cert.crt, cert.key)
