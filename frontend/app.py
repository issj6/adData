#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
广告数据可视化前端应用（Flask后端）
提供数据查询API和Web界面
"""

import sys
import os
import json
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from flask import Flask, render_template, request, jsonify
import time
import pymysql
from datetime import datetime, timedelta
import logging

from db_config import TARGET_DB_CONFIG

app = Flask(__name__)
app.config['SECRET_KEY'] = 'ad-data-dashboard'
# 开发期：模板与静态资源不缓存，便于看到最新改动
app.config['TEMPLATES_AUTO_RELOAD'] = True
app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 0
app.config['STATIC_VERSION'] = int(time.time())
app.jinja_env.auto_reload = True

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_db_connection():
    """获取数据库连接（增加超时与自动提交，避免阻塞）"""
    return pymysql.connect(
        **TARGET_DB_CONFIG,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
        connect_timeout=3,
        read_timeout=5,
        write_timeout=5,
    )

def load_ad_mapping():
    """从数据库加载广告ID映射关系"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 查询启用的映射关系
        cursor.execute("SELECT ad_id, display_name FROM ad_name_map WHERE is_active = 1")
        rows = cursor.fetchall()
        
        # 构造映射字典
        mapping = {}
        for row in rows:
            mapping[row['ad_id']] = row['display_name']
        
        cursor.close()
        conn.close()
        
        logger.info(f"从数据库加载广告映射: {len(mapping)} 个")
        return mapping
        
    except Exception as e:
        logger.error(f"从数据库加载广告映射失败: {e}")
        return {}

@app.route('/')
def index():
    """主页面"""
    return render_template('index.html')

@app.route('/api/filter-options')
def get_filter_options():
    """获取筛选器选项"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 获取各个维度的唯一值
        options = {}
        
        # 获取日期范围
        cursor.execute("SELECT MIN(date_day) as min_date, MAX(date_day) as max_date FROM ad_stats_daily")
        date_range = cursor.fetchone()
        options['date_range'] = {
            'min_date': str(date_range['min_date']) if date_range['min_date'] else None,
            'max_date': str(date_range['max_date']) if date_range['max_date'] else None
        }
        
        # 获取下游标识选项
        cursor.execute("SELECT DISTINCT ds_id FROM ad_stats_daily WHERE ds_id IS NOT NULL ORDER BY ds_id")
        options['ds_ids'] = [row['ds_id'] for row in cursor.fetchall()]
        
        # 获取广告ID选项（限制前50个）
        cursor.execute("""
            SELECT DISTINCT ad_id 
            FROM ad_stats_daily 
            WHERE ad_id IS NOT NULL 
            ORDER BY ad_id 
            LIMIT 50
        """)
        options['ad_ids'] = [row['ad_id'] for row in cursor.fetchall()]
        
        # 获取渠道选项
        cursor.execute("SELECT DISTINCT channel_id FROM ad_stats_daily WHERE channel_id IS NOT NULL ORDER BY channel_id")
        options['channel_ids'] = [row['channel_id'] for row in cursor.fetchall()]
        
        # 获取操作系统选项
        cursor.execute("SELECT DISTINCT os FROM ad_stats_daily WHERE os IS NOT NULL ORDER BY os")
        options['os_list'] = [row['os'] for row in cursor.fetchall()]
        

        
        # 获取上游标识选项
        cursor.execute("SELECT DISTINCT up_id FROM ad_stats_daily WHERE up_id IS NOT NULL ORDER BY up_id")
        options['up_ids'] = [row['up_id'] for row in cursor.fetchall()]
        
        # 获取回调发送状态选项
        cursor.execute("SELECT DISTINCT is_callback_sent FROM ad_stats_daily ORDER BY is_callback_sent")
        options['callback_sent_options'] = [row['is_callback_sent'] for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        
        # 添加广告映射关系
        options['ad_mapping'] = load_ad_mapping()
        
        return jsonify(options)
        
    except Exception as e:
        logger.error(f"获取筛选选项失败: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/data')
def get_data():
    """获取聚合数据"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 构建查询条件
        conditions = []
        params = []
        
        # 日期范围筛选
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')
        
        if start_date:
            conditions.append("date_day >= %s")
            params.append(start_date)
        if end_date:
            conditions.append("date_day <= %s")
            params.append(end_date)
        
        # 其他筛选条件
        filters = [
            ('ds_id', 'ds_id'),
            ('ad_id', 'ad_id'), 
            ('channel_id', 'channel_id'),
            ('up_id', 'up_id'),
            ('is_callback_sent', 'is_callback_sent')
        ]
        
        for param_name, column_name in filters:
            value = request.args.get(param_name)
            if value and value != 'all':
                conditions.append(f"{column_name} = %s")
                params.append(value)
        
        # 构建WHERE子句
        where_clause = " AND ".join(conditions) if conditions else "1=1"
        
        # 可选：按维度汇总（默认场景：按ad_id汇总）
        group_by = request.args.get('group_by')
        order_dir = request.args.get('order', 'DESC').upper()
        order_dir = 'ASC' if order_dir == 'ASC' else 'DESC'

        # 在选择“扣量数据(is_callback_sent=2)”时，回调事件数量应统计为对应事件的记录数
        # 其他情况下仍按实际回调数统计
        is_callback_sent_filter = request.args.get('is_callback_sent')
        callback_metric = 'request_count' if is_callback_sent_filter == '2' else 'callback_count'

        if group_by == 'ad_id':
            sql = f"""
                SELECT 
                    date_day,
                    MAX(up_id) AS up_id,
                    MAX(ds_id) AS ds_id,
                    ad_id,
                    MAX(channel_id) AS channel_id,
                    MAX(is_callback_sent) AS is_callback_sent,
                    SUM(request_count) AS request_count,
                    SUM(CASE WHEN callback_event_type IN ('ACTIVATED', 'activate') THEN {callback_metric} ELSE 0 END) AS activated_count,
                    SUM(CASE WHEN callback_event_type IN ('REGISTERED', 'reg') THEN {callback_metric} ELSE 0 END) AS registered_count,
                    SUM(CASE WHEN callback_event_type = 'PAID' THEN {callback_metric} ELSE 0 END) AS paid_count,
                    SUM(CASE WHEN callback_event_type IS NOT NULL THEN {callback_metric} ELSE 0 END) AS total_callback_count,
                    ROUND(SUM(callback_count) * 100.0 / NULLIF(SUM(request_count), 0), 2) AS callback_rate,
                    MAX(updated_at) AS updated_at
                FROM ad_stats_daily
                WHERE {where_clause}
                GROUP BY date_day, ad_id
                ORDER BY date_day {order_dir}, request_count DESC
                LIMIT 1000
            """
            cursor.execute(sql, params)
        else:
            # 明细模式（返回与汇总模式一致的字段结构）
            sql = f"""
                SELECT 
                    date_day,
                    up_id,
                    ds_id,
                    ad_id,
                    channel_id,
                    is_callback_sent,
                    request_count,
                    CASE WHEN callback_event_type IN ('ACTIVATED', 'activate') THEN {callback_metric} ELSE 0 END AS activated_count,
                    CASE WHEN callback_event_type IN ('REGISTERED', 'reg') THEN {callback_metric} ELSE 0 END AS registered_count,
                    CASE WHEN callback_event_type = 'PAID' THEN {callback_metric} ELSE 0 END AS paid_count,
                    {callback_metric} AS total_callback_count,
                    ROUND(CASE 
                        WHEN request_count > 0 
                        THEN callback_count * 100.0 / request_count 
                        ELSE 0 
                    END, 2) as callback_rate,
                    updated_at
                FROM ad_stats_daily
                WHERE {where_clause}
                ORDER BY date_day {order_dir}, request_count DESC
                LIMIT 1000
            """
            cursor.execute(sql, params)
        data = cursor.fetchall()
        
        # 转换日期格式以便JSON序列化
        for row in data:
            if row['date_day']:
                row['date_day'] = str(row['date_day'])
            if row['updated_at']:
                row['updated_at'] = row['updated_at'].strftime('%Y-%m-%d %H:%M:%S')
        
        cursor.close()
        conn.close()
        
        return jsonify({'data': data, 'count': len(data)})
        
    except Exception as e:
        logger.error(f"获取数据失败: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/summary')
def get_summary():
    """获取汇总统计"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 构建查询条件（与get_data相同的逻辑）
        conditions = []
        params = []
        
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')
        
        if start_date:
            conditions.append("date_day >= %s")
            params.append(start_date)
        if end_date:
            conditions.append("date_day <= %s")
            params.append(end_date)
        
        filters = [
            ('ds_id', 'ds_id'),
            ('ad_id', 'ad_id'), 
            ('channel_id', 'channel_id'),
            ('up_id', 'up_id'),
            ('is_callback_sent', 'is_callback_sent')
        ]
        
        for param_name, column_name in filters:
            value = request.args.get(param_name)
            if value and value != 'all':
                conditions.append(f"{column_name} = %s")
                params.append(value)
        
        where_clause = " AND ".join(conditions) if conditions else "1=1"
        
        # 汇总查询
        sql = f"""
            SELECT 
                COUNT(*) as record_count,
                COUNT(DISTINCT date_day) as date_count,
                COUNT(DISTINCT ad_id) as ad_count,
                SUM(request_count) as total_requests,
                SUM(callback_count) as total_callbacks,
                ROUND(SUM(callback_count) * 100.0 / NULLIF(SUM(request_count), 0), 2) as overall_callback_rate
            FROM ad_stats_daily
            WHERE {where_clause}
        """
        
        cursor.execute(sql, params)
        summary = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        return jsonify(summary)
        
    except Exception as e:
        logger.error(f"获取汇总统计失败: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/callback-distribution')
def get_callback_distribution():
    """获取回调事件类型分布"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 构建查询条件（与get_data相同的逻辑）
        conditions = []
        params = []
        
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')
        
        if start_date:
            conditions.append("date_day >= %s")
            params.append(start_date)
        if end_date:
            conditions.append("date_day <= %s")
            params.append(end_date)
        
        filters = [
            ('ds_id', 'ds_id'),
            ('ad_id', 'ad_id'), 
            ('channel_id', 'channel_id'),
            ('os', 'os'),
            ('up_id', 'up_id')
        ]
        
        for param_name, column_name in filters:
            value = request.args.get(param_name)
            if value and value != 'all':
                conditions.append(f"{column_name} = %s")
                params.append(value)
        
        where_clause = " AND ".join(conditions) if conditions else "1=1"
        
        # 回调类型分布查询（注意 where_clause 出现两次，需要双份参数）
        sql = f"""
            SELECT 
                COALESCE(a.callback_event_type, 'NULL') AS callback_event_type,
                SUM(a.callback_count) AS callback_count,
                ROUND(
                    SUM(a.callback_count) * 100.0 /
                    NULLIF((SELECT SUM(callback_count) FROM ad_stats_daily WHERE {where_clause}), 0),
                    2
                ) AS percentage
            FROM ad_stats_daily a
            WHERE {where_clause}
            GROUP BY a.callback_event_type
            ORDER BY callback_count DESC
        """
        
        duplicate_params = params + params if params else []
        cursor.execute(sql, duplicate_params)
        distribution = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify(distribution)
        
    except Exception as e:
        logger.error(f"获取回调分布失败: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    # 从环境变量获取配置
    import os
    host = os.getenv('FLASK_HOST', '0.0.0.0')
    port = int(os.getenv('FLASK_PORT', '8080'))
    debug = os.getenv('FLASK_DEBUG', 'false').lower() == 'true'
    
    # 生产化的开发运行参数：关闭自动重载，开启多线程以避免阻塞
    app.run(debug=debug, host=host, port=port, threaded=True)
