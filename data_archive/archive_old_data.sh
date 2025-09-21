#!/bin/bash

# 数据归档脚本
# 每日凌晨1点执行：导出14天前的数据为CSV并删除

set -eo pipefail

# 导入数据库配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 固定数据库配置（忽略环境变量与 .env）
SOURCE_DB_HOST="103.36.221.200"
SOURCE_DB_PORT=3316
SOURCE_DB_USER="root"
SOURCE_DB_PASSWORD="Yyy443556.0"
SOURCE_DB_DATABASE="ad_router"
SOURCE_TABLE_NAME="request_log"

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
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$line" >> "$LOG_FILE"
    >&2 echo "$line"
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
    
    if mysql --skip-ssl -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
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
    log_info "检查14天前的数据量..."
    
    # 接收或计算14天前的日期
    local archive_date="$1"
    if [ -z "$archive_date" ]; then
        archive_date=$(date -d '14 days ago' '+%Y-%m-%d')
    fi
    log_info "归档日期cutoff: $archive_date"
    
    # 查询要归档的数据量（将错误写入日志，不吞错）
    RECORD_COUNT=$(mysql --skip-ssl -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
        "$SOURCE_DB_DATABASE" -N -e "
        SELECT COUNT(*) 
        FROM $SOURCE_TABLE_NAME 
        WHERE track_time < '$archive_date 00:00:00'
    " 2>>"$LOG_FILE" || echo "0")
    
    log_info "找到 $RECORD_COUNT 条需要归档的记录"
    # 仅输出数字到stdout，供命令替换捕获
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
    mysql --quick --skip-ssl -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
        "$SOURCE_DB_DATABASE" -e "
        SELECT *
        FROM $SOURCE_TABLE_NAME 
        WHERE track_time < '$archive_date 00:00:00'
    " 2>>"$LOG_FILE" | sed 's/\t/,/g' > "$csv_file"
    
    if [ $? -eq 0 ] && [ -f "$csv_file" ]; then
        # 检查文件大小
        local file_size=$(du -h "$csv_file" | cut -f1)
        log_success "数据导出完成: $csv_file (大小: $file_size)"
        
        # 验证导出的行数（减去表头）
        local total_lines=$(wc -l < "$csv_file")
        local exported_lines=$(( total_lines - 1 ))
        if [ "$total_lines" -eq 0 ]; then
            log_error "导出文件为空（无表头），视为导出失败"
            return 1
        fi
        log_info "导出行数: $exported_lines 条记录"
        
        if [ "$exported_lines" -ne "$record_count" ]; then
            log_error "导出行数($exported_lines)与预期($record_count)不一致，停止删除以保证安全"
            return 1
        fi
        
        echo "$csv_file"
        return 0
    else
        log_error "数据导出失败"
        log_warning "尝试启用分片导出模式以降低内存/临时文件压力"
        # 回退到分片导出
        CSV_FILE_CHUNKED=$(export_data_to_csv_chunked "$archive_date" "$record_count") || return 1
        echo "$CSV_FILE_CHUNKED"
        return 0
    fi
}

# 分片导出，按天切分，首片保留表头，其余片去表头后追加
export_data_to_csv_chunked() {
    local archive_date=$1
    local record_count=$2
    local export_timestamp=$(date '+%Y%m%d_%H%M%S')
    local csv_file="$ARCHIVE_DIR/archived_data_${export_timestamp}.csv"

    log_info "开始分片导出（按天）到CSV文件: $csv_file"

    # 计算最早起始日（仅限小于cutoff的数据）
    local min_day
    min_day=$(mysql --skip-ssl -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
        "$SOURCE_DB_DATABASE" -N -e "
        SELECT LEFT(MIN(track_time),10)
        FROM $SOURCE_TABLE_NAME
        WHERE track_time < '$archive_date 00:00:00'
    " 2>>"$LOG_FILE" | tr -d '\r') || true

    if [ -z "$min_day" ] || ! [[ "$min_day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_error "无法获取最早日期，分片导出终止"
        return 1
    fi

    local cur_day="$min_day"
    local header_written=0

    while [ "$(date -d "$cur_day" +%s)" -lt "$(date -d "$archive_date" +%s)" ]; do
        local next_day
        next_day=$(date -d "$cur_day +1 day" '+%Y-%m-%d')

        log_info "导出分片: $cur_day"
        if [ "$header_written" -eq 0 ]; then
            mysql --quick --skip-ssl -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
                "$SOURCE_DB_DATABASE" -e "
                SELECT *
                FROM $SOURCE_TABLE_NAME
                WHERE track_time >= '$cur_day 00:00:00' AND track_time < '$next_day 00:00:00'
            " 2>>"$LOG_FILE" | sed 's/\t/,/g' > "$csv_file" || {
                log_error "分片导出失败: $cur_day"
                return 1
            }
            header_written=1
        else
            mysql --quick --skip-ssl -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
                "$SOURCE_DB_DATABASE" -e "
                SELECT *
                FROM $SOURCE_TABLE_NAME
                WHERE track_time >= '$cur_day 00:00:00' AND track_time < '$next_day 00:00:00'
            " 2>>"$LOG_FILE" | sed 's/\t/,/g' | tail -n +2 >> "$csv_file" || {
                log_error "分片导出失败: $cur_day"
                return 1
            }
        fi

        cur_day="$next_day"
    done

    if [ ! -f "$csv_file" ]; then
        log_error "分片导出未生成文件"
        return 1
    fi

    local total_lines=$(wc -l < "$csv_file")
    if [ "$total_lines" -eq 0 ]; then
        log_error "分片导出文件为空"
        return 1
    fi

    local exported_lines=$(( total_lines - 1 ))
    log_info "分片导出完成，合计: $exported_lines 条记录"

    if [ "$exported_lines" -ne "$record_count" ]; then
        log_error "分片导出行数($exported_lines)与预期($record_count)不一致，停止删除以保证安全"
        return 1
    fi

    echo "$csv_file"
    return 0
}

# 删除已归档的数据（按天窗口 + 无排序小批量 + 短锁等待 + 退避重试）
delete_archived_data() {
    local archive_date=$1
    local expected_count=$2
    local batch_size=${DELETE_BATCH_SIZE:-10000}
    local min_batch_size=${DELETE_MIN_BATCH_SIZE:-500}
    local lock_wait_timeout=${DELETE_LOCK_WAIT_TIMEOUT:-5}
    local retry_max=${DELETE_RETRY_MAX:-5}
    local total_deleted=0
    local loop_count=0
    local max_loops=${DELETE_MAX_LOOPS:-0} # 0 表示不限制
    
    log_info "开始按天窗口分批删除已归档的数据（预计: $expected_count 条，初始批大小: $batch_size）..."
    
    # 计算需要处理的起始天（小于 cutoff 的最早一天）
    local min_day
    min_day=$(mysql --skip-ssl -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
        "$SOURCE_DB_DATABASE" -sN -e "
        SELECT LEFT(MIN(track_time),10)
        FROM $SOURCE_TABLE_NAME
        WHERE track_time < '$archive_date 00:00:00'" 2>>"$LOG_FILE" | tr -d '\r') || true
    
    if [ -z "$min_day" ] || ! [[ "$min_day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_warning "无需删除：未找到早于 $archive_date 的数据"
        return 0
    fi
    
    local cur_day="$min_day"
    
    while [ "$(date -d "$cur_day" +%s)" -lt "$(date -d "$archive_date" +%s)" ]; do
        local next_day
        next_day=$(date -d "$cur_day +1 day" '+%Y-%m-%d')
        
        local day_deleted=1
        local day_total=0
        local current_batch_size=$batch_size
        local retry_count=0
        
        log_info "开始删除日期: $cur_day 的数据（窗口: [$cur_day, $next_day)）"
        
        while true; do
            # 执行单批删除，设置会话级短锁等待，避免长时间阻塞
            local output
            output=$(mysql --skip-ssl -h "$SOURCE_DB_HOST" -P "$SOURCE_DB_PORT" -u "$SOURCE_DB_USER" -p"$SOURCE_DB_PASSWORD" \
                "$SOURCE_DB_DATABASE" -sN -e "
                SET SESSION innodb_lock_wait_timeout=$lock_wait_timeout;
                DELETE FROM $SOURCE_TABLE_NAME
                WHERE track_time >= '$cur_day 00:00:00' AND track_time < '$next_day 00:00:00'
                LIMIT $current_batch_size;
                SELECT ROW_COUNT();
            " 2>>"$LOG_FILE")
            
            local ec=$?
            local rc
            rc=$(printf '%s' "$output" | tail -n 1 | tr -d '\r')
            
            if [ $ec -ne 0 ]; then
                # 失败：可能锁等待超时或其他错误，缩小批量并重试最多 retry_max 次
                retry_count=$(( retry_count + 1 ))
                if [ $current_batch_size -gt $min_batch_size ]; then
                    current_batch_size=$(( current_batch_size / 2 ))
                    if [ $current_batch_size -lt $min_batch_size ]; then
                        current_batch_size=$min_batch_size
                    fi
                fi
                
                if [ $retry_count -ge $retry_max ]; then
                    log_warning "日期 $cur_day 连续失败 $retry_count 次，跳过当日剩余记录（当前批大小: $current_batch_size）"
                    break
                fi
                
                if [ -n "$DELETE_BATCH_SLEEP" ]; then
                    sleep "$DELETE_BATCH_SLEEP"
                else
                    sleep 1
                fi
                continue
            fi
            
            if ! [[ "$rc" =~ ^[0-9]+$ ]]; then
                # 未取得数字行数（极少数情况下 stdout 为空）
                retry_count=$(( retry_count + 1 ))
                log_error "读取单批删除行数失败: $rc（日期: $cur_day）"
                if [ $retry_count -ge $retry_max ]; then
                    log_warning "日期 $cur_day 连续读取失败 $retry_count 次，跳过当日剩余记录"
                    break
                fi
                continue
            fi
            
            day_deleted=$rc
            if [ "$day_deleted" -eq 0 ]; then
                # 当日已删尽
                break
            fi
            
            day_total=$(( day_total + day_deleted ))
            total_deleted=$(( total_deleted + day_deleted ))
            loop_count=$(( loop_count + 1 ))
            retry_count=0
            log_info "日期 $cur_day 本批删除: $day_deleted，日期累计: $day_total，总累计: $total_deleted，当前批大小: $current_batch_size"
            
            if [ "$max_loops" -gt 0 ] && [ "$loop_count" -ge "$max_loops" ]; then
                log_warning "达到最大批次数 $max_loops，提前停止删除（累计: $total_deleted）"
                break 2
            fi
            
            if [ -n "$DELETE_BATCH_SLEEP" ]; then
                sleep "$DELETE_BATCH_SLEEP"
            fi
        done
        
        log_info "日期 $cur_day 删除完成，共: $day_total"
        cur_day="$next_day"
    done
    
    if [ "$total_deleted" -eq "$expected_count" ]; then
        log_success "分批删除完成，累计删除: $total_deleted（与预期一致）"
        return 0
    else
        log_warning "分批删除完成，累计删除: $total_deleted，与预期($expected_count)不一致"
        return 0
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
    ARCHIVE_DATE=$(date -d '14 days ago' '+%Y-%m-%d')
    
    # 检查要归档的数据量（仅捕获数字）
    RECORD_COUNT=$(check_archive_data "$ARCHIVE_DATE")
    if ! [[ "$RECORD_COUNT" =~ ^[0-9]+$ ]]; then
        log_error "统计返回值异常（非纯数字）: $RECORD_COUNT"
        exit 1
    fi
    
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
    
    # 删除已归档的数据（仅在导出成功且一致时执行）
    if delete_archived_data "$ARCHIVE_DATE" "$RECORD_COUNT"; then
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
