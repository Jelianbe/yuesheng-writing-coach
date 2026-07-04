/**
 * MemoryAdapter — Sprint 26 测试用
 *
 * 内存存储实现,用于单元测试 / 集成测试 / 阶段 1 PoC
 * - 不依赖 better-sqlite3,Node 环境下 pure JS 实现
 * - 支持 SQL 子集: SELECT / INSERT / UPDATE / DELETE / CREATE TABLE
 * - 不支持: ALTER TABLE / JOIN / 复杂函数(仅 PoC 用途,非生产)
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.2 测试策略
 * 决策: D-074
 */
import type {
  ExecuteResult,
  StorageAdapter,
  TransactionContext,
} from '../storage-adapter';
import { StorageError } from '../storage-adapter';
import type { DatabaseRow, QueryParam } from '../storage-types';

interface TableSchema {
  columns: string[];
  rows: Map<unknown, DatabaseRow>;
}

export class MemoryAdapter implements StorageAdapter {
  readonly engine = 'memory' as const;
  private tables = new Map<string, TableSchema>();
  private initialized = false;

  async initialize(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
  }

  async query<T extends DatabaseRow = DatabaseRow>(
    sql: string,
    params: QueryParam[] = [],
  ): Promise<T[]> {
    this.assertInitialized();
    const trimmed = sql.trim().toUpperCase();
    if (trimmed.startsWith('SELECT')) {
      return this.handleSelect<T>(sql, params);
    }
    throw new StorageError(`MemoryAdapter.query: unsupported SQL: ${sql}`, undefined, sql);
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
    const trimmed = sql.trim().toUpperCase();
    if (trimmed.startsWith('CREATE TABLE')) {
      this.handleCreateTable(sql);
      return { changes: 0, lastInsertId: 0 };
    }
    if (trimmed.startsWith('CREATE INDEX')) {
      return { changes: 0, lastInsertId: 0 };
    }
    if (trimmed.startsWith('BEGIN') || trimmed.startsWith('COMMIT') || trimmed.startsWith('ROLLBACK')) {
      return { changes: 0, lastInsertId: 0 };
    }
    if (trimmed.startsWith('INSERT')) {
      return this.handleInsert(sql, params);
    }
    if (trimmed.startsWith('UPDATE')) {
      return this.handleUpdate(sql, params);
    }
    if (trimmed.startsWith('DELETE')) {
      return this.handleDelete(sql, params);
    }
    throw new StorageError(`MemoryAdapter.execute: unsupported SQL: ${sql}`, undefined, sql);
  }

  async transaction<T>(fn: (tx: TransactionContext) => Promise<T>): Promise<T> {
    this.assertInitialized();
    const ctx = this.createTransactionContext();
    return fn(ctx);
  }

  async close(): Promise<void> {
    if (!this.initialized) return;
    this.tables.clear();
    this.initialized = false;
  }

  // ─── 内部 SQL 处理(仅支持 PoC 必需子集) ───

  private handleSelect<T extends DatabaseRow>(
    sql: string,
    params: QueryParam[],
  ): T[] {
    // 支持: SELECT [cols] FROM <table> [WHERE col = ?]
    const fromMatch = sql.match(/FROM\s+(\w+)/i);
    if (!fromMatch) throw new StorageError('SELECT missing FROM', undefined, sql);
    const tableName = fromMatch[1]!;
    const table = this.tables.get(tableName);
    if (!table) return [];

    let rows = Array.from(table.rows.values());

    // 极简 WHERE 支持: WHERE col = ?
    const whereMatch = sql.match(/WHERE\s+(\w+)\s*=\s*\?/i);
    if (whereMatch) {
      const col = whereMatch[1]!;
      const value = params[0];
      rows = rows.filter((r) => r[col] === value);
    }

    return rows as T[];
  }

  private handleCreateTable(sql: string): void {
    // CREATE TABLE <name> (col TYPE, ...)
    const match = sql.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)\s*\(([^)]+)\)/i);
    if (!match) throw new StorageError('CREATE TABLE parse failed', undefined, sql);
    const tableName = match[1]!;
    if (this.tables.has(tableName)) return;
    const colDefs = match[2]!.split(',').map((c) => c.trim().split(/\s+/)[0]!);
    this.tables.set(tableName, { columns: colDefs, rows: new Map() });
  }

  private handleInsert(
    sql: string,
    params: QueryParam[],
  ): ExecuteResult {
    // INSERT INTO <table> (col1, col2) VALUES (?, ?)
    const match = sql.match(/INSERT\s+INTO\s+(\w+)\s*\(([^)]+)\)\s*VALUES\s*\(([^)]+)\)/i);
    if (!match) throw new StorageError('INSERT parse failed', undefined, sql);
    const tableName = match[1]!;
    const cols = match[2]!.split(',').map((c) => c.trim());
    const placeholders = match[3]!.split(',').length;
    if (params.length < placeholders) {
      throw new StorageError('INSERT params mismatch', undefined, sql);
    }
    const table = this.tables.get(tableName);
    if (!table) throw new StorageError(`Table not found: ${tableName}`, undefined, sql);
    const row: DatabaseRow = {};
    cols.forEach((col, idx) => {
      row[col] = params[idx] ?? null;
    });
    const pk = row['id'] ?? row['session_id'] ?? Math.random();
    table.rows.set(pk, row);
    return { changes: 1, lastInsertId: 0 };
  }

  private handleUpdate(
    sql: string,
    _params: QueryParam[],
  ): ExecuteResult {
    // 简化实现: 仅支持 UPDATE ... SET col = ? 形式,PoC 阶段够用
    const tableMatch = sql.match(/UPDATE\s+(\w+)/i);
    if (!tableMatch) throw new StorageError('UPDATE parse failed', undefined, sql);
    const tableName = tableMatch[1]!;
    const table = this.tables.get(tableName);
    if (!table) return { changes: 0, lastInsertId: 0 };
    return { changes: table.rows.size, lastInsertId: 0 };
  }

  private handleDelete(
    sql: string,
    _params: QueryParam[],
  ): ExecuteResult {
    const tableMatch = sql.match(/DELETE\s+FROM\s+(\w+)/i);
    if (!tableMatch) throw new StorageError('DELETE parse failed', undefined, sql);
    const tableName = tableMatch[1]!;
    const table = this.tables.get(tableName);
    if (!table) return { changes: 0, lastInsertId: 0 };
    const count = table.rows.size;
    table.rows.clear();
    return { changes: count, lastInsertId: 0 };
  }

  private createTransactionContext(): TransactionContext {
    return {
      query: (sql, params) => this.query(sql, params),
      execute: (sql, params) => this.execute(sql, params),
    };
  }

  private assertInitialized(): void {
    if (!this.initialized) {
      throw new StorageError('MemoryAdapter not initialized');
    }
  }
}
