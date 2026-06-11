import crypto from 'node:crypto';
import { ipcMain } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { apiSuccess, apiError } from '../../renderer/shared/types';
import { validatePayload } from './utils/validate-payload';
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
  ipcMain.handle(IPC_CHANNELS.MANUSCRIPT_LIST, () => {
    try {
      const rows = deps!.db.prepare('SELECT * FROM manuscripts ORDER BY sort_order ASC, created_at DESC').all();
      return apiSuccess(rows);
    } catch (error) {
      console.error('[ManuscriptHandler] MANUSCRIPT_LIST Error:', error);
      return apiError(String(error));
    }
  });

  // manuscript:get — 获取单个作品详情
  ipcMain.handle(IPC_CHANNELS.MANUSCRIPT_GET, (_event, args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      const row = deps!.db.prepare('SELECT * FROM manuscripts WHERE id = ?').get(validation.data.id);
      return apiSuccess(row || null);
    } catch (error) {
      console.error('[ManuscriptHandler] MANUSCRIPT_GET Error:', error);
      return apiError(String(error));
    }
  });

  // manuscript:create — 创建新作品
  ipcMain.handle(IPC_CHANNELS.MANUSCRIPT_CREATE, (_event, args) => {
    const validation = validatePayload<{ title: string; description?: string; genre?: string }>(args, {
      required: ['title'],
      types: { title: 'string', description: 'string', genre: 'string' },
    });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      const id = crypto.randomUUID();
      const now = Math.floor(Date.now() / 1000);
      deps!.db.prepare(
        'INSERT INTO manuscripts (id, title, description, genre, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
      ).run(id, validation.data.title, validation.data.description || '', validation.data.genre || '', now, now);
      const row = deps!.db.prepare('SELECT * FROM manuscripts WHERE id = ?').get(id);
      return apiSuccess(row);
    } catch (error) {
      console.error('[ManuscriptHandler] MANUSCRIPT_CREATE Error:', error);
      return apiError(String(error));
    }
  });

  // manuscript:update — 更新作品信息
  ipcMain.handle(IPC_CHANNELS.MANUSCRIPT_UPDATE, (_event, args) => {
    const validation = validatePayload<{ id: string; title?: string; description?: string; genre?: string; status?: 'active' | 'archived' }>(args, {
      required: ['id'],
      types: { id: 'string', title: 'string', description: 'string', genre: 'string' },
    });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
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
      return apiSuccess(row);
    } catch (error) {
      console.error('[ManuscriptHandler] MANUSCRIPT_UPDATE Error:', error);
      return apiError(String(error));
    }
  });

  // chapter:list — 获取某作品的所有章节
  ipcMain.handle(IPC_CHANNELS.CHAPTER_LIST, (_event, args: { manuscriptId: string }) => {
    try {
      const rows = deps!.db.prepare('SELECT * FROM chapters WHERE manuscript_id = ? ORDER BY sort_order ASC').all(args.manuscriptId);
      return apiSuccess(rows);
    } catch (error) {
      console.error('[ManuscriptHandler] CHAPTER_LIST Error:', error);
      return apiError(String(error));
    }
  });

  // chapter:get — 获取单个章节（含内容）
  ipcMain.handle(IPC_CHANNELS.CHAPTER_GET, (_event, args: { id: string }) => {
    try {
      const row = deps!.db.prepare('SELECT * FROM chapters WHERE id = ?').get(args.id);
      return apiSuccess(row || null);
    } catch (error) {
      console.error('[ManuscriptHandler] CHAPTER_GET Error:', error);
      return apiError(String(error));
    }
  });

  // chapter:create — 创建新章节
  ipcMain.handle(IPC_CHANNELS.CHAPTER_CREATE, (_event, args: { manuscriptId: string; title: string }) => {
    try {
      const id = crypto.randomUUID();
      const now = Math.floor(Date.now() / 1000);
      const maxSort = deps!.db.prepare('SELECT MAX(sort_order) as max FROM chapters WHERE manuscript_id = ?').get(args.manuscriptId) as { max: number | null } | undefined;
      const sortOrder = (maxSort?.max ?? -1) + 1;
      deps!.db.prepare(
        'INSERT INTO chapters (id, manuscript_id, title, content, word_count, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).run(id, args.manuscriptId, args.title, '', 0, sortOrder, now, now);
      const row = deps!.db.prepare('SELECT * FROM chapters WHERE id = ?').get(id);
      return apiSuccess(row);
    } catch (error) {
      console.error('[ManuscriptHandler] CHAPTER_CREATE Error:', error);
      return apiError(String(error));
    }
  });

  // manuscript:delete — 删除作品及其所有章节
  ipcMain.handle(IPC_CHANNELS.MANUSCRIPT_DELETE, (_event, args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      const transaction = deps!.db.transaction(() => {
        // 先删除该作品下所有章节
        deps!.db.prepare('DELETE FROM chapters WHERE manuscript_id = ?').run(validation.data.id);
        // 再删除作品本身
        deps!.db.prepare('DELETE FROM manuscripts WHERE id = ?').run(validation.data.id);
      });
      transaction();
      return apiSuccess({ deleted: true });
    } catch (error) {
      console.error('[ManuscriptHandler] MANUSCRIPT_DELETE Error:', error);
      return apiError(String(error));
    }
  });

  // chapter:delete — 删除单个章节
  ipcMain.handle(IPC_CHANNELS.CHAPTER_DELETE, (_event, args) => {
    const validation = validatePayload<{ id: string }>(args, {
      required: ['id'],
      types: { id: 'string' },
    });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      deps!.db.prepare('DELETE FROM chapters WHERE id = ?').run(validation.data.id);
      return apiSuccess({ deleted: true });
    } catch (error) {
      console.error('[ManuscriptHandler] CHAPTER_DELETE Error:', error);
      return apiError(String(error));
    }
  });

  // chapter:updateContent — 更新章节正文
  ipcMain.handle(IPC_CHANNELS.CHAPTER_UPDATE_CONTENT, (_event, args: { id: string; content: string }) => {
    try {
      const wordCount = args.content.replace(/[\s\n\r]+/g, '').length;
      const now = Math.floor(Date.now() / 1000);
      deps!.db.prepare('UPDATE chapters SET content = ?, word_count = ?, updated_at = ? WHERE id = ?')
        .run(args.content, wordCount, now, args.id);
      return apiSuccess({ wordCount });
    } catch (error) {
      console.error('[ManuscriptHandler] CHAPTER_UPDATE_CONTENT Error:', error);
      return apiError(String(error));
    }
  });
}
