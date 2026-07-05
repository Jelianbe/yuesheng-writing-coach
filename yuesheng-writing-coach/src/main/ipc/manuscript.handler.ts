/**
 * 作品 + 章节管理 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('manuscript:list' | 'manuscript:get' | 'manuscript:create' | 'manuscript:update' | 'manuscript:delete' | 'chapter:list' | 'chapter:get' | 'chapter:create' | 'chapter:delete' | 'chapter:updateContent', ...)`
 *
 * 注: 11 个 channel 全部 SQL 直调(主进程 SQLite)。
 *    Android 端 StorageAdapter 完整化后考虑统一迁移到 storage handler。
 */

import crypto from 'node:crypto';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';
import type Database from 'better-sqlite3';

export interface ManuscriptHandlerDeps {
  db: Database.Database;
}

let deps: ManuscriptHandlerDeps | null = null;

export function initManuscriptHandlers(d: ManuscriptHandlerDeps): void {
  deps = d;
}

export function registerManuscriptHandlers(): void {
  if (!deps) throw new Error('ManuscriptHandler deps not injected');
  const d = deps;

  registerMethod('manuscript:list', async (_args) => {
    const rows = d.db.prepare('SELECT * FROM manuscripts ORDER BY sort_order ASC, created_at DESC').all();
    return rows;
  });

  registerMethod('manuscript:get', async (args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const row = d.db.prepare('SELECT * FROM manuscripts WHERE id = ?').get(validation.data.id);
    return row || null;
  });

  registerMethod('manuscript:create', async (args) => {
    const validation = validatePayload<{ title: string; description?: string; genre?: string }>(args, {
      required: ['title'],
      types: { title: 'string', description: 'string', genre: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const id = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    d.db.prepare(
      'INSERT INTO manuscripts (id, title, description, genre, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(id, validation.data.title, validation.data.description || '', validation.data.genre || '', now, now);
    const row = d.db.prepare('SELECT * FROM manuscripts WHERE id = ?').get(id);
    return row;
  });

  registerMethod('manuscript:update', async (args) => {
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
    d.db.prepare(`UPDATE manuscripts SET ${sets.join(', ')} WHERE id = ?`).run(...values);
    const row = d.db.prepare('SELECT * FROM manuscripts WHERE id = ?').get(validation.data.id);
    return row;
  });

  registerMethod('chapter:list', async (args) => {
    const validation = validatePayload<{ manuscriptId: string }>(args, { required: ['manuscriptId'], types: { manuscriptId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const rows = d.db.prepare('SELECT * FROM chapters WHERE manuscript_id = ? ORDER BY sort_order ASC').all(validation.data.manuscriptId);
    return rows;
  });

  registerMethod('chapter:get', async (args) => {
    const validation = validatePayload<{ id: string }>(args, { required: ['id'], types: { id: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const row = d.db.prepare('SELECT * FROM chapters WHERE id = ?').get(validation.data.id);
    return row || null;
  });

  registerMethod('chapter:create', async (args) => {
    const validation = validatePayload<{ manuscriptId: string; title: string }>(args, { required: ['manuscriptId', 'title'], types: { manuscriptId: 'string', title: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const id = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    const maxSort = d.db.prepare('SELECT MAX(sort_order) as max FROM chapters WHERE manuscript_id = ?').get(validation.data.manuscriptId) as { max: number | null } | undefined;
    const sortOrder = (maxSort?.max ?? -1) + 1;
    d.db.prepare(
      'INSERT INTO chapters (id, manuscript_id, title, content, word_count, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    ).run(id, validation.data.manuscriptId, validation.data.title, '', 0, sortOrder, now, now);
    const row = d.db.prepare('SELECT * FROM chapters WHERE id = ?').get(id);
    return row;
  });

  registerMethod('manuscript:delete', async (args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    d.db.transaction(() => {
      d.db.prepare('DELETE FROM chapters WHERE manuscript_id = ?').run(validation.data.id);
      d.db.prepare('DELETE FROM manuscripts WHERE id = ?').run(validation.data.id);
    })();
    return { deleted: true };
  });

  registerMethod('chapter:delete', async (args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    d.db.prepare('DELETE FROM chapters WHERE id = ?').run(validation.data.id);
    return { deleted: true };
  });

  registerMethod('chapter:updateContent', async (args) => {
    const validation = validatePayload<{ id: string; content: string }>(args, { required: ['id', 'content'], types: { id: 'string', content: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const wordCount = validation.data.content.replace(/[\s\n\r]+/g, '').length;
    const now = Math.floor(Date.now() / 1000);
    d.db.prepare('UPDATE chapters SET content = ?, word_count = ?, updated_at = ? WHERE id = ?')
      .run(validation.data.content, wordCount, now, validation.data.id);
    return { wordCount };
  });
}
