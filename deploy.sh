#!/bin/bash

# 广告数据聚合系统 - 简化部署脚本
# 支持部署和停止操作

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查Docker依赖
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
}

# 检查环境配置文件
check_env() {
    if [ ! -f ".env" ]; then
        if [ -f "env.example" ]; then
            log_info "创建 .env 配置文件..."
            cp env.example .env
            log_error "请先编辑 .env 文件配置数据库连接信息，然后重新运行部署"
            log_info "编辑命令: vim .env"
            exit 1
        else
            log_error "缺少环境配置文件，请检查 env.example 是否存在"
            exit 1
        fi
    fi
}

# 检查并创建归档目录
check_archive_directories() {
    log_info "检查归档目录..."
    
    # 检查归档目录是否存在
    if [ ! -d "/data/ad/archives" ] || [ ! -d "/data/ad/logs" ]; then
        log_info "创建归档目录..."
        
        # 尝试创建目录
        if sudo mkdir -p /data/ad/archives /data/ad/logs 2>/dev/null; then
            # 设置权限让Docker容器可以写入
            if sudo chown -R 1000:1000 /data/ad 2>/dev/null; then
                log_success "归档目录创建成功: /data/ad/"
            else
                log_error "无法设置归档目录权限，请手动执行: sudo chown -R 1000:1000 /data/ad"
                exit 1
            fi
        else
            log_error "无法创建归档目录，请手动执行:"
            log_error "  sudo mkdir -p /data/ad/archives /data/ad/logs"
            log_error "  sudo chown -R 1000:1000 /data/ad"
            exit 1
        fi
    else
        log_success "归档目录已存在: /data/ad/"
    fi
}

# 部署服务
deploy() {
    log_info "开始部署广告数据聚合系统..."
    
    # 检查依赖
    check_docker
    check_env
    check_archive_directories
    
    # 构建并启动服务
    log_info "构建Docker镜像..."
    docker compose build
    
    log_info "启动服务..."
    docker compose up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    if docker compose ps | grep -q "Up"; then
        log_success "部署成功！"
        echo ""
        log_info "访问地址:"
        echo "  Web界面: http://localhost:3300"
        echo "  API接口: http://localhost:3300/api/filter-options"
        echo ""
        log_info "常用命令:"
        echo "  查看日志: docker compose logs -f"
        echo "  停止服务: ./deploy.sh stop"
        echo ""
        log_info "归档目录:"
        echo "  CSV文件: /data/ad/archives/"
        echo "  日志文件: /data/ad/logs/"
    else
        log_error "服务启动失败，查看日志："
        docker compose logs
        exit 1
    fi
}

# 停止服务
stop() {
    log_info "停止广告数据聚合系统..."
    docker compose down
    log_success "服务已停止"
}

# 执行首次数据聚合
init_data() {
    log_info "执行首次数据聚合..."
    
    # 检查容器是否运行
    if ! docker compose ps | grep -q "Up"; then
        log_error "服务未运行，请先执行 ./deploy.sh 启动服务"
        exit 1
    fi
    
    # 执行ETL任务
    log_info "开始数据聚合，这可能需要几分钟时间..."
    if docker compose exec ad-data-app /app/run_daily_etl.sh; then
        log_success "首次数据聚合完成！"
        log_info "现在可以访问 Web界面查看数据"
        log_info "Web界面: http://localhost:3300"
    else
        log_error "数据聚合失败，请检查日志："
        log_info "查看日志: docker compose logs -f ad-data-app"
        exit 1
    fi
}

# 显示帮助
show_help() {
    echo "广告数据聚合系统 - 部署脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  (无参数)    部署系统"
    echo "  stop        停止服务"
    echo "  init-data   执行首次数据聚合"
    echo "  help        显示帮助"
    echo ""
    echo "首次使用步骤:"
    echo "  1. ./deploy.sh           # 会自动创建 .env 文件"
    echo "  2. vim .env              # 编辑数据库配置"
    echo "  3. ./deploy.sh           # 部署系统（自动创建表）"
    echo "  4. ./deploy.sh init-data # 执行首次数据聚合"
    echo ""
}

# 主函数
main() {
    case "${1:-deploy}" in
        "stop")
            stop
            ;;
        "init-data")
            init_data
            ;;
        "help")
            show_help
            ;;
        "deploy"|"")
            deploy
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"