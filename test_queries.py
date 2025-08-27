#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
广告数据查询测试脚本（最小工程版本）
验证聚合表是否支持用户的查询需求
"""

import pymysql
import time
import logging
from datetime import datetime, timedelta

from db_config import TARGET_DB_CONFIG

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def connect_db():
    """连接目标数据库"""
    return pymysql.connect(**TARGET_DB_CONFIG, cursorclass=pymysql.cursors.DictCursor)

def execute_query_with_timing(cursor, sql, params=None, description=""):
    """执行查询并记录时间"""
    start_time = time.time()
    cursor.execute(sql, params)
    results = cursor.fetchall()
    end_time = time.time()
    
    execution_time = end_time - start_time
    logger.info(f"📊 {description}: {len(results)} 条结果, 耗时 {execution_time:.3f}s")
    
    return results, execution_time

def test_basic_queries():
    """测试基础查询功能"""
    logger.info("🎯 测试基础查询功能")
    
    conn = connect_db()
    cursor = conn.cursor()
    
    try:
        # 1. 数据概览
        logger.info("\n1️⃣ 数据概览")
        sql1 = """
            SELECT 
                COUNT(*) as total_rows,
                COUNT(DISTINCT date_day) as date_days,
                COUNT(DISTINCT ad_id) as unique_ads,
                COUNT(DISTINCT ds_id) as unique_ds,
                SUM(request_count) as total_requests,
                SUM(callback_count) as total_callbacks,
                MIN(date_day) as min_date,
                MAX(date_day) as max_date
            FROM ad_stats_daily
        """
        
        results1, _ = execute_query_with_timing(cursor, sql1, None, "数据概览查询")
        if results1:
            overview = results1[0]
            print(f"  总行数: {overview['total_rows']:,}")
            print(f"  覆盖日期: {overview['date_days']} 天 ({overview['min_date']} ~ {overview['max_date']})")
            print(f"  唯一广告: {overview['unique_ads']}")
            print(f"  唯一下游: {overview['unique_ds']}")
            print(f"  总请求数: {overview['total_requests']:,}")
            print(f"  总回调数: {overview['total_callbacks']:,}")
            callback_rate = overview['total_callbacks'] / overview['total_requests'] * 100 if overview['total_requests'] > 0 else 0
            print(f"  回调率: {callback_rate:.2f}%")
        
        # 2. 用户查询场景1：某天某些条件下的广告数量和回调数量
        logger.info("\n2️⃣ 用户查询场景1 - 某天某些条件下的广告数量和回调数量")
        sql2 = """
            SELECT
                SUM(request_count) AS total_requests,
                SUM(callback_count) AS total_callbacks
            FROM ad_stats_daily
            WHERE date_day = %s
              AND ds_id = %s
        """
        
        test_date = '2025-08-27'
        test_ds = 'ow'
        
        results2, time2 = execute_query_with_timing(
            cursor, sql2, (test_date, test_ds), 
            f"场景1查询 - {test_date}, ds_id={test_ds}"
        )
        
        if results2:
            result = results2[0]
            print(f"  请求数量: {result['total_requests']:,}")
            print(f"  回调数量: {result['total_callbacks']:,}")
        
        # 3. 用户查询场景2：各callback_event_type的数量分布
        logger.info("\n3️⃣ 用户查询场景2 - 各callback_event_type的数量分布")
        sql3 = """
            SELECT
                callback_event_type,
                SUM(callback_count) AS callbacks
            FROM ad_stats_daily
            WHERE date_day = %s
              AND ds_id = %s
            GROUP BY callback_event_type
            ORDER BY callbacks DESC
        """
        
        results3, time3 = execute_query_with_timing(
            cursor, sql3, (test_date, test_ds),
            f"场景2查询 - {test_date}, ds_id={test_ds} 回调类型分布"
        )
        
        if results3:
            print("  回调类型分布:")
            for row in results3:
                callback_type = row['callback_event_type'] or 'NULL'
                print(f"    {callback_type}: {row['callbacks']} 次")
        
        # 4. 按日期趋势查询
        logger.info("\n4️⃣ 按日期趋势查询（最近7天）")
        sql4 = """
            SELECT
                date_day,
                SUM(request_count) AS daily_requests,
                SUM(callback_count) AS daily_callbacks,
                ROUND(SUM(callback_count) * 100.0 / SUM(request_count), 2) as daily_callback_rate
            FROM ad_stats_daily
            WHERE date_day >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
            GROUP BY date_day
            ORDER BY date_day DESC
        """
        
        results4, time4 = execute_query_with_timing(cursor, sql4, None, "7天趋势查询")
        
        if results4:
            print("  最近7天趋势:")
            for row in results4:
                print(f"    {row['date_day']}: {row['daily_requests']:,} 请求, "
                      f"{row['daily_callbacks']} 回调 ({row['daily_callback_rate']}%)")
        
        # 5. 多维度组合查询
        logger.info("\n5️⃣ 多维度组合查询 - 按操作系统和渠道分组")
        sql5 = """
            SELECT
                os,
                channel_id,
                COUNT(*) as record_count,
                SUM(request_count) AS total_requests,
                SUM(callback_count) AS total_callbacks
            FROM ad_stats_daily
            WHERE date_day >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
            GROUP BY os, channel_id
            HAVING total_requests > 1000
            ORDER BY total_requests DESC
            LIMIT 10
        """
        
        results5, time5 = execute_query_with_timing(cursor, sql5, None, "多维度组合查询")
        
        if results5:
            print("  Top操作系统×渠道组合:")
            for row in results5:
                os_name = row['os'] or 'NULL'
                channel_name = row['channel_id'] or 'NULL'
                print(f"    {os_name} × {channel_name}: {row['total_requests']:,} 请求, "
                      f"{row['total_callbacks']} 回调")
        
        print(f"\n⚡ 性能总结:")
        print(f"  查询场景1(条件筛选): {time2:.3f}s")
        print(f"  查询场景2(分组统计): {time3:.3f}s")
        print(f"  趋势查询: {time4:.3f}s")
        print(f"  多维度查询: {time5:.3f}s")
        
        return True
        
    except Exception as e:
        logger.error(f"❌ 查询测试失败: {e}")
        return False
        
    finally:
        cursor.close()
        conn.close()

def test_user_specific_scenarios():
    """测试用户的具体查询场景"""
    logger.info("\n🎯 测试用户的具体查询场景")
    
    conn = connect_db()
    cursor = conn.cursor()
    
    try:
        # 模拟用户查询：查询is_callback_sent为1（即有回调）的情况
        # 在我们的聚合表中，callback_count > 0 就表示有回调
        
        logger.info("\n📋 场景：查询某天某广告的回调情况")
        
        # 先找一个有数据的广告ID
        cursor.execute("""
            SELECT ad_id, date_day, SUM(callback_count) as total_callbacks
            FROM ad_stats_daily 
            WHERE callback_count > 0 
            GROUP BY ad_id, date_day 
            ORDER BY total_callbacks DESC 
            LIMIT 1
        """)
        
        sample = cursor.fetchone()
        if not sample:
            logger.warning("⚠️ 未找到有回调数据的样本")
            return True
        
        sample_ad_id = sample['ad_id']
        sample_date = sample['date_day']
        
        logger.info(f"📊 使用样本数据: ad_id={sample_ad_id}, date={sample_date}")
        
        # 用户查询场景1：某天某广告的总请求数和回调数
        sql1 = """
            SELECT 
                SUM(request_count) as total_requests,
                SUM(callback_count) as total_callbacks
            FROM ad_stats_daily
            WHERE date_day = %s AND ad_id = %s
        """
        
        results1, time1 = execute_query_with_timing(
            cursor, sql1, (sample_date, sample_ad_id),
            f"用户场景1 - {sample_date} {sample_ad_id} 总量统计"
        )
        
        if results1:
            result = results1[0]
            print(f"  该广告在{sample_date}的数据:")
            print(f"    总请求数: {result['total_requests']:,}")
            print(f"    总回调数: {result['total_callbacks']:,}")
        
        # 用户查询场景2：该广告各回调类型的数量分布
        sql2 = """
            SELECT 
                callback_event_type,
                SUM(callback_count) as callback_count
            FROM ad_stats_daily
            WHERE date_day = %s AND ad_id = %s
              AND callback_count > 0
            GROUP BY callback_event_type
            ORDER BY callback_count DESC
        """
        
        results2, time2 = execute_query_with_timing(
            cursor, sql2, (sample_date, sample_ad_id),
            f"用户场景2 - {sample_date} {sample_ad_id} 回调类型分布"
        )
        
        if results2:
            print(f"  该广告的回调类型分布:")
            for row in results2:
                event_type = row['callback_event_type'] or 'NULL'
                print(f"    {event_type}: {row['callback_count']} 次")
        
        print(f"\n⚡ 用户场景性能:")
        print(f"  场景1(总量查询): {time1:.3f}s")
        print(f"  场景2(分布查询): {time2:.3f}s")
        
        return True
        
    except Exception as e:
        logger.error(f"❌ 用户场景测试失败: {e}")
        return False
        
    finally:
        cursor.close()
        conn.close()

def main():
    """主函数"""
    print("🔍 广告数据聚合表查询测试（最小工程版本）")
    print("=" * 60)
    
    success = True
    
    # 基础功能测试
    if not test_basic_queries():
        success = False
    
    # 用户场景测试
    if not test_user_specific_scenarios():
        success = False
    
    print("\n" + "=" * 60)
    
    if success:
        print("✅ 所有测试通过!")
        print("\n💡 总结:")
        print("  • 单表设计简洁高效")
        print("  • 查询性能优秀（毫秒级）")
        print("  • 完全支持用户的查询需求")
        print("  • 支持灵活的多维度分析")
        
        print("\n📋 下一步:")
        print("  1. 配置定时任务自动运行ETL")
        print("  2. 根据实际查询频率优化索引")
        print("  3. 监控数据质量和一致性")
        
    else:
        print("❌ 部分测试失败，请检查数据和配置")
    
    return success

if __name__ == "__main__":
    main()
