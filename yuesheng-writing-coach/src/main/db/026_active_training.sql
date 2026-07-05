-- ============================================
-- Migration: 026_active_training.sql
-- Description: 新增 active_training 表
--   替代 teaching_state.active_training_meta JSON 字段的"业务元数据"职责,
--   承担完整 ActiveTrainingSession 状态机持久化(Sprint 24 A-1)。
--
--   字段设计:
--   - session_id UNIQUE: 同一会话同时只允许一个活跃训练(A-2 状态机边界)
--   - user_draft: 训练草稿(持久化核心,A-3 自动保存目标)
--   - steps_json: TrainingStep[] 序列化(SQLite JSON_EXTRACT 可查询)
--   - status: in_progress | completed | aborted
--   - 流式字段(currentStepIndex, submission_result_json): 状态机转换追踪
--
-- 依据: dev-docs/tasks/sprint-24-plan.md §A-1
-- 决策: D-070 路径 1(新增独立表,保留 teaching_state.active_training_meta 供审计)
-- 回滚: DROP TABLE IF EXISTS active_training;
-- Created: 2026-07-03
-- ============================================

BEGIN TRANSACTION;

-- ===== active_training 表 =====
-- session_id 不加 UNIQUE 约束: 允许同 session 多行(completed/aborted 历史)
-- 唯一性由 partial UNIQUE 索引(下方)保证:仅 in_progress 唯一
CREATE TABLE IF NOT EXISTS active_training (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  challenge_id TEXT NOT NULL,
  challenge_name TEXT,
  mode TEXT,
  current_step_index INTEGER NOT NULL DEFAULT 0,
  steps_json TEXT NOT NULL DEFAULT '[]',
  user_draft TEXT NOT NULL DEFAULT '',
  flow_type TEXT,
  training_flow_json TEXT,
  record_id TEXT,
  syndrome_id TEXT,
  original_quote TEXT,
  constraint_text TEXT,
  submission_result_json TEXT,
  status TEXT NOT NULL DEFAULT 'in_progress',
  started_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- ===== 索引 =====
-- 状态查询(找所有进行中的训练)
CREATE INDEX IF NOT EXISTS idx_active_training_status
  ON active_training(status);

-- 按症候查询(诊断联动)
CREATE INDEX IF NOT EXISTS idx_active_training_syndrome
  ON active_training(syndrome_id);

-- 完成时间倒序(历史审计)
CREATE INDEX IF NOT EXISTS idx_active_training_completed_at
  ON active_training(completed_at DESC);

-- 关键: partial UNIQUE — 同一 session 同时只能有一个 in_progress 训练
-- 但 completed/aborted 历史行可共存(供审计)
-- 决策: D-070 §2.2(状态机边界:Complete/Abort 不可恢复,新训练覆盖旧 in_progress)
CREATE UNIQUE INDEX IF NOT EXISTS idx_active_training_active_session
  ON active_training(session_id)
  WHERE status = 'in_progress';

COMMIT;
