-- ============================================
-- Migration: 025_teaching_state_active_training.sql
-- Description: teaching_state 表新增 active_training_meta 列
--   记录 session 进入 ActiveTraining 状态的元数据(JSON 字符串)
--   - syndromeId: 触发的症候 ID
--   - techniqueId?: 关联技法 ID(可选)
--   - triggeredAt: 触发时间 ISO 格式
--   - source: 触发来源 (training_triggered | user_request | diagnosis_result)
-- 依据: dev-docs/tasks/sprint-23-plan.md §G-1
-- 决策: D-069 路径 C (占位改进,S24 完整状态机迁移)
-- 升级：RWR-G1
-- 回滚：ALTER TABLE teaching_state DROP COLUMN active_training_meta;
-- Created: 2026-07-03
-- ============================================

BEGIN TRANSACTION;

-- ===== teaching_state.active_training_meta =====
-- Sprint 23 G-1: 主进程侧 ActiveTraining 业务元数据(轻量 JSON 字段)
-- R-014 配置外置: 数据结构在 types 层(ActiveTrainingMeta),DB 层只存 string
-- R-010 最小化: 不新增独立 active_training 表,保持单表模式
-- 完整 ActiveTrainingSession 状态机迁移推到 Sprint 24
ALTER TABLE teaching_state
  ADD COLUMN active_training_meta TEXT DEFAULT NULL;

COMMIT;
