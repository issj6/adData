-- 广告数据聚合表创建脚本（最小工程版本）
-- 仅一张日级聚合表，按track_time归因，支持迟到回调

-- 日级聚合表（唯一聚合表）
DROP TABLE IF EXISTS ad_stats_daily;
CREATE TABLE ad_stats_daily (
    id bigint AUTO_INCREMENT PRIMARY KEY COMMENT '自增主键',
    date_day date NOT NULL COMMENT '点击日期（基于track_time）',
    up_id varchar(64) DEFAULT NULL COMMENT '上游标识',
    ds_id varchar(64) NOT NULL COMMENT '下游标识',
    ad_id varchar(128) DEFAULT NULL COMMENT '广告标识',
    channel_id varchar(64) DEFAULT NULL COMMENT '渠道标识',
    os varchar(16) DEFAULT NULL COMMENT '操作系统',
    is_callback_sent tinyint(1) DEFAULT NULL COMMENT '回调发送状态(0:未发送, 1:已发送, 2:扣量)',
    callback_event_type varchar(64) DEFAULT NULL COMMENT '回调事件类型',
    request_count bigint NOT NULL DEFAULT 0 COMMENT '请求总数（该点击日的请求数）',
    callback_count bigint NOT NULL DEFAULT 0 COMMENT '回调总数（该点击日对应的已回调数）',
    updated_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    
    UNIQUE KEY uk_daily_stats (date_day, up_id, ds_id, ad_id, channel_id, os, is_callback_sent, callback_event_type) COMMENT '唯一约束',
    KEY idx_day_ad (date_day, ad_id) COMMENT '按日期+广告查询',
    KEY idx_day_ds_channel (date_day, ds_id, channel_id) COMMENT '按日期+下游+渠道查询',
    KEY idx_day_callback_type (date_day, callback_event_type) COMMENT '按日期+回调类型查询',
    KEY idx_callback_sent (is_callback_sent) COMMENT '按回调状态查询'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='日级广告统计表（按点击日归因）';

-- ===============================================================
-- 查询示例
-- ===============================================================

-- 示例1: 查询某天某些条件下的广告数量和回调数量
-- SELECT
--     SUM(request_count) AS total_requests,
--     SUM(callback_count) AS total_callbacks
-- FROM ad_stats_daily
-- WHERE date_day = '2025-08-26'
--   AND ad_id = 'aabbcc'         -- 可选条件
--   AND ds_id = 'ow'             -- 可选条件
--   AND channel_id = 'owch1';    -- 可选条件

-- 示例2: 查询同一条件下各callback_event_type的数量分布
-- SELECT
--     callback_event_type,
--     SUM(callback_count) AS callbacks
-- FROM ad_stats_daily
-- WHERE date_day = '2025-08-26'
--   AND ad_id = 'aabbcc'         -- 同样条件
--   AND ds_id = 'ow'
-- GROUP BY callback_event_type
-- ORDER BY callbacks DESC;

-- 示例3: 查询某天某广告的完整统计信息
-- SELECT
--     up_id,
--     ds_id, 
--     channel_id,
--     os,
--     callback_event_type,
--     request_count,
--     callback_count
-- FROM ad_stats_daily
-- WHERE date_day = '2025-08-26'
--   AND ad_id = 'aabbcc'
-- ORDER BY callback_count DESC;
