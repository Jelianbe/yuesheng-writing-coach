-- ============================================
-- Migration: 011_add_locked_syndromes.sql
-- Description: 添加症候锁定字段，支持诊断结果跨轮次保持
-- Created: 2026-06-05
-- ============================================

ALTER TABLE teaching_state ADD COLUMN locked_syndromes TEXT DEFAULT '[]';
