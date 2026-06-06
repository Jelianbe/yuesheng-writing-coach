-- ============================================
-- Migration: 008_evidence.sql
-- Description: 创建证据表（四级 Evidence）和诊断-证据关联表
-- 依据：SPEC_Evidence_V1.md
-- Created: 2026-06-02
-- ============================================

CREATE TABLE IF NOT EXISTS evidence (
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
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_evidence_disease ON evidence(related_disease);
CREATE INDEX IF NOT EXISTS idx_evidence_ability ON evidence(related_ability);
CREATE INDEX IF NOT EXISTS idx_evidence_novel ON evidence(novel_id);
CREATE INDEX IF NOT EXISTS idx_evidence_level ON evidence(level);

CREATE TABLE IF NOT EXISTS diagnosis_evidence (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    diagnosis_id TEXT NOT NULL,
    evidence_id TEXT NOT NULL,
    relevance TEXT CHECK(relevance IN ('primary', 'supporting', 'contextual')),
    UNIQUE(diagnosis_id, evidence_id)
);

CREATE INDEX IF NOT EXISTS idx_de_diagnosis ON diagnosis_evidence(diagnosis_id);
CREATE INDEX IF NOT EXISTS idx_de_evidence ON diagnosis_evidence(evidence_id);
