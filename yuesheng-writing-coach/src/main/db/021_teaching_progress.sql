-- ============================================
-- Migration: 021_teaching_progress.sql
-- Description: 教学进度持久化 + 学生画像持久化
--   - diagnosis_results: 新增 teaching_progress (TEXT JSON)
--     { currentStage, resolvedIssues, totalIssues }
--   - 新建 student_model: 跨会话画像持久化
--     { id, session_id, attitude_preference, teaching_history (JSON) }
-- 升级：RWR-P0-1
-- 回滚：DROP TABLE student_model; ALTER TABLE diagnosis_results DROP COLUMN teaching_progress;
-- Created: 2026-06-17
-- ============================================

BEGIN TRANSACTION;

-- ===== 1. diagnosis_results.teaching_progress =====
-- R-014 配置外置: 进度结构 {currentStage, resolvedIssues, totalIssues}
-- R-021 隐性诊断: 进度不暴露症候细节,只显示分子分母
ALTER TABLE diagnosis_results
  ADD COLUMN teaching_progress TEXT DEFAULT NULL;

-- ===== 2. student_model =====
-- 跨会话画像持久化(P1-7 直接读表,不再实时聚合)
-- R-021 隐性诊断: teaching_history 是系统内部字段,不渲染到前端 UI
CREATE TABLE IF NOT EXISTS student_model (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  attitude_preference TEXT DEFAULT NULL,
  teaching_history TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_student_model_session ON student_model(session_id);

COMMIT;
