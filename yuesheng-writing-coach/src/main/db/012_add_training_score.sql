-- 012: 训练记录新增 score 字段
-- 用于存储 Evaluator Agent 的 1-10 评分结果

ALTER TABLE user_training_records ADD COLUMN score INTEGER;
