#!/bin/bash

# 广告数据ETL定时任务脚本
# 每天凌晨3点执行，处理前一天的数据

# 设置脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 设置日志文件
LOG_FILE="$SCRIPT_DIR/logs/daily_etl_$(date '+%Y%m%d').log"
mkdir -p "$SCRIPT_DIR/logs"

# 确保在cron环境下也能找到python3
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== 开始执行定时ETL任务 ==="

# 检查Python环境
if ! command -v python3 &> /dev/null; then
    log "ERROR: Python3 未找到"
    exit 1
fi

# 检查必要文件
if [ ! -f "$SCRIPT_DIR/ad_stats_etl.py" ]; then
    log "ERROR: ad_stats_etl.py 文件未找到"
    exit 1
fi

# 执行ETL任务（默认处理昨天的数据）
log "开始执行ETL任务..."
python3 "$SCRIPT_DIR/ad_stats_etl.py" --rollback-days 7 >> "$LOG_FILE" 2>&1

# 检查执行结果
if [ $? -eq 0 ]; then
    log "ETL任务执行成功"
    
    # 清理过期日志文件（保留最近30天）
    find "$SCRIPT_DIR/logs" -name "daily_etl_*.log" -mtime +30 -delete 2>/dev/null
    log "清理过期日志完成"
    
    exit 0
else
    log "ERROR: ETL任务执行失败"
    exit 1
fi
