import crypto from 'node:crypto';
import type Database from 'better-sqlite3';

export interface SessionRow {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
}

export interface MessageRow {
  id: string;
  session_id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: number;
}

export class SessionService {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  listSessions(): SessionRow[] {
    return this.db.prepare('SELECT * FROM sessions ORDER BY updated_at DESC').all() as SessionRow[];
  }

  createSession(): SessionRow {
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    this.db.prepare('INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)').run(id, '新建会话', now, now);
    return { id, title: '新建会话', created_at: now, updated_at: now };
  }

  deleteSession(sessionId: string): void {
    this.db.prepare('DELETE FROM sessions WHERE id = ?').run(sessionId);
  }

  renameSession(sessionId: string, title: string): void {
    const now = new Date().toISOString();
    this.db.prepare('UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?').run(title, now, sessionId);
  }

  saveMessage(sessionId: string, role: 'user' | 'assistant' | 'system', content: string): MessageRow {
    const id = crypto.randomUUID();
    const timestamp = Date.now();
    const saveTransaction = this.db.transaction(() => {
      this.db.prepare('INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)').run(id, sessionId, role, content, timestamp);
      this.db.prepare('UPDATE sessions SET updated_at = ? WHERE id = ?').run(new Date().toISOString(), sessionId);
    });
    saveTransaction();
    return { id, session_id: sessionId, role, content, timestamp };
  }

  getMessages(sessionId: string): MessageRow[] {
    return this.db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC').all(sessionId) as MessageRow[];
  }

  getMessagesPaged(sessionId: string, offset: number, limit: number): { messages: MessageRow[]; total: number; hasMore: boolean } {
    const total = (this.db.prepare('SELECT COUNT(*) as count FROM messages WHERE session_id = ?').get(sessionId) as { count: number }).count;
    const messages = this.db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC LIMIT ? OFFSET ?').all(sessionId, limit, offset) as MessageRow[];
    return { messages, total, hasMore: offset + limit < total };
  }

  getLastMessage(sessionId: string): MessageRow | undefined {
    return this.db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp DESC LIMIT 1').get(sessionId) as MessageRow | undefined;
  }

  searchMessages(query: string, limitPerSession: number = 5, maxSessions: number = 10): Array<{ sessionId: string; sessionTitle: string; messages: MessageRow[] }> {
    const likePattern = `%${query}%`;
    const sessionIds = this.db.prepare(
      `SELECT m.session_id, s.title
       FROM messages m
       LEFT JOIN sessions s ON s.id = m.session_id
       WHERE m.content LIKE ?
       GROUP BY m.session_id
       ORDER BY MAX(m.timestamp) DESC
       LIMIT ?`
    ).all(likePattern, maxSessions) as { session_id: string; title: string }[];

    return sessionIds.map(row => {
      const messages = this.db.prepare(
        'SELECT * FROM messages WHERE session_id = ? AND content LIKE ? ORDER BY timestamp ASC LIMIT ?'
      ).all(row.session_id, likePattern, limitPerSession) as MessageRow[];
      return {
        sessionId: row.session_id,
        sessionTitle: row.title || '未命名会话',
        messages,
      };
    });
  }

  autoGenerateTitle(sessionId: string): void {
    const first = this.db.prepare("SELECT content FROM messages WHERE session_id = ? AND role = 'user' ORDER BY timestamp ASC LIMIT 1").get(sessionId) as { content: string } | undefined;
    if (first) {
      const title = first.content.length > 20 ? first.content.slice(0, 20) + '...' : first.content;
      this.renameSession(sessionId, title);
    }
  }

  getOrCreateDefaultSession(): SessionRow {
    const sessions = this.listSessions();
    if (sessions.length > 0) return sessions[0];
    return this.createSession();
  }
}
