-- ============================================
-- Migration: 003_create_teaching_state.sql
-- Description: 创建教学状态表，用于跟踪写作教练的教学流程状态
-- Created: 2026-06-01
-- ============================================

CREATE TABLE IF NOT EXISTS teaching_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL UNIQUE,
    current_phase TEXT NOT NULL DEFAULT 'P0_INIT',
    current_subphase TEXT,
    completed_actions TEXT DEFAULT '[]',
    completed_tasks TEXT DEFAULT '[]',
    active_problems TEXT DEFAULT '[]',
    next_suggested_actions TEXT DEFAULT '[]',
    current_task_id TEXT,
    diagnosis_summary TEXT DEFAULT '',
    last_user_confirmation TEXT,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- 创建索引以优化查询性能
CREATE INDEX IF NOT EXISTS idx_teaching_state_session ON teaching_state(session_id);
CREATE INDEX IF NOT EXISTS idx_teaching_state_phase ON teaching_state(current_phase);

-- 创建触发器自动更新 updated_at 字段
-- 注意: SQLite 不直接支持 UPDATE 触发器中的自动时间戳
-- 需要在应用层维护 updated_at 的更新
