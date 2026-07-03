-- ============================================
-- Migration: 027_active_training_step_responses.sql
-- Description: 新增 active_training.step_responses_json 字段
--   存 5 步分步提交的回答内容(Sprint 25 BL-01 C-4)。
--   - 与 user_draft 独立:user_draft 是"主草稿"(S8 改写),
--     step_responses 是 5 步流每步的"理解复述/确认文本"。
--   - 序列化: JSON 字符串,解析为 StepResponse[]
--   - 幂等: ALTER TABLE ADD COLUMN 用 IF NOT EXISTS 防御
--
-- 依据: dev-docs/tasks/sprint-25-bl-01-five-step-flow-integration.md §C-4
-- 决策: D-073 C-4(5 步分步提交契约)
-- 回滚: ALTER TABLE active_training DROP COLUMN step_responses_json;
-- Created: 2026-07-03
-- ============================================

BEGIN TRANSACTION;

-- ===== 新增字段 =====
-- 5 步通用流每步提交的回答内容,独立于 user_draft
-- 默认 '[]' 避免 NULL 解析路径
ALTER TABLE active_training ADD COLUMN step_responses_json TEXT NOT NULL DEFAULT '[]';

COMMIT;
