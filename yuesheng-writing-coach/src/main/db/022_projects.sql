-- ============================================
-- Migration: 021_projects.sql
-- Description: 项目表(顶层数据组织单元)
--   - projects: 独立于会话/作品,作为顶层容器
--   - setting_tree: JSON 字段,存储项目设置树(小说设定/人物/情节大纲等)
--   - sessions/manuscripts 的 project_id 外键由 RWR-P0-5 数据迁移脚本添加
-- 升级：RWR-P0-4
-- 回滚：DROP INDEX IF EXISTS idx_projects_updated_at; DROP TABLE IF EXISTS projects;
-- Created: 2026-06-17
-- ============================================

BEGIN TRANSACTION;

-- ===== projects 表 =====
-- R-007 双向绑定: projectId 是 sessions/manuscripts 的外键目标(后续 P0-5 添加)
-- R-014 配置外置: settingTree 使用 JSON TEXT,避免硬编码结构
-- R-021 最小化范围: 本迁移只建表,不动 sessions/manuscripts(由 P0-5 处理)
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT DEFAULT NULL,
  setting_tree TEXT DEFAULT NULL,
  setting_tree_type TEXT NOT NULL DEFAULT 'main',
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

-- 按更新时间倒序索引(列表查询优化)
CREATE INDEX IF NOT EXISTS idx_projects_updated_at ON projects(updated_at DESC);

COMMIT;
