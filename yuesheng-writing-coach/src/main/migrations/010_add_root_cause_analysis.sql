-- 010_add_root_cause_analysis.sql
-- 在 diagnosis_results 表中新增 root_cause_analysis 字段
-- 用于存储 Diagnosis Agent 的结构化分析结果 JSON

ALTER TABLE diagnosis_results ADD COLUMN root_cause_analysis TEXT;
