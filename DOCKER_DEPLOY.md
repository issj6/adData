# Docker 部署指南

## 📋 部署概述

本项目支持完整的Docker化部署，包括：
- ✅ Flask Web应用
- ✅ 定时ETL任务（每天凌晨3点执行）
- ✅ 环境变量配置
- ✅ 健康检查
- ✅ 日志持久化

## 🚀 快速部署

### 1. 准备环境变量文件

```bash
# 复制环境变量模板
cp env.example .env

# 根据实际情况修改 .env 文件中的数据库配置
vim .env
```

### 2. 启动服务

```bash
# 构建并启动服务
docker compose up -d

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f ad-data-app
```

### 3. 验证部署

```bash
# 检查Web界面
curl http://localhost:8080

# 检查API接口
curl http://localhost:8080/api/filter-options

# 检查健康状态
docker compose exec ad-data-app curl -f http://localhost:8080/api/filter-options
```

## 🗄️ 数据库初始化

### 创建数据库和表

```bash
# 如果目标数据库不存在，需要先创建
mysql -h YOUR_DB_HOST -u YOUR_DB_USER -p -e "CREATE DATABASE IF NOT EXISTS ad_data CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# 创建聚合表
mysql -h YOUR_DB_HOST -u YOUR_DB_USER -p ad_data < create_ad_stats_table.sql

# 创建映射表
mysql -h YOUR_DB_HOST -u YOUR_DB_USER -p ad_data < create_ad_name_map.sql
```

## ⚙️ 环境变量说明

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `SOURCE_DB_HOST` | 源数据库主机 | 222.186.41.7 |
| `SOURCE_DB_PORT` | 源数据库端口 | 3316 |
| `SOURCE_DB_USER` | 源数据库用户 | root |
| `SOURCE_DB_PASSWORD` | 源数据库密码 | - |
| `TARGET_DB_HOST` | 目标数据库主机 | host.docker.internal |
| `TARGET_DB_PORT` | 目标数据库端口 | 3306 |
| `TARGET_DB_USER` | 目标数据库用户 | root |
| `TARGET_DB_PASSWORD` | 目标数据库密码 | - |

## 🕐 定时任务

- **执行时间**: 每天凌晨 3:00
- **任务内容**: 执行ETL脚本处理前一天数据
- **回滚窗口**: 7天（处理迟到回调）
- **日志位置**: `/app/logs/daily_etl_YYYYMMDD.log`

### 手动执行ETL

```bash
# 进入容器执行ETL
docker compose exec ad-data-app /app/run_daily_etl.sh

# 或者执行特定日期的ETL
docker compose exec ad-data-app python /app/ad_stats_etl.py --date 2025-08-27
```

## 📊 监控和日志

### 查看应用日志

```bash
# 查看容器日志
docker compose logs -f ad-data-app

# 查看ETL任务日志
docker compose exec ad-data-app tail -f /app/logs/daily_etl_$(date +%Y%m%d).log
```

### 健康检查

```bash
# 检查容器健康状态
docker compose ps

# 手动健康检查
curl -f http://localhost:8080/api/filter-options
```

## 🔧 运维操作

### 重启服务

```bash
# 重启服务
docker compose restart ad-data-app

# 重新构建并启动
docker compose up -d --build
```

### 更新部署

```bash
# 拉取最新代码
git pull

# 重新构建并部署
docker compose down
docker compose up -d --build
```

### 数据备份

```bash
# 导出聚合数据
docker compose exec ad-data-app mysqldump -h $TARGET_DB_HOST -u $TARGET_DB_USER -p$TARGET_DB_PASSWORD ad_data > backup_$(date +%Y%m%d).sql

# 导出映射数据
docker compose exec ad-data-app mysqldump -h $TARGET_DB_HOST -u $TARGET_DB_USER -p$TARGET_DB_PASSWORD ad_data ad_name_map > mapping_backup_$(date +%Y%m%d).sql
```

## 🛠️ 故障排除

### 容器无法启动

```bash
# 检查日志
docker compose logs ad-data-app

# 检查环境变量
docker compose config

# 检查端口占用
netstat -tlnp | grep 8080
```

### 数据库连接失败

```bash
# 测试数据库连接
docker compose exec ad-data-app mysql -h $TARGET_DB_HOST -u $TARGET_DB_USER -p$TARGET_DB_PASSWORD -e "SELECT 1"

# 检查网络连通性
docker compose exec ad-data-app ping $TARGET_DB_HOST
```

### ETL任务失败

```bash
# 查看ETL日志
docker compose exec ad-data-app cat /app/logs/daily_etl_$(date +%Y%m%d).log

# 手动测试ETL
docker compose exec ad-data-app python /app/ad_stats_etl.py --test
```

## 📈 性能调优

### 资源限制

```yaml
# 在 docker-compose.yml 中添加资源限制
services:
  ad-data-app:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M
```

### 日志轮转

```bash
# 清理过期日志（保留30天）
docker compose exec ad-data-app find /app/logs -name "*.log" -mtime +30 -delete
```

## 🔒 安全建议

1. **环境变量**: 生产环境中使用强密码
2. **网络访问**: 限制数据库访问IP
3. **定期更新**: 及时更新基础镜像
4. **日志审计**: 定期检查ETL执行日志

---

**部署状态**: ✅ **已就绪，可投入生产使用**
