-- 013_manuscripts.sql
-- 作品与章节表

CREATE TABLE IF NOT EXISTS manuscripts (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  genre TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'archived')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE TABLE IF NOT EXISTS chapters (
  id TEXT PRIMARY KEY,
  manuscript_id TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  word_count INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft', 'revising', 'complete')),
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_chapters_manuscript_id ON chapters(manuscript_id);
CREATE INDEX IF NOT EXISTS idx_chapters_sort_order ON chapters(manuscript_id, sort_order);
