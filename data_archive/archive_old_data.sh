#!/bin/bash

# 数据归档脚本
# 每日凌晨1点执行：导出30天前的数据为CSV并删除

set -e

# 导入数据库配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 导入环境变量（如果存在.env文件）
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

# 设置默认值
SOURCE_DB_HOST=${SOURCE_DB_HOST:-"222.186.41.7"}
SOURCE_DB_PORT=${SOURCE_DB_PORT:-3316}
SOURCE_DB_USER=${SOURCE_DB_USER:-"root"}
SOURCE_DB_PASSWORD=${SOURCE_DB_PASSWORD:-"Yyy443556.0"}
SOURCE_DB_DATABASE=${SOURCE_DB_DATABASE:-"ad_router"}
SOURCE_TABLE_NAME=${SOURCE_TABLE_NAME:-"request_log"}

# 确保在cron环境下能找到系统命令
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# 创建归档目录
ARCHIVE_DIR="$SCRIPT_DIR/archives"
mkdir -p "$ARCHIVE_DIR"

# 设置日志文件
LOG_FILE="$SCRIPT_DIR/logs/archive_$(date '+%Y%m%d').log"
mkdir -p "$SCRIPT_DIR/logs"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "[INFO] $1"
}

log_success() {
    log "[SUCCESS] $1"
}

log_error() {
    log "[ERROR] $1"
}

log_warning() {
    log "[WARNING] $1"
}

# 检查数据库连接
check_database_connection() {
    log_info "检查源数据库连接..."
    
    if mysql -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
        -e "SELECT 1;" &> /dev/null; then
        log_success "数据库连接正常"
        return 0
    else
        log_error "数据库连接失败"
        return 1
    fi
}

# 检查要归档的数据量
check_archive_data() {
    log_info "检查30天前的数据量..."
    
    # 计算30天前的日期
    ARCHIVE_DATE=$(date -d '30 days ago' '+%Y-%m-%d')
    log_info "归档日期cutoff: $ARCHIVE_DATE"
    
    # 查询要归档的数据量
    RECORD_COUNT=$(mysql -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
        "$SOURCE_DB_DATABASE" -N -e "
        SELECT COUNT(*) 
        FROM $SOURCE_TABLE_NAME 
        WHERE DATE(track_time) < '$ARCHIVE_DATE'
    " 2>/dev/null || echo "0")
    
    log_info "找到 $RECORD_COUNT 条需要归档的记录"
    echo "$RECORD_COUNT"
}

# 导出数据为CSV
export_data_to_csv() {
    local archive_date=$1
    local record_count=$2
    
    # 生成CSV文件名（以导出时间命名）
    local export_timestamp=$(date '+%Y%m%d_%H%M%S')
    local csv_file="$ARCHIVE_DIR/archived_data_${export_timestamp}.csv"
    
    log_info "开始导出数据到CSV文件: $csv_file"
    
    # 导出数据（包含表头）
    mysql -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
        "$SOURCE_DB_DATABASE" -e "
        SELECT *
        FROM $SOURCE_TABLE_NAME 
        WHERE DATE(track_time) < '$archive_date'
        ORDER BY track_time
    " | sed 's/\t/,/g' > "$csv_file"
    
    if [ $? -eq 0 ] && [ -f "$csv_file" ]; then
        # 检查文件大小
        local file_size=$(du -h "$csv_file" | cut -f1)
        log_success "数据导出完成: $csv_file (大小: $file_size)"
        
        # 验证导出的行数（减去表头）
        local exported_lines=$(($(wc -l < "$csv_file") - 1))
        log_info "导出行数: $exported_lines 条记录"
        
        if [ "$exported_lines" -ne "$record_count" ]; then
            log_warning "导出行数($exported_lines)与预期($record_count)不匹配"
        fi
        
        echo "$csv_file"
        return 0
    else
        log_error "数据导出失败"
        return 1
    fi
}

# 删除已归档的数据
delete_archived_data() {
    local archive_date=$1
    
    log_info "开始删除已归档的数据..."
    
    # 执行删除操作
    mysql -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
        "$SOURCE_DB_DATABASE" -e "
        DELETE FROM $SOURCE_TABLE_NAME 
        WHERE DATE(track_time) < '$archive_date'
    "
    
    if [ $? -eq 0 ]; then
        # 获取删除的行数
        local deleted_count=$(mysql -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
            "$SOURCE_DB_DATABASE" -e "SELECT ROW_COUNT();" -N 2>/dev/null || echo "未知")
        
        log_success "数据删除完成，删除了 $deleted_count 条记录"
        return 0
    else
        log_error "数据删除失败"
        return 1
    fi
}

# 清理过期的归档文件和日志
cleanup_old_files() {
    log_info "清理过期文件..."
    
    # 清理90天前的归档文件
    find "$ARCHIVE_DIR" -name "archived_data_*.csv" -mtime +90 -delete 2>/dev/null || true
    
    # 清理30天前的日志文件
    find "$SCRIPT_DIR/logs" -name "archive_*.log" -mtime +30 -delete 2>/dev/null || true
    
    log_success "过期文件清理完成"
}

# 生成归档报告
generate_report() {
    local csv_file=$1
    local record_count=$2
    local archive_date=$3
    
    local report_file="$SCRIPT_DIR/logs/archive_report_$(date '+%Y%m%d').txt"
    
    cat > "$report_file" << EOF
===== 数据归档报告 =====
执行时间: $(date '+%Y-%m-%d %H:%M:%S')
归档日期范围: < $archive_date
归档记录数: $record_count
导出文件: $csv_file
文件大小: $(du -h "$csv_file" 2>/dev/null | cut -f1 || echo "未知")

数据库信息:
- 主机: $SOURCE_DB_HOST:$SOURCE_DB_PORT
- 数据库: $SOURCE_DB_DATABASE
- 表名: $SOURCE_TABLE_NAME

执行状态: 成功
========================
EOF
    
    log_info "归档报告已生成: $report_file"
}

# 主函数
main() {
    log_info "===== 数据归档任务开始 ====="
    
    # 检查数据库连接
    if ! check_database_connection; then
        log_error "数据库连接失败，任务终止"
        exit 1
    fi
    
    # 计算归档日期
    ARCHIVE_DATE=$(date -d '30 days ago' '+%Y-%m-%d')
    
    # 检查要归档的数据量
    RECORD_COUNT=$(check_archive_data)
    
    if [ "$RECORD_COUNT" -eq 0 ]; then
        log_info "没有需要归档的数据，任务结束"
        cleanup_old_files
        exit 0
    fi
    
    log_info "开始归档 $RECORD_COUNT 条记录（日期 < $ARCHIVE_DATE）"
    
    # 导出数据
    CSV_FILE=$(export_data_to_csv "$ARCHIVE_DATE" "$RECORD_COUNT")
    if [ $? -ne 0 ]; then
        log_error "数据导出失败，任务终止"
        exit 1
    fi
    
    # 删除已归档的数据
    if delete_archived_data "$ARCHIVE_DATE"; then
        log_success "数据归档任务完成"
        
        # 生成报告
        generate_report "$CSV_FILE" "$RECORD_COUNT" "$ARCHIVE_DATE"
        
        # 清理过期文件
        cleanup_old_files
        
        log_info "===== 数据归档任务结束 ====="
        exit 0
    else
        log_error "数据删除失败，但CSV文件已导出: $CSV_FILE"
        log_warning "请手动检查并处理数据删除"
        exit 1
    fi
}

# 执行主函数
main "$@"
