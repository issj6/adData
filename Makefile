# 广告数据聚合系统 Makefile
# 提供常用的部署和管理命令

.PHONY: help init deploy start stop restart status logs build clean backup health update

# 默认目标
help:
	@echo "广告数据聚合系统 - 可用命令:"
	@echo ""
	@echo "  make deploy     完整部署 (推荐首次使用)"
	@echo "  make init       初始化环境配置"
	@echo "  make build      构建Docker镜像"
	@echo "  make start      启动服务"
	@echo "  make stop       停止服务"
	@echo "  make restart    重启服务"
	@echo "  make status     查看服务状态"
	@echo "  make logs       查看服务日志"
	@echo "  make health     健康检查"
	@echo "  make update     更新部署"
	@echo "  make backup     备份数据"
	@echo "  make clean      清理Docker资源"
	@echo ""

# 完整部署
deploy:
	@echo "🚀 开始完整部署..."
	./deploy.sh deploy

# 初始化环境
init:
	@echo "⚙️ 初始化环境..."
	./deploy.sh init

# 构建镜像
build:
	@echo "🔨 构建Docker镜像..."
	./deploy.sh build

# 启动服务
start:
	@echo "▶️ 启动服务..."
	./deploy.sh start

# 停止服务
stop:
	@echo "⏹️ 停止服务..."
	./deploy.sh stop

# 重启服务
restart:
	@echo "🔄 重启服务..."
	./deploy.sh restart

# 查看状态
status:
	@echo "📊 查看服务状态..."
	./deploy.sh status

# 查看日志
logs:
	@echo "📋 查看服务日志..."
	./deploy.sh logs

# 健康检查
health:
	@echo "🏥 执行健康检查..."
	./deploy.sh health

# 更新部署
update:
	@echo "⬆️ 更新部署..."
	./deploy.sh update

# 备份数据
backup:
	@echo "💾 备份数据..."
	./deploy.sh backup

# 清理资源
clean:
	@echo "🧹 清理Docker资源..."
	./deploy.sh cleanup

# 快速启动开发环境
dev:
	@echo "🔧 启动开发环境..."
	docker compose up --build

# 查看容器信息
ps:
	@echo "📋 容器状态:"
	docker compose ps

# 进入容器
shell:
	@echo "🐚 进入应用容器..."
	docker compose exec ad-data-app bash

# 手动执行ETL
etl:
	@echo "⚡ 手动执行ETL任务..."
	docker compose exec ad-data-app /app/run_daily_etl.sh

# 查看ETL日志
etl-logs:
	@echo "📋 查看ETL日志..."
	docker compose exec ad-data-app tail -f /app/logs/daily_etl_$$(date +%Y%m%d).log

# 重建并重启
rebuild:
	@echo "🔄 重建并重启..."
	docker compose down
	docker compose up -d --build
