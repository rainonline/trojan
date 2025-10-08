#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查环境
check_env() {
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log_error ".env 文件不存在！"
        log_info "请复制 .env.example 并配置："
        echo "  cp .env.example .env"
        echo "  vim .env"
        exit 1
    fi
    
    # 加载环境变量
    source "$PROJECT_ROOT/.env"
}

# 启动服务
start() {
    log_info "启动 Trojan 服务..."
    cd "$PROJECT_ROOT"
    docker-compose up -d
    log_info "等待服务就绪..."
    sleep 5
    docker-compose ps
}

# 停止服务
stop() {
    log_info "停止 Trojan 服务..."
    cd "$PROJECT_ROOT"
    docker-compose down
}

# 重启服务
restart() {
    log_info "重启 Trojan 服务..."
    cd "$PROJECT_ROOT"
    docker-compose restart
}

# 查看日志
logs() {
    service="${1:-trojan}"
    cd "$PROJECT_ROOT"
    docker-compose logs -f "$service"
}

# 进入容器
shell() {
    cd "$PROJECT_ROOT"
    docker-compose exec trojan bash
}

# 备份数据库
backup() {
    backup_dir="$PROJECT_ROOT/backup"
    mkdir -p "$backup_dir"
    backup_file="$backup_dir/trojan_$(date +%Y%m%d_%H%M%S).sql"
    
    log_info "备份数据库到 $backup_file"
    cd "$PROJECT_ROOT"
    docker-compose exec -T mariadb \
        mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" trojan > "$backup_file"
    
    log_info "备份完成！"
    gzip "$backup_file"
    log_info "压缩备份: ${backup_file}.gz"
}

# 恢复数据库
restore() {
    backup_file="$1"
    if [[ -z "$backup_file" ]]; then
        log_error "请指定备份文件路径"
        echo "用法: $0 restore /path/to/backup.sql"
        exit 1
    fi
    
    log_warn "警告: 这将覆盖现有数据库！"
    read -p "确认继续? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "取消恢复"
        exit 0
    fi
    
    log_info "恢复数据库..."
    cd "$PROJECT_ROOT"
    if [[ "$backup_file" =~ \.gz$ ]]; then
        gunzip -c "$backup_file" | docker-compose exec -T mariadb \
            mysql -u root -p"${MYSQL_ROOT_PASSWORD}" trojan
    else
        docker-compose exec -T mariadb \
            mysql -u root -p"${MYSQL_ROOT_PASSWORD}" trojan < "$backup_file"
    fi
    
    log_info "恢复完成！"
}

# 更新到新版本
update() {
    new_version="$1"
    if [[ -z "$new_version" ]]; then
        log_error "请指定版本号"
        echo "用法: $0 update v1.0.1"
        exit 1
    fi
    
    log_info "更新到版本 $new_version"
    
    # 1. 备份
    log_info "步骤 1/5: 备份数据库..."
    backup
    
    # 2. 拉取新代码
    log_info "步骤 2/5: 拉取新代码..."
    cd "$PROJECT_ROOT"
    git fetch --tags
    git checkout "$new_version"
    
    # 3. 重新构建镜像
    log_info "步骤 3/5: 构建新镜像..."
    export VERSION="$new_version"
    export BUILD_DATE=$(date -u +"%Y%m%d-%H%M")
    export GIT_COMMIT=$(git rev-parse HEAD)
    docker-compose build
    
    # 4. 停止旧容器
    log_info "步骤 4/5: 停止旧服务..."
    docker-compose down
    
    # 5. 启动新容器
    log_info "步骤 5/5: 启动新服务..."
    docker-compose up -d
    
    log_info "✅ 更新完成到版本 $new_version"
}

# 回滚到旧版本
rollback() {
    old_version="$1"
    if [[ -z "$old_version" ]]; then
        log_error "请指定要回滚的版本号"
        echo "用法: $0 rollback v1.0.0"
        exit 1
    fi
    
    log_warn "回滚到版本 $old_version"
    update "$old_version"
}

# 查看状态
status() {
    cd "$PROJECT_ROOT"
    docker-compose ps
    echo ""
    log_info "服务健康状态:"
    docker-compose exec trojan curl -s http://localhost:8080/health 2>/dev/null || log_error "Trojan 服务异常"
}

# 构建镜像
build() {
    log_info "构建 Docker 镜像..."
    cd "$PROJECT_ROOT"
    export VERSION="${VERSION:-dev}"
    export BUILD_DATE=$(date -u +"%Y%m%d-%H%M")
    export GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    docker-compose build
    log_info "✅ 构建完成"
}

# ==========================================
# 用户管理功能
# ==========================================

# 添加用户
user_add() {
    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        log_error "用法: $0 user add <username> <password>"
        exit 1
    fi
    
    log_info "添加用户: $1"
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan add "$1" "$2"
}

# 删除用户
user_del() {
    if [[ -z "$1" ]]; then
        log_error "用法: $0 user del <username>"
        exit 1
    fi
    
    log_info "删除用户: $1"
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan del "$1"
}

# 用户列表
user_list() {
    log_info "用户列表:"
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan info
}

# 清空用户流量
user_clean() {
    if [[ -z "$1" ]]; then
        log_error "用法: $0 user clean <username>"
        exit 1
    fi
    
    log_info "清空用户流量: $1"
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan clean "$1"
}

# ==========================================
# 配置管理功能
# ==========================================

# 修改端口
config_port() {
    if [[ -z "$1" ]]; then
        log_error "用法: $0 config port <new-port>"
        exit 1
    fi
    
    new_port="$1"
    log_info "修改 Trojan 端口为: $new_port"
    
    # 修改 .env 文件
    if grep -q "TROJAN_PORT" "$PROJECT_ROOT/.env"; then
        sed -i.bak "s/TROJAN_PORT=.*/TROJAN_PORT=$new_port/" "$PROJECT_ROOT/.env"
    else
        echo "TROJAN_PORT=$new_port" >> "$PROJECT_ROOT/.env"
    fi
    
    # 修改 docker-compose.yml 中的端口映射
    log_warn "请手动修改 docker-compose.yml 中的端口映射"
    log_info "然后运行: $0 restart"
}

# TLS 证书管理
tls_install() {
    log_info "安装 TLS 证书..."
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan tls
}

tls_renew() {
    log_info "续期 TLS 证书..."
    cd "$PROJECT_ROOT"
    docker-compose exec trojan bash -c "~/.acme.sh/acme.sh --cron"
}

# ==========================================
# 升级功能
# ==========================================

upgrade_db() {
    log_info "升级数据库..."
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan upgrade db
}

upgrade_config() {
    log_info "升级配置文件..."
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan upgrade config
}

# ==========================================
# 信息查询
# ==========================================

show_version() {
    log_info "版本信息:"
    echo ""
    echo "  Trojan 版本: ${VERSION:-未知}"
    echo "  构建日期: ${BUILD_DATE:-未知}"
    echo "  Git 提交: ${GIT_COMMIT:-未知}"
    echo ""
    log_info "容器内版本:"
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan version 2>/dev/null || echo "  容器未运行"
}

# 导出配置信息
export_config() {
    log_info "当前配置:"
    cd "$PROJECT_ROOT"
    docker-compose exec trojan bash -c "cat /usr/local/etc/trojan/config.json" 2>/dev/null || log_error "容器未运行"
}

# ==========================================
# 直接执行容器内命令
# ==========================================

exec_command() {
    if [[ -z "$1" ]]; then
        log_error "用法: $0 exec <trojan-command> [args...]"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
    docker-compose exec trojan trojan "$@"
}

# ==========================================
# 交互式菜单
# ==========================================

interactive_menu() {
    while true; do
        echo ""
        echo "═══════════════════════════════════════════"
        echo "  Trojan Docker 管理菜单"
        echo "═══════════════════════════════════════════"
        echo "  1) 启动服务"
        echo "  2) 停止服务"
        echo "  3) 重启服务"
        echo "  4) 查看状态"
        echo "  5) 查看日志"
        echo "───────────────────────────────────────────"
        echo "  6) 添加用户"
        echo "  7) 删除用户"
        echo "  8) 用户列表"
        echo "  9) 清空流量"
        echo "───────────────────────────────────────────"
        echo "  10) 备份数据库"
        echo "  11) 恢复数据库"
        echo "  12) 更新版本"
        echo "───────────────────────────────────────────"
        echo "  13) TLS 证书管理"
        echo "  14) 修改端口"
        echo "  15) 版本信息"
        echo "───────────────────────────────────────────"
        echo "  16) 进入容器 Shell"
        echo "  0) 退出"
        echo "═══════════════════════════════════════════"
        echo ""
        
        read -p "请选择 [0-16]: " choice
        
        case $choice in
            1) start ;;
            2) stop ;;
            3) restart ;;
            4) status ;;
            5) 
                read -p "查看哪个服务的日志? (trojan/mariadb): " svc
                logs "${svc:-trojan}"
                ;;
            6)
                read -p "用户名: " username
                read -sp "密码: " password
                echo ""
                user_add "$username" "$password"
                ;;
            7)
                read -p "要删除的用户名: " username
                user_del "$username"
                ;;
            8) user_list ;;
            9)
                read -p "要清空流量的用户名: " username
                user_clean "$username"
                ;;
            10) backup ;;
            11)
                read -p "备份文件路径: " file
                restore "$file"
                ;;
            12)
                read -p "目标版本 (如 v1.0.1): " ver
                update "$ver"
                ;;
            13)
                echo "1) 安装证书  2) 续期证书"
                read -p "选择: " tls_choice
                case $tls_choice in
                    1) tls_install ;;
                    2) tls_renew ;;
                esac
                ;;
            14)
                read -p "新端口号: " port
                config_port "$port"
                ;;
            15) show_version ;;
            16) shell ;;
            0) 
                log_info "退出管理菜单"
                exit 0
                ;;
            *)
                log_error "无效选择"
                ;;
        esac
        
        echo ""
        read -p "按 Enter 继续..."
    done
}

# 帮助信息
usage() {
    cat << EOF
Trojan Docker 管理脚本 - 完整兼容原有 CLI 命令

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 🚀 服务管理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  start              启动所有服务
  stop               停止所有服务
  restart            重启所有服务
  status             查看服务状态
  logs [service]     查看日志 (默认: trojan)
  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 👥 用户管理 (完全兼容 trojan CLI)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  user add <user> <pass>     添加用户 (= trojan add)
  user del <user>            删除用户 (= trojan del)
  user list                  用户列表 (= trojan info)
  user clean <user>          清空流量 (= trojan clean)
  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ⚙️  配置管理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  config port <port>         修改端口 (= trojan port)
  config show                显示配置
  tls install                安装证书 (= trojan tls)
  tls renew                  续期证书
  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 💾 数据管理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  backup                     备份数据库 (= trojan export)
  restore <file>             恢复数据库 (= trojan import)
  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 📦 版本管理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  update <version>           更新到指定版本 (= trojan update)
  rollback <version>         回滚到指定版本
  upgrade db                 升级数据库 (= trojan upgrade db)
  upgrade config             升级配置 (= trojan upgrade config)
  version                    显示版本 (= trojan version)
  build                      构建 Docker 镜像
  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 🛠️  高级功能
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  shell                      进入容器 Shell
  exec <cmd> [args]          执行容器内命令
  menu                       交互式菜单
  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📖 示例:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # 基础操作
  $0 start
  $0 logs
  $0 status
  
  # 用户管理 (与原 trojan 命令完全一致)
  $0 user add user1 password123
  $0 user list
  $0 user del user1
  
  # 数据备份
  $0 backup
  $0 restore backup/trojan_20251008.sql.gz
  
  # 版本更新
  $0 update v1.0.1
  $0 rollback v1.0.0
  
  # 直接执行原有命令 (完全兼容)
  $0 exec add user2 pass2      # = trojan add user2 pass2
  $0 exec info                 # = trojan info
  $0 exec port 8443            # = trojan port 8443
  
  # 交互式菜单
  $0 menu
  $0                           # 无参数时自动进入菜单

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💡 提示: 所有原有 'trojan' 命令都可通过以下方式使用:
  1. $0 exec <命令> [参数]     # 转发到容器内
  2. $0 <快捷命令> [参数]      # 使用快捷方式
  3. $0 shell → trojan <命令>  # 进入容器直接使用

EOF
}

# 主逻辑
check_env

# 无参数时进入交互式菜单
if [[ $# -eq 0 ]]; then
    interactive_menu
fi

case "$1" in
    # 服务管理
    start)      start ;;
    stop)       stop ;;
    restart)    restart ;;
    logs)       logs "$2" ;;
    shell)      shell ;;
    status)     status ;;
    build)      build ;;
    
    # 用户管理
    user)
        case "$2" in
            add)    user_add "$3" "$4" ;;
            del)    user_del "$3" ;;
            list)   user_list ;;
            clean)  user_clean "$3" ;;
            *)      
                log_error "用法: $0 user {add|del|list|clean}"
                exit 1
                ;;
        esac
        ;;
    
    # 配置管理
    config)
        case "$2" in
            port)   config_port "$3" ;;
            show)   export_config ;;
            *)
                log_error "用法: $0 config {port|show}"
                exit 1
                ;;
        esac
        ;;
    
    # TLS 管理
    tls)
        case "$2" in
            install) tls_install ;;
            renew)   tls_renew ;;
            *)
                log_error "用法: $0 tls {install|renew}"
                exit 1
                ;;
        esac
        ;;
    
    # 数据管理
    backup)     backup ;;
    restore)    restore "$2" ;;
    
    # 版本管理
    update)     update "$2" ;;
    rollback)   rollback "$2" ;;
    upgrade)
        case "$2" in
            db)     upgrade_db ;;
            config) upgrade_config ;;
            *)
                log_error "用法: $0 upgrade {db|config}"
                exit 1
                ;;
        esac
        ;;
    
    # 信息查询
    version)    show_version ;;
    
    # 直接执行容器内命令
    exec)       
        shift
        exec_command "$@" 
        ;;
    
    # 交互式菜单
    menu)       interactive_menu ;;
    
    # 帮助
    -h|--help|help) usage ;;
    
    *)          
        log_error "未知命令: $1"
        usage
        exit 1
        ;;
esac
