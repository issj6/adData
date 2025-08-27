-- 创建广告名称映射表
-- 用于替代 ad_mapping.json，实现动态映射管理

CREATE TABLE IF NOT EXISTS ad_name_map (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    ad_id VARCHAR(128) NOT NULL COMMENT '广告ID',
    display_name VARCHAR(255) NOT NULL COMMENT '显示名称',
    is_active TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用(1:启用, 0:停用)',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    UNIQUE KEY uk_ad_id (ad_id),
    KEY idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='广告名称映射表';

-- 插入现有映射数据（从 ad_mapping.json 迁移）
INSERT INTO ad_name_map (ad_id, display_name) VALUES
('67576', '永远的蔚蓝星球'),
('10_60_683572_8', '燕云十六声'),
('68a58f8ab82a4', '向僵尸开炮'),
('68ae719ed76c8', '热血江湖：归来')
ON DUPLICATE KEY UPDATE 
display_name = VALUES(display_name),
is_active = 1,
updated_at = CURRENT_TIMESTAMP;
