-- ============================================
-- Migration: 024_teaching_decision_log.sql
-- Description: 教学决策记录层(Teaching Intelligence Layer)
--   依据 spec §8.2 / §8.3:Phase 1 = "写不读",积累数据待 Phase 4+ 回流优化
--   - teaching_decision_log: 教学策略选择记录(每条 syndrome 一行)
--   - 字段对齐 spec §8.2 数据结构
--   - decision_id PK, decision 与 DiagnosisEntry 关联
-- 升级:RWR-P1-6 (B-2)
-- 回滚:DROP TABLE teaching_decision_log;
-- Created: 2026-06-17
-- ============================================

BEGIN TRANSACTION;

-- ===== teaching_decision_log 表 =====
-- R-014 配置外置:strategy 枚举在 types 层,DB 层只存 string
-- R-021 隐性诊断:仅系统内部消费,不渲染到前端 UI
-- R-018 变更溯源:关联 sessionId + diagnosisId(syndromeId 来自 DiagnosisEntry)
CREATE TABLE IF NOT EXISTS teaching_decision_log (
  decision_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  syndrome_id TEXT NOT NULL,
  strategy_chosen TEXT NOT NULL,
  reason TEXT NOT NULL,
  student_state_json TEXT NOT NULL,
  decided_at INTEGER NOT NULL DEFAULT (unixepoch()),
  outcome TEXT DEFAULT NULL,
  outcome_at INTEGER DEFAULT NULL,
  notes TEXT DEFAULT NULL,
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- 索引:按会话快速取所有决策(Phase 4+ 回流优化用)
CREATE INDEX IF NOT EXISTS idx_teaching_decision_session
  ON teaching_decision_log(session_id, decided_at DESC);

-- 索引:按症候统计策略分布
CREATE INDEX IF NOT EXISTS idx_teaching_decision_syndrome
  ON teaching_decision_log(syndrome_id);

COMMIT;
