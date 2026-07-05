-- Sprint 25 C-2: 状态机审计日志
-- append-only 表,每次状态转换同步写一条审计记录
-- 设计: active_training 删除时级联清理审计日志

CREATE TABLE IF NOT EXISTS active_training_audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  active_training_id INTEGER NOT NULL,
  trigger TEXT NOT NULL,
  from_state TEXT,
  to_state TEXT NOT NULL,
  actor TEXT NOT NULL DEFAULT 'main',
  context_json TEXT,
  occurred_at TEXT NOT NULL,
  FOREIGN KEY (active_training_id) REFERENCES active_training(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_atal_at_id
  ON active_training_audit_log(active_training_id, occurred_at);
