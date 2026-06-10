-- ============================================
-- Migration: 018_db_p1a_time_format.sql
-- Description: DB-P1a 时间格式统一
-- 统一所有时间字段为 INTEGER NOT NULL DEFAULT (unixepoch())
-- 现有 TEXT（ISO 8601）数据自动转换为 INTEGER unix 时间戳
-- SQLite 不支持 ALTER COLUMN，需重建表
-- Created: 2026-06-09
-- ============================================

PRAGMA foreign_keys = OFF;

-- ===== 1. teaching_state =====
-- updated_at: TEXT → INTEGER NOT NULL DEFAULT (unixepoch())

DROP TABLE IF EXISTS teaching_state_p1a;

CREATE TABLE IF NOT EXISTS teaching_state_p1a (
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
    focus_area TEXT DEFAULT NULL,
    transition_offered INTEGER DEFAULT 0,
    locked_syndromes TEXT DEFAULT '[]',
    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

INSERT INTO teaching_state_p1a (
    id, session_id, current_phase, current_subphase,
    completed_actions, completed_tasks, active_problems,
    next_suggested_actions, current_task_id, diagnosis_summary,
    last_user_confirmation, focus_area, transition_offered,
    locked_syndromes, updated_at
)
SELECT
    id, session_id, current_phase, current_subphase,
    completed_actions, completed_tasks, active_problems,
    next_suggested_actions, current_task_id, diagnosis_summary,
    last_user_confirmation, focus_area, transition_offered,
    locked_syndromes,
    COALESCE(CAST(strftime('%s', REPLACE(REPLACE(updated_at, 'T', ' '), 'Z', '')) AS INTEGER), unixepoch())
FROM teaching_state;

DROP TABLE IF EXISTS teaching_state;
ALTER TABLE teaching_state_p1a RENAME TO teaching_state;

CREATE INDEX IF NOT EXISTS idx_teaching_state_session ON teaching_state(session_id);
CREATE INDEX IF NOT EXISTS idx_teaching_state_phase ON teaching_state(current_phase);
CREATE INDEX IF NOT EXISTS idx_teaching_state_focus_area ON teaching_state(focus_area);


-- ===== 2. sessions =====
-- created_at: TEXT → INTEGER NOT NULL DEFAULT (unixepoch())
-- updated_at: TEXT → INTEGER NOT NULL DEFAULT (unixepoch())

DROP TABLE IF EXISTS sessions_p1a;

CREATE TABLE IF NOT EXISTS sessions_p1a (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '新建会话',
    preview TEXT DEFAULT '',
    manuscript_id TEXT,
    chapter_id TEXT,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

INSERT INTO sessions_p1a (id, title, preview, manuscript_id, chapter_id, created_at, updated_at)
SELECT
    id, title, preview, manuscript_id, chapter_id,
    COALESCE(CAST(strftime('%s', REPLACE(REPLACE(created_at, 'T', ' '), 'Z', '')) AS INTEGER), unixepoch()),
    COALESCE(CAST(strftime('%s', REPLACE(REPLACE(updated_at, 'T', ' '), 'Z', '')) AS INTEGER), unixepoch())
FROM sessions;

DROP TABLE IF EXISTS sessions;
ALTER TABLE sessions_p1a RENAME TO sessions;


-- ===== 3. diagnosis_results =====
-- timestamp: TEXT → INTEGER NOT NULL
-- created_at: TEXT DEFAULT (datetime('now')) → INTEGER NOT NULL DEFAULT (unixepoch())
-- 注意：015 迁移重建表时可能丢失 root_cause_analysis 列，此处做防御性处理

DROP TABLE IF EXISTS diagnosis_results_p1a;

CREATE TABLE IF NOT EXISTS diagnosis_results_p1a (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    message_id TEXT NOT NULL,
    syndromes TEXT NOT NULL,
    suggested_actions TEXT NOT NULL,
    confidence REAL NOT NULL DEFAULT 0,
    timestamp INTEGER NOT NULL,
    next_focus TEXT,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    root_cause_analysis TEXT,
    UNIQUE(session_id, message_id)
);

-- 防御性 INSERT：root_cause_analysis 可能不存在于旧表中（015 重建时丢失）
-- 015 迁移重建表时遗漏了此列，此处统一填 NULL，后续由诊断 Agent 重新生成
INSERT INTO diagnosis_results_p1a (
    id, session_id, message_id, syndromes, suggested_actions,
    confidence, timestamp, next_focus, created_at, root_cause_analysis
)
SELECT
    id, session_id, message_id, syndromes, suggested_actions,
    confidence,
    COALESCE(CAST(strftime('%s', REPLACE(REPLACE(timestamp, 'T', ' '), 'Z', '')) AS INTEGER), unixepoch()),
    next_focus,
    COALESCE(CAST(strftime('%s', REPLACE(REPLACE(created_at, 'T', ' '), 'Z', '')) AS INTEGER), unixepoch()),
    NULL
FROM diagnosis_results;

DROP TABLE IF EXISTS diagnosis_results;
ALTER TABLE diagnosis_results_p1a RENAME TO diagnosis_results;

CREATE INDEX IF NOT EXISTS idx_diagnosis_session ON diagnosis_results(session_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_diagnosis_message ON diagnosis_results(message_id);


-- ===== 4. user_training_records =====
-- assigned_at: TEXT NOT NULL → INTEGER NOT NULL
-- completed_at: TEXT → INTEGER (nullable)

DROP TABLE IF EXISTS user_training_records_p1a;

CREATE TABLE IF NOT EXISTS user_training_records_p1a (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    task_id TEXT NOT NULL,
    syndrome_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('assigned', 'completed', 'skipped')),
    assigned_at INTEGER NOT NULL,
    completed_at INTEGER,
    user_response TEXT,
    ai_feedback TEXT,
    effectiveness INTEGER CHECK(effectiveness IS NULL OR (effectiveness >= 1 AND effectiveness <= 5)),
    score INTEGER
);

INSERT INTO user_training_records_p1a (
    id, session_id, task_id, syndrome_id, status,
    assigned_at, completed_at, user_response, ai_feedback,
    effectiveness, score
)
SELECT
    id, session_id, task_id, syndrome_id, status,
    CAST(strftime('%s', REPLACE(assigned_at, 'T', ' ')) AS INTEGER),
    CASE WHEN completed_at IS NOT NULL
         THEN CAST(strftime('%s', REPLACE(completed_at, 'T', ' ')) AS INTEGER)
         ELSE NULL
    END,
    user_response, ai_feedback, effectiveness, score
FROM user_training_records;

DROP TABLE IF EXISTS user_training_records;
ALTER TABLE user_training_records_p1a RENAME TO user_training_records;

CREATE INDEX IF NOT EXISTS idx_training_session ON user_training_records(session_id, assigned_at);
CREATE INDEX IF NOT EXISTS idx_training_task ON user_training_records(task_id);
CREATE INDEX IF NOT EXISTS idx_training_status ON user_training_records(session_id, status);


-- ===== 5. evidence =====
-- created_at: TEXT NOT NULL → INTEGER NOT NULL DEFAULT (unixepoch())

DROP TABLE IF EXISTS evidence_p1a;

CREATE TABLE IF NOT EXISTS evidence_p1a (
    evidence_id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK(type IN ('text', 'pattern', 'statistical', 'comparison')),
    level INTEGER NOT NULL CHECK(level IN (1, 2, 3, 4)),
    novel_id TEXT NOT NULL,
    chapter_id TEXT,
    chapter_range TEXT,
    paragraph_index INTEGER,
    sample_range TEXT,
    content_json TEXT NOT NULL,
    related_disease TEXT NOT NULL,
    related_ability TEXT NOT NULL,
    related_observations TEXT,
    extracted_by TEXT NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
);

INSERT INTO evidence_p1a (
    evidence_id, type, level, novel_id, chapter_id,
    chapter_range, paragraph_index, sample_range, content_json,
    related_disease, related_ability, related_observations,
    extracted_by, created_at
)
SELECT
    evidence_id, type, level, novel_id, chapter_id,
    chapter_range, paragraph_index, sample_range, content_json,
    related_disease, related_ability, related_observations,
    extracted_by,
    CAST(strftime('%s', REPLACE(created_at, 'T', ' ')) AS INTEGER)
FROM evidence;

DROP TABLE IF EXISTS evidence;
ALTER TABLE evidence_p1a RENAME TO evidence;

CREATE INDEX IF NOT EXISTS idx_evidence_disease ON evidence(related_disease);
CREATE INDEX IF NOT EXISTS idx_evidence_ability ON evidence(related_ability);
CREATE INDEX IF NOT EXISTS idx_evidence_novel ON evidence(novel_id);
CREATE INDEX IF NOT EXISTS idx_evidence_level ON evidence(level);

PRAGMA foreign_keys = ON;
