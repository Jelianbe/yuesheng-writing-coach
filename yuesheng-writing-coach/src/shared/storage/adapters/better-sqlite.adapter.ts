/**
 * BetterSqliteAdapter — Sprint 26
 *
 * Windows / Electron 端存储实现
 * - 基于 better-sqlite3(同步 Node.js 原生 SQLite 绑定)
 * - 所有方法 Promise 化(R-020 + WebView 兼容)
 * - schema 在 initialize() 内一次性 CREATE TABLE IF NOT EXISTS
 *
 * 5 张核心表 schema 同步:
 *   - sessions(001)
 *   - projects(021)
 *   - active_training(026+027)
 *   - teaching_state(002)
 *   - training_records(015)
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.3
 * 决策: D-074
 */
import type Database from 'better-sqlite3';
import type {
  ExecuteResult,
  StorageAdapter,
  TransactionContext,
} from '../storage-adapter';
import { StorageError } from '../storage-adapter';
import type { DatabaseRow, QueryParam, StorageInitConfig } from '../storage-types';

export interface BetterSqliteAdapterOptions extends StorageInitConfig {
  /** better-sqlite3 数据库实例(由调用方注入,便于测试用 in-memory DB) */
  db: Database.Database;
}

export class BetterSqliteAdapter implements StorageAdapter {
  readonly engine = 'better-sqlite3' as const;
  private readonly db: Database.Database;
  private initialized = false;

  constructor(options: BetterSqliteAdapterOptions) {
    this.db = options.db;
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;
    try {
      this.initSchema();
      this.initialized = true;
    } catch (e) {
      throw new StorageError('BetterSqliteAdapter.initialize failed', e);
    }
  }

  async query<T extends DatabaseRow = DatabaseRow>(
    sql: string,
    params: QueryParam[] = [],
  ): Promise<T[]> {
    this.assertInitialized();
    try {
      const stmt = this.db.prepare(sql);
      return stmt.all(...this.serializeParams(params)) as T[];
    } catch (e) {
      throw new StorageError(`query failed: ${sql}`, e, sql);
    }
  }

  async queryOne<T extends DatabaseRow = DatabaseRow>(
    sql: string,
    params: QueryParam[] = [],
  ): Promise<T | null> {
    const rows = await this.query<T>(sql, params);
    return rows[0] ?? null;
  }

  async execute(
    sql: string,
    params: QueryParam[] = [],
  ): Promise<ExecuteResult> {
    this.assertInitialized();
    try {
      const stmt = this.db.prepare(sql);
      const result = stmt.run(...this.serializeParams(params));
      return {
        changes: result.changes,
        lastInsertId: result.lastInsertRowid as number,
      };
    } catch (e) {
      throw new StorageError(`execute failed: ${sql}`, e, sql);
    }
  }

  async transaction<T>(fn: (tx: TransactionContext) => Promise<T>): Promise<T> {
    this.assertInitialized();
    // better-sqlite3 transaction 是同步,需包装成 Promise
    // 注意: better-sqlite3 的 transaction 函数是同步的,这里用 BEGIN/COMMIT 手动控制以支持 async fn
    await this.execute('BEGIN TRANSACTION');
    try {
      const result = await fn(this.createTransactionContext());
      await this.execute('COMMIT');
      return result;
    } catch (e) {
      await this.execute('ROLLBACK').catch(() => {
        // rollback 失败时仅记录,不覆盖原错误
      });
      throw e instanceof StorageError
        ? e
        : new StorageError('transaction failed', e);
    }
  }

  async close(): Promise<void> {
    if (!this.initialized) return;
    try {
      this.db.close();
      this.initialized = false;
    } catch (e) {
      throw new StorageError('close failed', e);
    }
  }

  // ─── 内部工具 ───

  private assertInitialized(): void {
    if (!this.initialized) {
      throw new StorageError('Adapter not initialized. Call initialize() first.');
    }
  }

  private serializeParams(params: QueryParam[]): unknown[] {
    return params.map((p) => {
      if (p instanceof Date) return p.toISOString();
      if (p instanceof Uint8Array) return Buffer.from(p);
      return p;
    });
  }

  private createTransactionContext(): TransactionContext {
    return {
      query: (sql, params) => this.query(sql, params),
      execute: (sql, params) => this.execute(sql, params),
    };
  }

  /**
   * 初始化 5 张核心表 schema
   * - 使用 IF NOT EXISTS 保证幂等
   * - 完整 SQL 来自原 migration 文件,本轮 S26 限定 5 张核心表
   * - 未来 S27+ 需实现版本化 migration 系统
   */
  private initSchema(): void {
    // sessions
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    `);

    // projects
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_projects_session
        ON projects(session_id);
    `);

    // active_training (Sprint 24 A-1 + Sprint 25 C-4 step_responses_json)
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS active_training (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        challenge_id TEXT NOT NULL,
        challenge_name TEXT,
        mode TEXT,
        current_step_index INTEGER NOT NULL DEFAULT 0,
        steps_json TEXT NOT NULL DEFAULT '[]',
        user_draft TEXT NOT NULL DEFAULT '',
        flow_type TEXT,
        training_flow_json TEXT,
        record_id TEXT,
        syndrome_id TEXT,
        original_quote TEXT,
        constraint_text TEXT,
        submission_result_json TEXT,
        step_responses_json TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'in_progress',
        started_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_active_training_status
        ON active_training(status);
    `);

    // teaching_state
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS teaching_state (
        session_id TEXT PRIMARY KEY,
        current_phase TEXT NOT NULL DEFAULT 'idle',
        active_training_id TEXT,
        last_event_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
    `);

    // training_records
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS training_records (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        challenge_id TEXT NOT NULL,
        flow_type TEXT,
        passed INTEGER NOT NULL DEFAULT 0,
        score REAL,
        feedback TEXT,
        started_at TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_training_records_session
        ON training_records(session_id);
    `);
  }
}
