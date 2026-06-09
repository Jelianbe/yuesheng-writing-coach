-- ============================================
-- Migration: 019_db_p1b_pk_unify.sql
-- Description: DB-P1b 主键类型统一
-- teaching_state.id: INTEGER PRIMARY KEY → TEXT UUID
-- 统一与全局 UUID 格式一致
-- 所有代码层查询均使用 session_id，PK 变更对运行时无影响
-- Created: 2026-06-09
-- ============================================

CREATE TABLE IF NOT EXISTS teaching_state_p1b (
    id TEXT PRIMARY KEY,
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
    focus_area TEXT DEFAULT NULL,
    transition_offered INTEGER DEFAULT 0,
    locked_syndromes TEXT DEFAULT '[]',
    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

INSERT INTO teaching_state_p1b (
    id, session_id, current_phase, current_subphase,
    completed_actions, completed_tasks, active_problems,
    next_suggested_actions, current_task_id, diagnosis_summary,
    last_user_confirmation, focus_area, transition_offered,
    locked_syndromes, updated_at
)
SELECT
    hex(randomblob(16)),
    session_id, current_phase, current_subphase,
    completed_actions, completed_tasks, active_problems,
    next_suggested_actions, current_task_id, diagnosis_summary,
    last_user_confirmation, focus_area, transition_offered,
    locked_syndromes, updated_at
FROM teaching_state;

DROP TABLE IF EXISTS teaching_state;
ALTER TABLE teaching_state_p1b RENAME TO teaching_state;

CREATE INDEX IF NOT EXISTS idx_teaching_state_session ON teaching_state(session_id);
CREATE INDEX IF NOT EXISTS idx_teaching_state_phase ON teaching_state(current_phase);
CREATE INDEX IF NOT EXISTS idx_teaching_state_focus_area ON teaching_state(focus_area);
