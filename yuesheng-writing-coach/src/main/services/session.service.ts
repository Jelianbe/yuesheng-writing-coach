import crypto from 'node:crypto';
import Database from 'better-sqlite3';

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
    this.db.prepare('INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)').run(id, sessionId, role, content, timestamp);
    this.db.prepare('UPDATE sessions SET updated_at = ? WHERE id = ?').run(new Date().toISOString(), sessionId);
    return { id, session_id: sessionId, role, content, timestamp };
  }

  getMessages(sessionId: string): MessageRow[] {
    return this.db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC').all(sessionId) as MessageRow[];
  }

  getLastMessage(sessionId: string): MessageRow | undefined {
    return this.db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp DESC LIMIT 1').get(sessionId) as MessageRow | undefined;
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
