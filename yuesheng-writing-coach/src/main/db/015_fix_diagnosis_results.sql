-- 015: 修复 diagnosis_results 参照完整性
-- 补全 FK（message_id → chat_messages.id）+ UNIQUE（session_id + message_id）
--
-- SQLite 不支持 ALTER TABLE ADD CONSTRAINT，需重建：
-- 1. 建新表（带约束）
-- 2. 迁移数据
-- 3. 删除旧表
-- 4. 新表重命名

DROP TABLE IF EXISTS diagnosis_results_new;

CREATE TABLE IF NOT EXISTS diagnosis_results_new (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  message_id TEXT NOT NULL REFERENCES messages(id),
  syndromes TEXT NOT NULL,
  suggested_actions TEXT NOT NULL,
  confidence REAL NOT NULL DEFAULT 0,
  timestamp TEXT NOT NULL,
  next_focus TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  root_cause_analysis TEXT,
  UNIQUE(session_id, message_id)
);

-- 临时禁用 FK 检查以迁移已有数据（可能存在孤儿记录）
PRAGMA foreign_keys = OFF;

INSERT INTO diagnosis_results_new (id, session_id, message_id, syndromes, suggested_actions, confidence, timestamp, next_focus, created_at, root_cause_analysis)
  SELECT id, session_id, message_id, syndromes, suggested_actions, confidence, timestamp, next_focus, created_at, root_cause_analysis
  FROM diagnosis_results;

DROP TABLE diagnosis_results;

ALTER TABLE diagnosis_results_new RENAME TO diagnosis_results;

-- 重新启用 FK 检查（新数据将受约束）
PRAGMA foreign_keys = ON;

CREATE INDEX IF NOT EXISTS idx_diagnosis_session ON diagnosis_results(session_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_diagnosis_message ON diagnosis_results(message_id);
