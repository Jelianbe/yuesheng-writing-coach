-- 017: FTS5 全文搜索索引
-- 为 messages.content 提供高效全文搜索，替代 LIKE '%query%' 全表扫描
-- 依赖：SQLite 编译时启用 FTS5（better-sqlite3 默认启用）

CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    content,
    content=messages,
    content_rowid=rowid,
    tokenize='unicode61'
);

-- 初始填充：将现有消息内容导入 FTS5 索引
INSERT INTO messages_fts(rowid, content)
SELECT rowid, content FROM messages;

-- 创建触发器保持 FTS5 索引与 messages 表同步
CREATE TRIGGER IF NOT EXISTS trg_messages_fts_insert
AFTER INSERT ON messages
BEGIN
    INSERT INTO messages_fts(rowid, content)
    VALUES (new.rowid, new.content);
END;

CREATE TRIGGER IF NOT EXISTS trg_messages_fts_delete
AFTER DELETE ON messages
BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content)
    VALUES ('delete', old.rowid, old.content);
END;

CREATE TRIGGER IF NOT EXISTS trg_messages_fts_update
AFTER UPDATE OF content ON messages
BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content)
    VALUES ('delete', old.rowid, old.content);
    INSERT INTO messages_fts(rowid, content)
    VALUES (new.rowid, new.content);
END;
