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
    // better-sqlite3 是同步的,构造时直接初始化 schema
    this.initSchema();
    this.initialized = true;
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

    // messages (Sprint 26 阶段 2 补:SessionService 依赖)
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_messages_session
        ON messages(session_id);
    `);

    // projects
    // 注意:必须与 021_projects.sql 保持一致(主进程 handler 实际使用此 schema)
    // - name/setting_tree/setting_tree_type 字段
    // - created_at/updated_at 用 INTEGER unix 秒
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT DEFAULT NULL,
        setting_tree TEXT DEFAULT NULL,
        setting_tree_type TEXT NOT NULL DEFAULT 'main',
        created_at INTEGER NOT NULL DEFAULT (unixepoch()),
        updated_at INTEGER NOT NULL DEFAULT (unixepoch())
      );
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_projects_updated_at
        ON projects(updated_at DESC);
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
    // 注意:必须与 app-initializer.ensureBaseSchema 保持一致(主进程 store 实际使用此 schema)
    // 字段累积自多个 migration:
    //   - 003_create_teaching_state.sql 基础字段
    //   - 006_add_focus_area.sql focus_area
    //   - 011_add_locked_syndromes.sql locked_syndromes
    //   - 025_teaching_state_active_training.sql active_training_meta
    // JSON 数组字段(completed_actions/completed_tasks/active_problems/next_suggested_actions/locked_syndromes)
    // 全部用 TEXT 存 JSON 字符串,Service 层负责 parse/stringify
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS teaching_state (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL UNIQUE,
        current_phase TEXT NOT NULL DEFAULT 'P0_INIT',
        current_subphase TEXT,
        completed_actions TEXT NOT NULL DEFAULT '[]',
        completed_tasks TEXT NOT NULL DEFAULT '[]',
        active_problems TEXT NOT NULL DEFAULT '[]',
        next_suggested_actions TEXT NOT NULL DEFAULT '[]',
        current_task_id TEXT,
        diagnosis_summary TEXT NOT NULL DEFAULT '',
        last_user_confirmation TEXT,
        focus_area TEXT DEFAULT NULL,
        transition_offered INTEGER NOT NULL DEFAULT 0,
        locked_syndromes TEXT NOT NULL DEFAULT '[]',
        active_training_meta TEXT DEFAULT NULL,
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_teaching_state_session
        ON teaching_state(session_id);
    `);

    // user_training_records (Sprint 26 阶段 2 T26-2.4)
    // 注意:必须与 src/main/domains/04-validation/training/training-record.service.ts 实际使用对齐
    // 字段累积自多个 migration:
    //   - 015_db_create_user_training_records.sql 基础字段
    //   - 020_db_add_task_type.sql task_type
    // 表名 user_training_records(非 training_records),与生产环境一致
    // 开发态与 app-initializer.ensureBaseSchema 共存(IF NOT EXISTS,不冲突)
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS user_training_records (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        syndrome_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('assigned', 'completed', 'skipped')),
        assigned_at TEXT NOT NULL,
        completed_at TEXT,
        user_response TEXT,
        ai_feedback TEXT,
        effectiveness INTEGER CHECK(effectiveness IS NULL OR (effectiveness >= 1 AND effectiveness <= 5)),
        score INTEGER,
        task_type TEXT NOT NULL DEFAULT 'writing' CHECK(task_type IN ('writing', 'reading', 'reflection', 'technique')),
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_training_session
        ON user_training_records(session_id, assigned_at);
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_training_task
        ON user_training_records(task_id);
    `);
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_training_status
        ON user_training_records(session_id, status);
    `);
  }
}
