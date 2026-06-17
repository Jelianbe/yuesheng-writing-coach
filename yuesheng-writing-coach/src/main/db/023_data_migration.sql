-- ============================================
-- Migration: 022_data_migration.sql
-- Description: 数据迁移:RWR-P0-1 + RWR-P0-4 之后的旧数据接入新模型
--   1. sessions 表添加 project_id 字段
--   2. manuscripts 表添加 project_id 字段
--   3. 创建默认项目(固定 ID 'default-project',name='我的作品集')
--   4. 现有 sessions/manuscripts 归入默认项目
--   5. 诊断数据新字段默认值双保险
--   6. 索引
-- 升级:RWR-P0-5
-- 依赖:RWR-P0-1 (021_teaching_progress.sql) + RWR-P0-4 (021_projects.sql)
-- ============================================
--
-- 回滚限制说明(SQLite DDL 特性):
--   1. ALTER TABLE ADD COLUMN 不可事务回滚(SQLite DDL 在事务内部分不可逆)
--   2. 完整手动回滚:
--      ALTER TABLE sessions DROP COLUMN project_id;
--      ALTER TABLE manuscripts DROP COLUMN project_id;
--      DELETE FROM projects WHERE id = 'default-project';
--   3. 诊断数据 teaching_progress 默认值回滚无意义(021 已加默认值)
--
-- Created: 2026-06-17
-- ============================================

BEGIN TRANSACTION;

-- ===== 1. 添加 project_id 字段 =====
-- 字段可空:历史数据可能在迁移前已存在
-- FK ON DELETE SET NULL:删项目时 session/manuscript 保留,仅清空关联
ALTER TABLE sessions ADD COLUMN project_id TEXT REFERENCES projects(id) ON DELETE SET NULL;
ALTER TABLE manuscripts ADD COLUMN project_id TEXT REFERENCES projects(id) ON DELETE SET NULL;

-- ===== 2. 创建默认项目(幂等:固定 ID) =====
-- 固定 ID 'default-project' 保证重入安全(不会创建多个默认项目)
-- 同一 SQLite db 重复运行迁移,WHERE NOT EXISTS 跳过第二次
INSERT INTO projects (id, name, description, setting_tree, setting_tree_type, created_at, updated_at)
SELECT
  'default-project',
  '我的作品集',
  '自动创建的默认项目,包含所有现有作品与会话',
  NULL,
  'main',
  unixepoch(),
  unixepoch()
WHERE NOT EXISTS (SELECT 1 FROM projects WHERE id = 'default-project');

-- ===== 3. 现有数据归入默认项目(幂等:WHERE project_id IS NULL) =====
UPDATE sessions SET project_id = 'default-project' WHERE project_id IS NULL;
UPDATE manuscripts SET project_id = 'default-project' WHERE project_id IS NULL;

-- ===== 4. 诊断数据新字段默认值(双保险) =====
-- 021 迁移已添加 teaching_progress TEXT DEFAULT '[]',此处显式 UPDATE
-- 防御性:防止老数据在 021 之前 INSERT 且未触发默认值
UPDATE diagnosis_results SET teaching_progress = '[]' WHERE teaching_progress IS NULL;

-- ===== 5. 索引 =====
CREATE INDEX IF NOT EXISTS idx_sessions_project_id ON sessions(project_id);
CREATE INDEX IF NOT EXISTS idx_manuscripts_project_id ON manuscripts(project_id);

COMMIT;
