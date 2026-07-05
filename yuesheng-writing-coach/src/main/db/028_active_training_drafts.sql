-- ============================================
-- Migration: 028_active_training_drafts.sql
-- Description: 新增 active_training_drafts 表
--   每次 step 推进(advance/evaluate/complete/abort)自动快照 userDraft,
--   支持查询历史快照与回退到指定版本(Sprint 25 C-1)。
--
-- 字段设计:
--   - active_training_id: 关联 active_training(id),ON DELETE CASCADE
--   - step_index: 快照时刻的 currentStepIndex
--   - content: 快照内容(userDraft 副本)
--   - trigger: 触发原因
--   - snapshot_at: 快照时间 ISO 8601
--   - restored_from_id: 仅 restore 触发时指向原快照
--
-- 字符上限: 50K(与 active_training.user_draft 一致,超限截断并 warn)
--
-- 依据: dev-docs/tasks/sprint-25-plan.md §C-1
-- 决策: D-070 §2.2(状态机边界) + #42
-- 回滚: DROP TABLE IF EXISTS active_training_drafts;
-- Created: 2026-07-05
-- ============================================

BEGIN TRANSACTION;

-- ===== 草稿快照表 =====
CREATE TABLE IF NOT EXISTS active_training_drafts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  active_training_id INTEGER NOT NULL,
  step_index INTEGER NOT NULL,
  content TEXT NOT NULL,
  trigger TEXT NOT NULL,
  snapshot_at TEXT NOT NULL,
  restored_from_id INTEGER,
  FOREIGN KEY (active_training_id) REFERENCES active_training(id) ON DELETE CASCADE
);

-- 按训练ID + 步骤索引查询(历史回退/审计)
CREATE INDEX IF NOT EXISTS idx_atd_at_id
  ON active_training_drafts(active_training_id, step_index);

-- 按时间倒序(最近快照优先)
CREATE INDEX IF NOT EXISTS idx_atd_snapshot_at
  ON active_training_drafts(active_training_id, snapshot_at DESC);

COMMIT;
