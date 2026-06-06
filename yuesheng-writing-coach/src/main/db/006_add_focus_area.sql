-- ============================================
-- Migration: 006_add_focus_area.sql
-- Description: 为 teaching_state 表添加聚焦方向和过渡邀请字段
-- Created: 2026-06-02
-- ============================================

-- 添加 focus_area 字段（聚焦方向）
ALTER TABLE teaching_state ADD COLUMN focus_area TEXT DEFAULT NULL;

-- 添加 transition_offered 字段（是否已提供过渡邀请，0/1）
ALTER TABLE teaching_state ADD COLUMN transition_offered INTEGER DEFAULT 0 CHECK(transition_offered IN (0, 1));

-- 创建索引优化按 focus_area 的查询
CREATE INDEX IF NOT EXISTS idx_teaching_state_focus_area ON teaching_state(focus_area);
