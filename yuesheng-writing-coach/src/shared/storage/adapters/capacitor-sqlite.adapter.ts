/**
 * CapacitorSqliteAdapter — Sprint 26 真实实现
 *
 * Android / Capacitor 端存储实现
 * - 基于 @capacitor-community/sqlite 8.x
 * - 使用 SQLiteConnection 高级 API
 * - 平台:Android (iOS 通过相同 API 可扩展)
 *
 * 关键差异(better-sqlite3 → capacitor-sqlite):
 * - 同步 → 异步(已处理)
 * - `Database.Database` → `SQLiteDBConnection`
 * - `prepare(sql).all(values)` → `query(sql, values)`
 * - `prepare(sql).run(values)` → `run(sql, values)`
 * - `db.transaction(fn)` → `beginTransaction()` + `commitTransaction()` / `rollbackTransaction()`
 *
 * 注意:web 平台下 @capacitor-community/sqlite 走 WASM fallback,
 *     在 vite dev server 直接跑会 mock。本文件主要在 Android WebView 中生效。
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.2 / D-074
 */
import { CapacitorSQLite, SQLiteConnection } from '@capacitor-community/sqlite';
import type { SQLiteDBConnection } from '@capacitor-community/sqlite';
import type {
  ExecuteResult,
  StorageAdapter,
  TransactionContext,
} from '../storage-adapter';
import { StorageError } from '../storage-adapter';
import type { DatabaseRow, QueryParam, StorageInitConfig } from '../storage-types';

export type CapacitorSqliteAdapterOptions = StorageInitConfig;

export class CapacitorSqliteAdapter implements StorageAdapter {
  readonly engine = 'capacitor-sqlite' as const;
  private readonly dbName: string;
  private readonly version: number;
  private connection: SQLiteDBConnection | null = null;
  private initialized = false;

  constructor(options: CapacitorSqliteAdapterOptions) {
    if (!options.dbName) {
      throw new StorageError('CapacitorSqliteAdapter: dbName is required');
    }
    this.dbName = options.dbName;
    this.version = options.version ?? 1;
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;
    try {
      const sqlite = new SQLiteConnection(CapacitorSQLite);
      this.connection = await sqlite.createConnection(
        this.dbName,
        false,
        'no-encryption',
        this.version,
        false,
      );
      await this.connection.open();
      await this.initSchema();
      this.initialized = true;
    } catch (e) {
      throw new StorageError('CapacitorSqliteAdapter.initialize failed', e);
    }
  }

  async query<T extends DatabaseRow = DatabaseRow>(
    sql: string,
    params: QueryParam[] = [],
  ): Promise<T[]> {
    this.assertInitialized();
    try {
      const result = await this.connection!.query(sql, params);
      // Android 端 query 返回 { values: Array<Record<string, any>> }
      // 兼容空结果
      if (!result.values || result.values.length === 0) return [];
      return result.values as unknown as T[];
    } catch (e) {
      throw new StorageError('CapacitorSqliteAdapter.query failed', e, sql);
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
      const result = await this.connection!.run(sql, params);
      return {
        changes: result.changes?.changes ?? 0,
        lastInsertId: Number(result.changes?.lastId ?? 0),
      };
    } catch (e) {
      throw new StorageError('CapacitorSqliteAdapter.execute failed', e, sql);
    }
  }

  async transaction<T>(fn: (tx: TransactionContext) => Promise<T>): Promise<T> {
    this.assertInitialized();
    const txContext: TransactionContext = {
      query: <U extends DatabaseRow = DatabaseRow>(sql: string, params: QueryParam[] = []) =>
        this.query<U>(sql, params),
      execute: (sql: string, params: QueryParam[] = []) => this.execute(sql, params),
    };
    let inTransaction = true;
    try {
      await this.connection!.beginTransaction();
      const result = await fn(txContext);
      await this.connection!.commitTransaction();
      inTransaction = false;
      return result;
    } catch (e) {
      if (inTransaction) {
        try {
          await this.connection!.rollbackTransaction();
        } catch (rollbackErr) {
          // 静默:回滚失败不应掩盖原始错误
        }
      }
      throw new StorageError('CapacitorSqliteAdapter.transaction failed', e);
    }
  }

  async close(): Promise<void> {
    if (!this.initialized || !this.connection) return;
    try {
      await this.connection.close();
      this.initialized = false;
      this.connection = null;
    } catch (e) {
      throw new StorageError('CapacitorSqliteAdapter.close failed', e);
    }
  }

  private assertInitialized(): void {
    if (!this.initialized || !this.connection) {
      throw new StorageError(
        'CapacitorSqliteAdapter: not initialized. Call initialize() first.',
      );
    }
  }

  private async initSchema(): Promise<void> {
    // 5 张核心表 — 与 BetterSqliteAdapter 对齐
    const statements = [
      `CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS active_training (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        status TEXT NOT NULL,
        step_responses_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS teaching_state (
        session_id TEXT PRIMARY KEY,
        state_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )`,
    ];
    for (const sql of statements) {
      await this.connection!.run(sql);
    }
  }
}
