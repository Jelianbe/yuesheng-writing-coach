-- 020_db_add_task_type.sql
-- 为 user_training_records 表添加 task_type 列，支持训练类型区分
-- 升级：G-01 DB Migration
-- 回滚：ALTER TABLE user_training_records DROP COLUMN task_type;

ALTER TABLE user_training_records ADD COLUMN task_type TEXT NOT NULL DEFAULT 'writing' CHECK(task_type IN ('writing', 'reading', 'reflection', 'technique'));
