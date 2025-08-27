# 广告数据聚合系统 Dockerfile
FROM python:3.11-slim

# 设置工作目录
WORKDIR /app

# 配置阿里云Debian源
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    cron \
    default-mysql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 复制requirements文件
COPY requirements.txt .
COPY frontend/requirements.txt frontend_requirements.txt

# 安装Python依赖
RUN pip install --no-cache-dir -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/
RUN pip install --no-cache-dir -r frontend_requirements.txt -i https://mirrors.aliyun.com/pypi/simple/

# 复制应用代码
COPY . .

# 创建日志目录
RUN mkdir -p /app/logs

# 设置脚本执行权限
RUN chmod +x /app/run_daily_etl.sh /app/init_database.sh /app/data_archive/archive_old_data.sh

# 设置定时任务
RUN echo "0 1 * * * /app/data_archive/archive_old_data.sh" > /tmp/crontab && \
    echo "0 3 * * * /app/run_daily_etl.sh" >> /tmp/crontab && \
    crontab /tmp/crontab && \
    rm /tmp/crontab

# 创建启动脚本
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# 初始化数据库\n\
echo "正在初始化数据库..."\n\
/app/init_database.sh || echo "数据库初始化失败，但继续启动服务"\n\
\n\
# 启动cron服务\n\
service cron start\n\
\n\
# 启动Flask应用\n\
cd /app/frontend\n\
exec python app.py' > /app/start.sh && chmod +x /app/start.sh

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/api/filter-options || exit 1

# 启动应用
CMD ["/app/start.sh"]
