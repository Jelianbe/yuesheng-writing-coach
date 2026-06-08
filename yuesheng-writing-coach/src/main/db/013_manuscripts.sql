-- 013: 新建 manuscripts + chapters 表
-- 用于存储用户作品和章节内容（V2 SOLO 模式数据层基础）

CREATE TABLE IF NOT EXISTS manuscripts (
  id TEXT PRIMARY KEY,              -- UUID
  title TEXT NOT NULL,               -- 作品标题
  description TEXT DEFAULT '',       -- 作品简介
  genre TEXT DEFAULT '',             -- 类型/题材
  status TEXT DEFAULT 'active' CHECK(status IN ('active','archived')),
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
  sort_order INTEGER DEFAULT 0       -- 排序权重
);

CREATE TABLE IF NOT EXISTS chapters (
  id TEXT PRIMARY KEY,              -- UUID
  manuscript_id TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
  title TEXT NOT NULL,               -- 章节标题
  content TEXT DEFAULT '',           -- 正文内容（纯文本或 Markdown）
  word_count INTEGER DEFAULT 0,      -- 字数（缓存）
  sort_order INTEGER DEFAULT 0,
  status TEXT DEFAULT 'draft' CHECK(status IN ('draft','revising','complete')),
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_chapters_manuscript ON chapters(manuscript_id);
