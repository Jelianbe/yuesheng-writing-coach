-- ============================================
-- Migration: 025_evidence_offset.sql
-- Description: evidence 表新增 start_offset / end_offset 列（原文位置溯源）
--   - ADR-003 B-5：证据溯源增强
--   - chapter_id 列在 app-initializer.ts 中已存在（008_evidence.sql），
--     本迁移不重复添加（避免与既有 schema 冲突）
--   - 新增 2 列 + 1 索引
-- 升级：RWR-P0-? / Sprint 10 B-5
-- 回滚：见文件末尾
-- Created: 2026-06-22
-- ============================================

BEGIN TRANSACTION;

-- ===== 新增 start_offset / end_offset 列 =====
-- 字符单位（与 JS String.slice 语义一致）
-- 0-based inclusive / exclusive
-- 可空：老证据（无 offset 字段）继续按纯文本处理
ALTER TABLE evidence ADD COLUMN start_offset INTEGER;
ALTER TABLE evidence ADD COLUMN end_offset INTEGER;

-- ===== 索引 =====
-- 优化"按章节 + offset 范围查询"的常见场景
-- 例如：用户点击诊断卡片跳转到原文时，需要快速找出该章节的证据
CREATE INDEX IF NOT EXISTS idx_evidence_chapter_offset
  ON evidence(chapter_id, start_offset)
  WHERE chapter_id IS NOT NULL AND start_offset IS NOT NULL;

-- ===== 数据完整性（CHECK 约束） =====
-- SQLite 3.37+ 支持 CHECK（Electron 内置 SQLite 满足）
-- 保证 end_offset > start_offset（如果两者都不为 null）
-- 使用触发器实现（旧 SQLite 兼容）：

CREATE TRIGGER IF NOT EXISTS trg_evidence_offset_range
BEFORE INSERT ON evidence
FOR EACH ROW
WHEN NEW.start_offset IS NOT NULL
  AND NEW.end_offset IS NOT NULL
  AND NEW.end_offset <= NEW.start_offset
BEGIN
  SELECT RAISE(ABORT, 'evidence: end_offset must be > start_offset');
END;

CREATE TRIGGER IF NOT EXISTS trg_evidence_offset_range_update
BEFORE UPDATE ON evidence
FOR EACH ROW
WHEN NEW.start_offset IS NOT NULL
  AND NEW.end_offset IS NOT NULL
  AND NEW.end_offset <= NEW.start_offset
BEGIN
  SELECT RAISE(ABORT, 'evidence: end_offset must be > start_offset');
END;

COMMIT;

-- ============================================
-- 回滚脚本（手动执行，不自动运行）：
--
-- DROP TRIGGER IF EXISTS trg_evidence_offset_range_update;
-- DROP TRIGGER IF EXISTS trg_evidence_offset_range;
-- DROP INDEX IF EXISTS idx_evidence_chapter_offset;
-- ALTER TABLE evidence DROP COLUMN end_offset;
-- ALTER TABLE evidence DROP COLUMN start_offset;
-- ============================================
