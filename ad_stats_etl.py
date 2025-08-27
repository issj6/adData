#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
广告数据ETL脚本（最小工程版本）
按track_time归因，支持滚动重算窗口处理迟到回调
"""

import pymysql
from datetime import datetime, timedelta
import argparse
import logging
import sys

from db_config import SOURCE_DB_CONFIG, TARGET_DB_CONFIG, SOURCE_TABLE_NAME

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('ad_stats_etl.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

def connect_database(config):
    """连接数据库"""
    return pymysql.connect(**config, cursorclass=pymysql.cursors.DictCursor, ssl_disabled=True)

def process_daily_aggregation(target_date: str, rollback_days: int = 7):
    """
    处理日级聚合
    
    Args:
        target_date: 目标日期 (YYYY-MM-DD)
        rollback_days: 回滚重算天数，处理迟到回调
    """
    
    logger.info(f"🔄 开始处理日级聚合: {target_date} (回滚{rollback_days}天)")
    
    # 计算需要重算的日期范围
    target_dt = datetime.strptime(target_date, '%Y-%m-%d')
    start_date = (target_dt - timedelta(days=rollback_days-1)).strftime('%Y-%m-%d')
    end_date = target_date
    
    logger.info(f"📅 重算日期范围: {start_date} 至 {end_date}")
    
    source_conn = connect_database(SOURCE_DB_CONFIG)
    target_conn = connect_database(TARGET_DB_CONFIG)
    
    try:
        # 删除重算窗口内的旧数据
        target_cursor = target_conn.cursor()
        delete_sql = """
            DELETE FROM ad_stats_daily 
            WHERE date_day >= %s AND date_day <= %s
        """
        target_cursor.execute(delete_sql, (start_date, end_date))
        deleted_rows = target_cursor.rowcount
        logger.info(f"🗑️ 删除旧数据: {deleted_rows} 行")
        
        # 从源表聚合数据（按track_time归因）
        source_cursor = source_conn.cursor()
        
        aggregation_sql = f"""
            SELECT
                DATE(track_time) as date_day,
                up_id,
                ds_id,
                ad_id,
                channel_id,
                os,
                is_callback_sent,
                callback_event_type,
                COUNT(*) as request_count,
                SUM(CASE WHEN is_callback_sent = 1 THEN 1 ELSE 0 END) as callback_count
            FROM {SOURCE_TABLE_NAME}
            WHERE DATE(track_time) >= %s AND DATE(track_time) <= %s
            GROUP BY
                DATE(track_time),
                up_id,
                ds_id,
                ad_id,
                channel_id,
                os,
                is_callback_sent,
                callback_event_type
            ORDER BY date_day, ds_id, ad_id, is_callback_sent
        """
        
        logger.info("📊 开始从源表聚合数据...")
        source_cursor.execute(aggregation_sql, (start_date, end_date))
        aggregated_data = source_cursor.fetchall()
        
        if not aggregated_data:
            logger.warning("⚠️ 未找到需要聚合的数据")
            return True
        
        logger.info(f"📊 聚合完成: {len(aggregated_data)} 条记录")
        
        # 批量插入聚合数据
        insert_sql = """
            INSERT INTO ad_stats_daily 
            (date_day, up_id, ds_id, ad_id, channel_id, os, is_callback_sent, callback_event_type, request_count, callback_count)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """
        
        batch_data = []
        for row in aggregated_data:
            batch_data.append((
                row['date_day'],
                row['up_id'],
                row['ds_id'],
                row['ad_id'],
                row['channel_id'],
                row['os'],
                row['is_callback_sent'],
                row['callback_event_type'],
                row['request_count'],
                row['callback_count']
            ))
        
        # 分批插入
        batch_size = 1000
        inserted_count = 0
        
        for i in range(0, len(batch_data), batch_size):
            batch = batch_data[i:i + batch_size]
            target_cursor.executemany(insert_sql, batch)
            inserted_count += len(batch)
            
            if i % (batch_size * 10) == 0:
                target_conn.commit()
                logger.info(f"📥 已插入 {inserted_count} / {len(batch_data)} 条记录")
        
        target_conn.commit()
        logger.info(f"✅ 聚合数据插入完成: {inserted_count} 条记录")
        
        # 数据验证
        target_cursor.execute("""
            SELECT 
                COUNT(*) as total_rows,
                SUM(request_count) as total_requests,
                SUM(callback_count) as total_callbacks,
                MIN(date_day) as min_date,
                MAX(date_day) as max_date
            FROM ad_stats_daily 
            WHERE date_day >= %s AND date_day <= %s
        """, (start_date, end_date))
        
        validation = target_cursor.fetchone()
        logger.info(f"📊 数据验证 - 总行数: {validation['total_rows']}, "
                   f"总请求: {validation['total_requests']}, "
                   f"总回调: {validation['total_callbacks']}, "
                   f"日期范围: {validation['min_date']} ~ {validation['max_date']}")
        
        return True
        
    except Exception as e:
        logger.error(f"❌ ETL处理失败: {e}")
        target_conn.rollback()
        return False
        
    finally:
        if 'source_cursor' in locals():
            source_cursor.close()
        if 'target_cursor' in locals():
            target_cursor.close()
        source_conn.close()
        target_conn.close()
        logger.info("🔐 数据库连接已关闭")

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='广告数据ETL处理（最小工程版本）')
    parser.add_argument('--date', type=str, help='目标日期 (YYYY-MM-DD)，默认为昨天')
    parser.add_argument('--rollback-days', type=int, default=7, 
                       help='回滚重算天数，用于处理迟到回调 (默认: 7天)')
    parser.add_argument('--test', action='store_true', help='测试模式（不执行实际ETL）')
    
    args = parser.parse_args()
    
    # 确定目标日期
    if args.date:
        target_date = args.date
        # 验证日期格式
        try:
            datetime.strptime(target_date, '%Y-%m-%d')
        except ValueError:
            logger.error("❌ 日期格式错误，请使用 YYYY-MM-DD 格式")
            sys.exit(1)
    else:
        # 默认处理昨天的数据
        target_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
    
    logger.info(f"🚀 启动广告数据ETL任务")
    logger.info(f"📅 目标日期: {target_date}")
    logger.info(f"🔄 回滚天数: {args.rollback_days}")
    
    if args.test:
        logger.info("🧪 测试模式，跳过实际ETL执行")
        logger.info("✅ 测试完成")
        return
    
    # 执行ETL
    success = process_daily_aggregation(target_date, args.rollback_days)
    
    if success:
        logger.info("🎉 ETL任务执行成功!")
        sys.exit(0)
    else:
        logger.error("💥 ETL任务执行失败!")
        sys.exit(1)

if __name__ == "__main__":
    main()
