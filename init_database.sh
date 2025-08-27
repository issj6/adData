#!/bin/bash

# 数据库初始化脚本
# 在容器启动时自动检查并创建表

set -e

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
}

# 等待数据库连接可用
wait_for_database() {
    log_info "等待数据库连接..."
    
    # 最多等待60秒
    for i in {1..60}; do
        if mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" --skip-ssl -e "SELECT 1;" 2>/dev/null; then
            log_success "数据库连接成功"
            return 0
        fi
        log_info "等待数据库连接... ($i/60)"
        sleep 1
    done
    
    log_error "数据库连接超时"
    return 1
}

# 检查表是否存在
check_table_exists() {
    local table_name=$1
    mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" --skip-ssl "$TARGET_DB_DATABASE" \
        -e "SELECT 1 FROM $table_name LIMIT 1;" &> /dev/null
}

# 初始化数据库
init_database() {
    log_info "开始数据库初始化..."
    
    # 等待数据库可用
    if ! wait_for_database; then
        log_error "数据库不可用，跳过初始化"
        return 1
    fi
    
    # 创建数据库（如果不存在）
    log_info "创建数据库 $TARGET_DB_DATABASE..."
    mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" --skip-ssl \
        -e "CREATE DATABASE IF NOT EXISTS $TARGET_DB_DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || {
        log_warning "创建数据库失败，可能已存在"
    }
    
    # 检查并创建聚合数据表
    if ! check_table_exists "ad_stats_daily"; then
        log_info "创建聚合数据表 ad_stats_daily..."
        if [ -f "/app/create_ad_stats_table.sql" ]; then
            mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" --skip-ssl "$TARGET_DB_DATABASE" < /app/create_ad_stats_table.sql
            log_success "聚合数据表创建成功"
        else
            log_error "SQL文件不存在: create_ad_stats_table.sql"
        fi
    else
        log_info "聚合数据表 ad_stats_daily 已存在"
    fi
    
    # 检查并创建名称映射表
    if ! check_table_exists "ad_name_map"; then
        log_info "创建名称映射表 ad_name_map..."
        if [ -f "/app/create_ad_name_map.sql" ]; then
            mysql -h "$TARGET_DB_HOST" -P "$TARGET_DB_PORT" -u "$TARGET_DB_USER" -p"$TARGET_DB_PASSWORD" --skip-ssl "$TARGET_DB_DATABASE" < /app/create_ad_name_map.sql
            log_success "名称映射表创建成功"
        else
            log_error "SQL文件不存在: create_ad_name_map.sql"
        fi
    else
        log_info "名称映射表 ad_name_map 已存在"
    fi
    
    log_success "数据库初始化完成"
    return 0
}

# 主函数
main() {
    log_info "=== 数据库初始化脚本启动 ==="
    
    # 检查必要的环境变量
    if [ -z "$TARGET_DB_HOST" ] || [ -z "$TARGET_DB_USER" ] || [ -z "$TARGET_DB_PASSWORD" ] || [ -z "$TARGET_DB_DATABASE" ]; then
        log_error "缺少必要的数据库环境变量"
        log_info "需要设置: TARGET_DB_HOST, TARGET_DB_USER, TARGET_DB_PASSWORD, TARGET_DB_DATABASE"
        exit 1
    fi
    
    # 执行初始化
    if init_database; then
        log_success "=== 数据库初始化完成 ==="
        exit 0
    else
        log_error "=== 数据库初始化失败 ==="
        exit 1
    fi
}

# 执行主函数
main "$@"
