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

# 帮助信息
usage() {
    cat << EOF
Trojan Docker 管理脚本

用法: $0 <command> [options]

命令:
  start              启动所有服务
  stop               停止所有服务
  restart            重启所有服务
  logs [service]     查看日志 (默认: trojan)
  shell              进入 trojan 容器
  status             查看服务状态
  build              构建 Docker 镜像
  backup             备份数据库
  restore <file>     恢复数据库
  update <version>   更新到指定版本
  rollback <version> 回滚到指定版本

示例:
  $0 start
  $0 logs trojan
  $0 backup
  $0 update v1.0.1
  $0 rollback v1.0.0

EOF
}

# 主逻辑
check_env

case "$1" in
    start)      start ;;
    stop)       stop ;;
    restart)    restart ;;
    logs)       logs "$2" ;;
    shell)      shell ;;
    status)     status ;;
    build)      build ;;
    backup)     backup ;;
    restore)    restore "$2" ;;
    update)     update "$2" ;;
    rollback)   rollback "$2" ;;
    *)          usage ;;
esac
