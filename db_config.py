# 数据库连接配置
import os

# 原数据库配置（上亿数据的生产库）
SOURCE_DB_CONFIG = {
    'host': os.getenv('SOURCE_DB_HOST', '103.36.221.200'),
    'port': int(os.getenv('SOURCE_DB_PORT', '3316')),
    'user': os.getenv('SOURCE_DB_USER', 'root'),
    'password': os.getenv('SOURCE_DB_PASSWORD', 'Yyy443556.0'),
    'database': os.getenv('SOURCE_DB_DATABASE', 'ad_router'),
    'charset': 'utf8mb4'
}

# 原数据库表名
SOURCE_TABLE_NAME = os.getenv('SOURCE_TABLE_NAME', 'request_log')

# 目标数据库配置（聚合数据存储库）
TARGET_DB_CONFIG = {
    'host': os.getenv('TARGET_DB_HOST', '103.36.221.200'),
    'port': int(os.getenv('TARGET_DB_PORT', '3316')),
    'user': os.getenv('TARGET_DB_USER', 'root'),
    'password': os.getenv('TARGET_DB_PASSWORD', 'Yyy443556.0'),
    'database': os.getenv('TARGET_DB_DATABASE', 'ad_data'),
    'charset': 'utf8mb4'
}