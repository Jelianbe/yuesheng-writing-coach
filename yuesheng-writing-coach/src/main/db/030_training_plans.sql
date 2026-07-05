-- Sprint 38: 自定义训练计划
-- 创建 training_plans 和 training_plan_items 表

CREATE TABLE IF NOT EXISTS training_plans (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS training_plan_items (
  id TEXT PRIMARY KEY,
  plan_id TEXT NOT NULL REFERENCES training_plans(id) ON DELETE CASCADE,
  challenge_id TEXT NOT NULL,
  technique_name TEXT NOT NULL,
  syndrome_id TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'in_progress', 'completed')),
  completed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tpi_plan_id ON training_plan_items(plan_id);
CREATE INDEX IF NOT EXISTS idx_tpi_status ON training_plan_items(status);
