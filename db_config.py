# 数据库连接配置
# 原数据库配置（上亿数据的生产库）
SOURCE_DB_CONFIG = {
    'host': '222.186.41.7',
    'port': 3316,
    'user': 'root',
    'password': 'Yyy443556.0',
    'database': 'ad_router',
    'charset': 'utf8mb4'
}

# 原数据库表名
SOURCE_TABLE_NAME = 'request_log'

# 目标数据库配置（聚合数据存储库）
TARGET_DB_CONFIG = {
    'host': '127.0.0.1',
    'port': 3306,
    'user': 'root',
    'password': '123456',
    'database': 'ad_data',
    'charset': 'utf8mb4'
}