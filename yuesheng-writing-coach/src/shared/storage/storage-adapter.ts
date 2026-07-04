/**
 * StorageAdapter — Sprint 26 跨端存储抽象
 *
 * 目标: 让同一份业务代码(Stores / Services)在 Windows(Electron + better-sqlite3)
 *       和 Android(Capacitor + @capacitor-community/sqlite)上无差别运行。
 *
 * 设计原则:
 *   - 接口最小化: 仅暴露 query / execute / transaction / close,屏蔽 SQL 引擎差异
 *   - 异步优先: 全部 Promise 化,WebView 环境友好
 *   - 类型安全: query<T>() 强制泛型,避免运行时字段错误
 *   - 异常隔离: 任何 SQL 错误抛 StorageError,调用方按 R-028 处理
 *
 * 跨端差异(由各 Adapter 内部抹平):
 *   - better-sqlite3: 同步,需 `await Promise.resolve()` 包装成异步
 *   - Capacitor SQLite: 原生异步,需 `runAsPromise()` 包装
 *   - 占位符: better-sqlite3 用 `?`,Capacitor SQLite 用 `?`(一致)
 *   - 事务 API: better-sqlite3 用 `db.transaction(fn)`,Capacitor 用 `db.beginTransaction() + commit/rollback`
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.2
 * 决策: D-074
 */
import type { DatabaseRow, QueryParam } from './storage-types';

/** 事务上下文(与 Adapter 解耦,内部封装) */
export interface TransactionContext {
  query<T extends DatabaseRow = DatabaseRow>(
    sql: string,
    params?: QueryParam[],
  ): Promise<T[]>;
  execute(
    sql: string,
    params?: QueryParam[],
  ): Promise<{ changes: number; lastInsertId: number | bigint }>;
}

/** 存储操作结果(用于 execute 反馈) */
export interface ExecuteResult {
  /** 受影响行数(INSERT/UPDATE/DELETE 返回值) */
  changes: number;
  /** 最后插入的行 ID(INSERT 返回值,SELECT 为 0/null) */
  lastInsertId: number | bigint;
}

/** 存储异常(统一异常类型,屏蔽 SQL 引擎差异) */
export class StorageError extends Error {
  constructor(
    message: string,
    public readonly cause?: unknown,
    public readonly sql?: string,
  ) {
    super(message);
    this.name = 'StorageError';
  }
}

/**
 * 存储适配器接口(双端共用)
 *
 * 实现:
 *   - BetterSqliteAdapter: Windows/Electron,基于 better-sqlite3
 *   - CapacitorSqliteAdapter: Android/Capacitor,基于 @capacitor-community/sqlite
 *
 * 用法:
 * ```typescript
 * const adapter = createStorageAdapter('electron');  // or 'capacitor'
 * await adapter.initialize();
 * const rows = await adapter.query<User>('SELECT * FROM users WHERE id = ?', [42]);
 * await adapter.close();
 * ```
 */
export interface StorageAdapter {
  /**
   * 初始化适配器(创建连接、初始化 schema)
   * - 幂等: 多次调用应安全(SQLite 已有 `IF NOT EXISTS` 保护)
   * - 必须先于 query/execute 调用
   */
  initialize(): Promise<void>;

  /**
   * 查询多行(SELECT)
   * @param sql SQL 语句(支持 `?` 占位符)
   * @param params 参数数组
   * @returns 行数组,无结果返回空数组
   */
  query<T extends DatabaseRow = DatabaseRow>(
    sql: string,
    params?: QueryParam[],
  ): Promise<T[]>;

  /**
   * 查询单行(SELECT ... LIMIT 1)
   * - 便捷方法,等价于 `query().then(rows => rows[0] ?? null)`
   * - 无结果返回 null(不抛错)
   */
  queryOne<T extends DatabaseRow = DatabaseRow>(
    sql: string,
    params?: QueryParam[],
  ): Promise<T | null>;

  /**
   * 执行非查询语句(INSERT/UPDATE/DELETE/CREATE/DROP)
   * @returns 受影响行数 + 最后插入 ID
   */
  execute(
    sql: string,
    params?: QueryParam[],
  ): Promise<ExecuteResult>;

  /**
   * 事务执行(多条 SQL 在一个事务内)
   * - 任意 SQL 抛错 → 自动 rollback
   * - fn 返回值透传给调用方
   *
   * 用法:
   * ```typescript
   * await adapter.transaction(async (tx) => {
   *   await tx.execute('INSERT INTO a ...');
   *   await tx.execute('INSERT INTO b ...');
   *   return { success: true };
   * });
   * ```
   */
  transaction<T>(fn: (tx: TransactionContext) => Promise<T>): Promise<T>;

  /**
   * 关闭连接
   * - 幂等: 多次调用安全
   * - 关闭后 query/execute 应抛错
   */
  close(): Promise<void>;

  /**
   * 获取底层引擎标识(用于日志/调试)
   * @returns 'better-sqlite3' | 'capacitor-sqlite' | 'memory'(测试)
   */
  readonly engine: 'better-sqlite3' | 'capacitor-sqlite' | 'memory';
}
