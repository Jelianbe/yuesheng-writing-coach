/**
 * SessionService — Sprint 26 跨端版
 *
 * 双端共用,接 StorageAdapter:
 * - Electron 端: 用 BetterSqliteAdapter(走主进程,经 IPC)
 * - Android 端: 用 CapacitorSqliteAdapter(走 WebView 直接调用)
 *
 * 关键差异(对比 main/shared/services/session.service.ts):
 * - 同步 → 异步
 * - `better-sqlite3.Database` → `StorageAdapter`
 * - 直接 prepare/run 改为 `adapter.query()` / `adapter.execute()` / `adapter.transaction()`
 *
 * 注意:
 * - 平台差异(crypto.randomUUID)由 globalThis 抹平,Web 与 Node 21+ 都有
 * - 原 Electron 端 main/shared/services/session.service.ts(sync, better-sqlite3)保留,
 *   用于保持现有 IPC handler 链路不动;本文件是 renderer 直接 import 的版本
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.2 / D-074
 */
import type { StorageAdapter } from '../storage/storage-adapter';
import type { DatabaseRow } from '../storage/storage-types';

export interface SessionRow extends DatabaseRow {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
}

export interface MessageRow extends DatabaseRow {
  id: string;
  session_id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: number;
}

export class SessionService {
  constructor(private readonly adapter: StorageAdapter) {}

  async listSessions(): Promise<SessionRow[]> {
    return this.adapter.query<SessionRow>(
      'SELECT * FROM sessions ORDER BY updated_at DESC',
    );
  }

  async createSession(): Promise<SessionRow> {
    const id = this.generateUUID();
    const now = new Date().toISOString();
    await this.adapter.execute(
      'INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [id, '新建会话', now, now],
    );
    return { id, title: '新建会话', created_at: now, updated_at: now };
  }

  async deleteSession(sessionId: string): Promise<void> {
    await this.adapter.execute('DELETE FROM sessions WHERE id = ?', [sessionId]);
  }

  async renameSession(sessionId: string, title: string): Promise<void> {
    const now = new Date().toISOString();
    await this.adapter.execute(
      'UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?',
      [title, now, sessionId],
    );
  }

  async saveMessage(
    sessionId: string,
    role: 'user' | 'assistant' | 'system',
    content: string,
  ): Promise<MessageRow> {
    const id = this.generateUUID();
    const timestamp = Date.now();
    await this.adapter.transaction(async (tx) => {
      await tx.execute(
        'INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)',
        [id, sessionId, role, content, timestamp],
      );
      await tx.execute(
        'UPDATE sessions SET updated_at = ? WHERE id = ?',
        [new Date().toISOString(), sessionId],
      );
    });
    return { id, session_id: sessionId, role, content, timestamp };
  }

  async getMessages(sessionId: string): Promise<MessageRow[]> {
    return this.adapter.query<MessageRow>(
      'SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC',
      [sessionId],
    );
  }

  async getMessagesPaged(
    sessionId: string,
    offset: number,
    limit: number,
  ): Promise<{ messages: MessageRow[]; total: number; hasMore: boolean }> {
    const totalRows = await this.adapter.queryOne<{ count: number }>(
      'SELECT COUNT(*) as count FROM messages WHERE session_id = ?',
      [sessionId],
    );
    const total = totalRows?.count ?? 0;
    const messages = await this.adapter.query<MessageRow>(
      'SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC LIMIT ? OFFSET ?',
      [sessionId, limit, offset],
    );
    return { messages, total, hasMore: offset + limit < total };
  }

  async getLastMessage(sessionId: string): Promise<MessageRow | null> {
    return this.adapter.queryOne<MessageRow>(
      'SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp DESC LIMIT 1',
      [sessionId],
    );
  }

  async searchMessages(
    query: string,
    limitPerSession: number = 5,
    maxSessions: number = 10,
  ): Promise<Array<{ sessionId: string; sessionTitle: string; messages: MessageRow[] }>> {
    const likePattern = `%${query}%`;
    const sessionIds = await this.adapter.query<{ session_id: string; title: string }>(
      `SELECT m.session_id, s.title
       FROM messages m
       LEFT JOIN sessions s ON s.id = m.session_id
       WHERE m.content LIKE ?
       GROUP BY m.session_id
       ORDER BY MAX(m.timestamp) DESC
       LIMIT ?`,
      [likePattern, maxSessions],
    );

    const results: Array<{ sessionId: string; sessionTitle: string; messages: MessageRow[] }> = [];
    for (const row of sessionIds) {
      const messages = await this.adapter.query<MessageRow>(
        'SELECT * FROM messages WHERE session_id = ? AND content LIKE ? ORDER BY timestamp ASC LIMIT ?',
        [row.session_id, likePattern, limitPerSession],
      );
      results.push({
        sessionId: row.session_id,
        sessionTitle: row.title || '未命名会话',
        messages,
      });
    }
    return results;
  }

  async getOrCreateDefaultSession(): Promise<SessionRow> {
    const sessions = await this.listSessions();
    if (sessions.length > 0) return sessions[0];
    return this.createSession();
  }

  /**
   * Sprint 26 阶段 2: 自动根据首条用户消息生成会话标题
   * - 移植自主进程旧版 SessionService(Sprint 14 前)
   * - 取首条 user 消息,截断 20 字作为标题
   */
  async autoGenerateTitle(sessionId: string): Promise<void> {
    const first = await this.adapter.queryOne<{ content: string }>(
      "SELECT content FROM messages WHERE session_id = ? AND role = 'user' ORDER BY timestamp ASC LIMIT 1",
      [sessionId],
    );
    if (!first) return;
    const title = first.content.length > 20 ? first.content.slice(0, 20) + '...' : first.content;
    await this.renameSession(sessionId, title);
  }

  private generateUUID(): string {
    // Web Crypto API 在 WebView 和 Node 21+ 都有
    return globalThis.crypto.randomUUID();
  }
}
