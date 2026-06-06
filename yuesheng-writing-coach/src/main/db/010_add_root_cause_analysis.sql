-- 010 新增 root_cause_analysis 列
-- 用于存储 Diagnosis Agent 的结构化因果分析结果
-- 依赖：005_diagnosis.sqlite 已创建 diagnosis_results 表

ALTER TABLE diagnosis_results ADD COLUMN root_cause_analysis TEXT;
