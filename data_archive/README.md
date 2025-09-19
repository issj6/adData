# 数据归档系统

## 📋 功能概述

自动归档和清理源数据库中的历史数据，避免数据库过度膨胀。

### 🎯 核心功能
- **自动导出**: 将14天前的数据导出为CSV文件
- **安全删除**: 导出成功后删除源数据库中的对应记录
- **定时执行**: 每日凌晨1点自动运行
- **文件管理**: 自动清理过期的归档文件和日志

## 🚀 使用方式

### 手动执行归档
```bash
cd data_archive
./archive_old_data.sh
```

### 查看归档日志
```bash
# 查看最新日志
tail -f data_archive/logs/archive_$(date +%Y%m%d).log

# 查看归档报告
cat data_archive/logs/archive_report_$(date +%Y%m%d).txt
```

### 准备主机目录
```bash
# 创建主机归档目录
sudo mkdir -p /data/ad/archives /data/ad/logs
sudo chown -R 1000:1000 /data/ad  # 确保Docker容器有权限写入
```

### 配置定时任务
```bash
# 编辑crontab
crontab -e

# 添加以下行（每日凌晨1点执行）
0 1 * * * /path/to/adData/data_archive/archive_old_data.sh
```

## 📁 文件结构

```
data_archive/
├── README.md              # 说明文档
├── archive_old_data.sh     # 归档脚本
├── archives/               # CSV归档文件存储目录（映射到 /data/ad/archives）
│   └── archived_data_YYYYMMDD_HHMMSS.csv
└── logs/                   # 日志文件目录（映射到 /data/ad/logs）
    ├── archive_YYYYMMDD.log        # 执行日志
    └── archive_report_YYYYMMDD.txt # 归档报告
```

## ⚙️ 配置说明

### 环境变量
脚本会自动读取项目根目录的 `.env` 文件中的数据库配置：

```bash
SOURCE_DB_HOST=222.186.41.7
SOURCE_DB_PORT=3316
SOURCE_DB_USER=root
SOURCE_DB_PASSWORD=Yyy443556.0
SOURCE_DB_DATABASE=ad_router
SOURCE_TABLE_NAME=request_log
```

### 归档策略
- **归档条件**: `DATE(track_time) < 14天前`
- **文件命名**: `archived_data_YYYYMMDD_HHMMSS.csv`
- **清理策略**: 
  - 归档文件保留90天
  - 日志文件保留30天

## 🔍 执行流程

1. **检查数据库连接**
2. **计算归档日期** (14天前)
3. **统计待归档记录数**
4. **导出数据为CSV文件**
5. **验证导出完整性**
6. **删除已归档的源数据**
7. **生成归档报告**
8. **清理过期文件**

## 📊 安全机制

### 数据安全
- ✅ 先导出后删除，确保数据不丢失
- ✅ 导出完整性验证
- ✅ 详细的执行日志
- ✅ 错误时保留数据，仅记录警告

### 执行安全
- ✅ 数据库连接检查
- ✅ 异常处理和回滚
- ✅ 操作前数据量确认
- ✅ 详细的状态报告

## 📈 监控和维护

### 执行状态检查
```bash
# 检查最近的归档状态
grep "SUCCESS\|ERROR" data_archive/logs/archive_$(date +%Y%m%d).log

# 查看归档文件大小
ls -lh data_archive/archives/
```

### 故障排除
```bash
# 查看详细错误日志
cat data_archive/logs/archive_$(date +%Y%m%d).log

# 手动测试数据库连接
mysql -h $SOURCE_DB_HOST -P $SOURCE_DB_PORT -u $SOURCE_DB_USER -p$SOURCE_DB_PASSWORD -e "SELECT 1;"
```

## 🚨 注意事项

### 重要提醒
- ⚠️ **数据不可恢复**: 删除的数据仅存在于CSV文件中
- ⚠️ **定期备份**: 建议定期备份CSV归档文件
- ⚠️ **存储空间**: 确保归档目录有足够空间
- ⚠️ **数据库权限**: 确保有DELETE权限

### 建议配置
- 🔧 在生产环境中使用专用数据库用户
- 🔧 设置归档目录的定期备份
- 🔧 配置磁盘空间监控告警
- 🔧 定期检查归档任务的执行状态

## 📋 常见问题

### Q: 如何恢复归档的数据？
A: 从CSV文件中导入，需要手动处理数据格式转换

### Q: 归档失败怎么办？
A: 检查日志文件，常见原因是数据库连接或权限问题

### Q: 可以修改归档天数吗？
A: 可以，修改脚本中的 `14 days ago` 为其他天数

### Q: CSV文件过大怎么办？
A: 可以考虑按月分割或使用压缩存储

---

**状态**: ✅ **已就绪，可投入生产使用**
