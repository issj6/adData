#!/bin/bash

# 广告数据聚合系统 - 一键部署脚本
# 支持初始化、部署、更新、停止等操作

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_NAME="ad-data-aggregator"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
ENV_EXAMPLE="env.example"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 初始化环境配置
init_env() {
    log_info "初始化环境配置..."
    
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$ENV_EXAMPLE" ]; then
            cp "$ENV_EXAMPLE" "$ENV_FILE"
            log_success "已创建 $ENV_FILE 文件"
            log_warning "请根据实际情况修改 $ENV_FILE 中的数据库配置"
        else
            log_error "$ENV_EXAMPLE 文件不存在"
            exit 1
        fi
    else
        log_info "$ENV_FILE 文件已存在"
    fi
}

# 检查数据库连接
check_database() {
    log_info "检查数据库连接..."
    
    # 读取环境变量
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
    
    # 设置默认值
    TARGET_DB_HOST=${TARGET_DB_HOST:-127.0.0.1}
    TARGET_DB_PORT=${TARGET_DB_PORT:-3306}
    TARGET_DB_USER=${TARGET_DB_USER:-root}
    TARGET_DB_DATABASE=${TARGET_DB_DATABASE:-ad_data}
    
    # 检查MySQL客户端
    if ! command -v mysql &> /dev/null; then
        log_warning "MySQL客户端未安装，跳过数据库连接检查"
        return 0
    fi
    
    # 测试连接
    if mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" -e "SELECT 1;" &> /dev/null; then
        log_success "数据库连接正常"
    else
        log_warning "数据库连接失败，请检查配置"
        log_info "数据库配置: $TARGET_DB_USER@$TARGET_DB_HOST:$TARGET_DB_PORT/$TARGET_DB_DATABASE"
    fi
}

# 初始化数据库
init_database() {
    log_info "初始化数据库..."
    
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
    
    TARGET_DB_HOST=${TARGET_DB_HOST:-127.0.0.1}
    TARGET_DB_PORT=${TARGET_DB_PORT:-3306}
    TARGET_DB_USER=${TARGET_DB_USER:-root}
    TARGET_DB_DATABASE=${TARGET_DB_DATABASE:-ad_data}
    
    if ! command -v mysql &> /dev/null; then
        log_warning "MySQL客户端未安装，请手动执行SQL文件："
        log_info "  1. create_ad_stats_table.sql"
        log_info "  2. create_ad_name_map.sql"
        return 0
    fi
    
    # 创建数据库
    log_info "创建数据库 $TARGET_DB_DATABASE..."
    mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" \
        -e "CREATE DATABASE IF NOT EXISTS $TARGET_DB_DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || {
        log_warning "创建数据库失败，可能已存在或权限不足"
    }
    
    # 执行建表脚本
    if [ -f "create_ad_stats_table.sql" ]; then
        log_info "创建聚合数据表..."
        mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" "$TARGET_DB_DATABASE" < create_ad_stats_table.sql 2>/dev/null || {
            log_warning "创建聚合数据表失败"
        }
    fi
    
    if [ -f "create_ad_name_map.sql" ]; then
        log_info "创建名称映射表..."
        mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" "$TARGET_DB_DATABASE" < create_ad_name_map.sql 2>/dev/null || {
            log_warning "创建名称映射表失败"
        }
    fi
    
    log_success "数据库初始化完成"
}

# 构建镜像
build_image() {
    log_info "构建Docker镜像..."
    docker compose build
    log_success "镜像构建完成"
}

# 启动服务
start_services() {
    log_info "启动服务..."
    docker compose up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    if docker compose ps | grep -q "Up"; then
        log_success "服务启动成功"
        show_status
    else
        log_error "服务启动失败"
        docker compose logs
        exit 1
    fi
}

# 停止服务
stop_services() {
    log_info "停止服务..."
    docker compose down
    log_success "服务已停止"
}

# 重启服务
restart_services() {
    log_info "重启服务..."
    docker compose restart
    log_success "服务已重启"
}

# 查看状态
show_status() {
    log_info "服务状态："
    docker compose ps
    
    echo ""
    log_info "访问地址："
    echo "  Web界面: http://localhost:8080"
    echo "  API接口: http://localhost:8080/api/filter-options"
    
    echo ""
    log_info "常用命令："
    echo "  查看日志: docker compose logs -f"
    echo "  进入容器: docker compose exec ad-data-app bash"
    echo "  手动ETL: docker compose exec ad-data-app /app/run_daily_etl.sh"
}

# 查看日志
show_logs() {
    docker compose logs -f
}

# 更新部署
update_deployment() {
    log_info "更新部署..."
    
    # 拉取最新代码（如果是git仓库）
    if [ -d ".git" ]; then
        log_info "拉取最新代码..."
        git pull
    fi
    
    # 重新构建并启动
    docker compose down
    docker compose up -d --build
    
    log_success "更新完成"
    show_status
}

# 清理资源
cleanup() {
    log_info "清理Docker资源..."
    
    # 停止并删除容器
    docker compose down --volumes --remove-orphans
    
    # 删除镜像（可选）
    read -p "是否删除Docker镜像? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose down --rmi all
        log_success "已删除Docker镜像"
    fi
    
    log_success "清理完成"
}

# 备份数据
backup_data() {
    log_info "备份数据..."
    
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
    
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 备份数据库
    if command -v mysqldump &> /dev/null; then
        TARGET_DB_HOST=${TARGET_DB_HOST:-127.0.0.1}
        TARGET_DB_PORT=${TARGET_DB_PORT:-3306}
        TARGET_DB_USER=${TARGET_DB_USER:-root}
        TARGET_DB_DATABASE=${TARGET_DB_DATABASE:-ad_data}
        
        log_info "备份数据库到 $BACKUP_DIR..."
        mysqldump -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" \
            "$TARGET_DB_DATABASE" > "$BACKUP_DIR/database_backup.sql" 2>/dev/null || {
            log_warning "数据库备份失败"
        }
    fi
    
    # 备份日志
    if [ -d "logs" ]; then
        cp -r logs "$BACKUP_DIR/"
        log_info "已备份日志文件"
    fi
    
    log_success "备份完成: $BACKUP_DIR"
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    # 检查容器状态
    if ! docker compose ps | grep -q "Up"; then
        log_error "容器未运行"
        return 1
    fi
    
    # 检查API接口
    if curl -f -s "http://localhost:8080/api/filter-options" > /dev/null; then
        log_success "API接口正常"
    else
        log_error "API接口异常"
        return 1
    fi
    
    # 检查数据库连接
    check_database
    
    log_success "健康检查通过"
}

# 显示帮助
show_help() {
    echo "广告数据聚合系统 - 部署脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  init        初始化环境（创建.env文件）"
    echo "  init-db     初始化数据库（创建表）"
    echo "  build       构建Docker镜像"
    echo "  start       启动服务"
    echo "  stop        停止服务"
    echo "  restart     重启服务"
    echo "  status      查看服务状态"
    echo "  logs        查看服务日志"
    echo "  update      更新部署"
    echo "  backup      备份数据"
    echo "  cleanup     清理Docker资源"
    echo "  health      健康检查"
    echo "  deploy      完整部署（init + init-db + build + start）"
    echo "  help        显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 deploy     # 完整部署"
    echo "  $0 status     # 查看状态"
    echo "  $0 logs       # 查看日志"
}

# 完整部署
full_deploy() {
    log_info "开始完整部署..."
    
    check_dependencies
    init_env
    init_database
    build_image
    start_services
    
    log_success "部署完成！"
    echo ""
    log_info "接下来您可以："
    echo "  1. 访问 http://localhost:8080 查看Web界面"
    echo "  2. 运行 $0 health 进行健康检查"
    echo "  3. 运行 $0 logs 查看运行日志"
}

# 主函数
main() {
    case "${1:-help}" in
        "init")
            check_dependencies
            init_env
            ;;
        "init-db")
            init_database
            ;;
        "build")
            build_image
            ;;
        "start")
            start_services
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            restart_services
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "update")
            update_deployment
            ;;
        "backup")
            backup_data
            ;;
        "cleanup")
            cleanup
            ;;
        "health")
            health_check
            ;;
        "deploy")
            full_deploy
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# 执行主函数
main "$@"
