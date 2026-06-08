-- 014: 扩展 sessions 表
-- 添加 preview/manuscript_id/chapter_id 字段（V2 SOLO 模式数据层扩展）

ALTER TABLE sessions ADD COLUMN preview TEXT DEFAULT '';             -- 最后一条消息预览（截取前 80 字）
ALTER TABLE sessions ADD COLUMN manuscript_id TEXT REFERENCES manuscripts(id);
ALTER TABLE sessions ADD COLUMN chapter_id TEXT REFERENCES chapters(id);
