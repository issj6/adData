#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
简化版Flask应用 - 用于测试
"""

import sys
import os
sys.path.append('/Users/yang/PycharmProjects/adData')

from flask import Flask, render_template, jsonify
import pymysql
from db_config import TARGET_DB_CONFIG

app = Flask(__name__)

@app.route('/')
def index():
    """主页"""
    return render_template('index.html')

@app.route('/api/test')
def test():
    """测试接口"""
    return jsonify({'status': 'ok', 'message': 'Flask is working'})

@app.route('/api/filter-options')
def get_filter_options():
    """获取筛选选项 - 简化版"""
    try:
        print("开始查询筛选选项...")
        conn = pymysql.connect(**TARGET_DB_CONFIG)
        cursor = conn.cursor()
        
        # 简化查询，只获取少量数据
        options = {}
        
        # 获取ds_id选项（限制10个）
        cursor.execute("SELECT DISTINCT ds_id FROM ad_stats_daily WHERE ds_id IS NOT NULL ORDER BY ds_id LIMIT 10")
        options['ds_ids'] = [row[0] for row in cursor.fetchall()]
        
        # 获取ad_id选项（限制10个）
        cursor.execute("SELECT DISTINCT ad_id FROM ad_stats_daily WHERE ad_id IS NOT NULL ORDER BY ad_id LIMIT 10")
        options['ad_ids'] = [row[0] for row in cursor.fetchall()]
        
        # 获取os选项
        cursor.execute("SELECT DISTINCT os FROM ad_stats_daily WHERE os IS NOT NULL ORDER BY os")
        options['os_list'] = [row[0] for row in cursor.fetchall()]
        
        # 获取callback_event_type选项
        cursor.execute("SELECT DISTINCT callback_event_type FROM ad_stats_daily WHERE callback_event_type IS NOT NULL ORDER BY callback_event_type")
        options['callback_event_types'] = [row[0] for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        
        print("✅ 查询完成")
        return jsonify(options)
        
    except Exception as e:
        print(f"❌ 查询失败: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/query')
def query_data():
    """查询数据 - 简化版"""
    try:
        conn = pymysql.connect(**TARGET_DB_CONFIG)
        cursor = conn.cursor()
        
        # 简单查询最近10条数据
        cursor.execute("""
            SELECT date_day, ds_id, ad_id, os, callback_event_type, 
                   request_count, callback_count
            FROM ad_stats_daily 
            ORDER BY date_day DESC 
            LIMIT 10
        """)
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'date_day': str(row[0]),
                'ds_id': row[1],
                'ad_id': row[2],
                'os': row[3],
                'callback_event_type': row[4],
                'request_count': row[5],
                'callback_count': row[6]
            })
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'data': results,
            'total': len(results)
        })
        
    except Exception as e:
        print(f"❌ 查询失败: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print("启动简化的Flask应用...")
    app.run(debug=True, host='127.0.0.1', port=8080)
