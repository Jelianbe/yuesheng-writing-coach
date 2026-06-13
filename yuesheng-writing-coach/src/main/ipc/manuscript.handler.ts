import crypto from 'node:crypto';
import { IPC_CHANNELS } from '../../shared/constants';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';
import Database from 'better-sqlite3';

export interface ManuscriptHandlerDeps {
  db: Database.Database;
}

let deps: ManuscriptHandlerDeps | null = null;

export function initManuscriptHandlers(d: ManuscriptHandlerDeps): void {
  deps = d;
}

export function registerManuscriptHandlers(): void {
  if (!deps) throw new Error('ManuscriptHandler deps not injected');

  // manuscript:list — 获取作品列表
  createHandler(IPC_CHANNELS.MANUSCRIPT_LIST, () => {
    const rows = deps!.db.prepare('SELECT * FROM manuscripts ORDER BY sort_order ASC, created_at DESC').all();
    return rows;
  });

  // manuscript:get — 获取单个作品详情
  createHandler(IPC_CHANNELS.MANUSCRIPT_GET, (_event, args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const row = deps!.db.prepare('SELECT * FROM manuscripts WHERE id = ?').get(validation.data.id);
    return row || null;
  });

  // manuscript:create — 创建新作品
  createHandler(IPC_CHANNELS.MANUSCRIPT_CREATE, (_event, args) => {
    const validation = validatePayload<{ title: string; description?: string; genre?: string }>(args, {
      required: ['title'],
      types: { title: 'string', description: 'string', genre: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const id = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    deps!.db.prepare(
      'INSERT INTO manuscripts (id, title, description, genre, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(id, validation.data.title, validation.data.description || '', validation.data.genre || '', now, now);
    const row = deps!.db.prepare('SELECT * FROM manuscripts WHERE id = ?').get(id);
    return row;
  });

  // manuscript:update — 更新作品信息
  createHandler(IPC_CHANNELS.MANUSCRIPT_UPDATE, (_event, args) => {
    const validation = validatePayload<{ id: string; title?: string; description?: string; genre?: string; status?: 'active' | 'archived' }>(args, {
      required: ['id'],
      types: { id: 'string', title: 'string', description: 'string', genre: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const now = Math.floor(Date.now() / 1000);
    const sets: string[] = ['updated_at = ?'];
    const values: unknown[] = [now];
    if (validation.data.title !== undefined) { sets.push('title = ?'); values.push(validation.data.title); }
    if (validation.data.description !== undefined) { sets.push('description = ?'); values.push(validation.data.description); }
    if (validation.data.genre !== undefined) { sets.push('genre = ?'); values.push(validation.data.genre); }
    if (validation.data.status !== undefined) { sets.push('status = ?'); values.push(validation.data.status); }
    values.push(validation.data.id);
    deps!.db.prepare(`UPDATE manuscripts SET ${sets.join(', ')} WHERE id = ?`).run(...values);
    const row = deps!.db.prepare('SELECT * FROM manuscripts WHERE id = ?').get(validation.data.id);
    return row;
  });

  // chapter:list — 获取某作品的所有章节
  createHandler(IPC_CHANNELS.CHAPTER_LIST, (_event, args) => {
    const validation = validatePayload<{ manuscriptId: string }>(args, { required: ['manuscriptId'], types: { manuscriptId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const rows = deps!.db.prepare('SELECT * FROM chapters WHERE manuscript_id = ? ORDER BY sort_order ASC').all(validation.data.manuscriptId);
    return rows;
  });

  // chapter:get — 获取单个章节（含内容）
  createHandler(IPC_CHANNELS.CHAPTER_GET, (_event, args) => {
    const validation = validatePayload<{ id: string }>(args, { required: ['id'], types: { id: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const row = deps!.db.prepare('SELECT * FROM chapters WHERE id = ?').get(validation.data.id);
    return row || null;
  });

  // chapter:create — 创建新章节
  createHandler(IPC_CHANNELS.CHAPTER_CREATE, (_event, args) => {
    const validation = validatePayload<{ manuscriptId: string; title: string }>(args, { required: ['manuscriptId', 'title'], types: { manuscriptId: 'string', title: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const id = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    const maxSort = deps!.db.prepare('SELECT MAX(sort_order) as max FROM chapters WHERE manuscript_id = ?').get(validation.data.manuscriptId) as { max: number | null } | undefined;
    const sortOrder = (maxSort?.max ?? -1) + 1;
    deps!.db.prepare(
      'INSERT INTO chapters (id, manuscript_id, title, content, word_count, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    ).run(id, validation.data.manuscriptId, validation.data.title, '', 0, sortOrder, now, now);
    const row = deps!.db.prepare('SELECT * FROM chapters WHERE id = ?').get(id);
    return row;
  });

  // manuscript:delete — 删除作品及其所有章节
  createHandler(IPC_CHANNELS.MANUSCRIPT_DELETE, (_event, args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    deps!.db.transaction(() => {
      deps!.db.prepare('DELETE FROM chapters WHERE manuscript_id = ?').run(validation.data.id);
      deps!.db.prepare('DELETE FROM manuscripts WHERE id = ?').run(validation.data.id);
    })();
    return { deleted: true };
  });

  // chapter:delete — 删除单个章节
  createHandler(IPC_CHANNELS.CHAPTER_DELETE, (_event, args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    deps!.db.prepare('DELETE FROM chapters WHERE id = ?').run(validation.data.id);
    return { deleted: true };
  });

  // chapter:updateContent — 更新章节正文
  createHandler(IPC_CHANNELS.CHAPTER_UPDATE_CONTENT, (_event, args) => {
    const validation = validatePayload<{ id: string; content: string }>(args, { required: ['id', 'content'], types: { id: 'string', content: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const wordCount = validation.data.content.replace(/[\s\n\r]+/g, '').length;
    const now = Math.floor(Date.now() / 1000);
    deps!.db.prepare('UPDATE chapters SET content = ?, word_count = ?, updated_at = ? WHERE id = ?')
      .run(validation.data.content, wordCount, now, validation.data.id);
    return { wordCount };
  });
}
