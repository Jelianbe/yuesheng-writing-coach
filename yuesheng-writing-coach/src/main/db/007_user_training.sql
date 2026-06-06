-- ============================================
-- Migration: 007_user_training.sql
-- Description: 创建用户训练记录表，用于追踪训练任务分配和完成情况
-- Created: 2026-06-02
-- ============================================

CREATE TABLE IF NOT EXISTS user_training_records (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    task_id TEXT NOT NULL,
    syndrome_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('assigned', 'completed', 'skipped')),
    assigned_at TEXT NOT NULL,
    completed_at TEXT,
    user_response TEXT,
    ai_feedback TEXT,
    effectiveness INTEGER CHECK(effectiveness IS NULL OR (effectiveness >= 1 AND effectiveness <= 5))
);

-- 优化查询性能
CREATE INDEX IF NOT EXISTS idx_training_session ON user_training_records(session_id, assigned_at);
CREATE INDEX IF NOT EXISTS idx_training_task ON user_training_records(task_id);
CREATE INDEX IF NOT EXISTS idx_training_status ON user_training_records(session_id, status);
