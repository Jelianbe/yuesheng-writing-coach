/**
 * StorageAdapter PoC 测试 — Sprint 26 阶段 1
 *
 * 目标: 验证 MemoryAdapter 和 BetterSqliteAdapter 行为一致
 * 同一套 SQL 在两个 adapter 上跑出相同结果
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.2
 * 决策: D-074
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import { BetterSqliteAdapter } from '../adapters/better-sqlite.adapter';
import { MemoryAdapter } from '../adapters/memory.adapter';
import type { StorageAdapter } from '../storage-adapter';

interface TestRow extends Record<string, unknown> {
  id: string;
  title: string;
  created_at: string;
}

const SESSIONS_SCHEMA = `
  CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );
`;

describe('StorageAdapter PoC — Sprint 26 阶段 1', () => {
  let adapters: StorageAdapter[];

  beforeEach(async () => {
    adapters = [];
  });

  afterEach(async () => {
    for (const a of adapters) {
      await a.close().catch(() => {});
    }
  });

  function makeMemory(): StorageAdapter {
    const a = new MemoryAdapter();
    adapters.push(a);
    return a;
  }

  function makeBetterSqlite(): StorageAdapter {
    const db = new Database(':memory:');
    const a = new BetterSqliteAdapter({ db, dbName: 'test.db', version: 1 });
    adapters.push(a);
    return a;
  }

  /**
   * 在两个 adapter 上跑同一组操作,断言结果一致
   */
  async function runScenario(
    name: string,
    fn: (adapter: StorageAdapter) => Promise<void>,
  ): Promise<void> {
    const mem = makeMemory();
    const sql = makeBetterSqlite();
    await mem.initialize();
    await sql.initialize();

    // sessions 表 schema(MemoryAdapter 需手动 CREATE, BetterSqlite 初始化时已自动建)
    await mem.execute(SESSIONS_SCHEMA);

    // 跑同一组操作
    await fn(mem);
    await fn(sql);

    // 断言两个 adapter 状态一致
    const memRows = await mem.query<TestRow>('SELECT * FROM sessions');
    const sqlRows = await sql.query<TestRow>('SELECT * FROM sessions');
    expect(sqlRows.length, `[${name}] better-sqlite3 row count`).toBe(memRows.length);
  }

  it('initialize: 双 adapter 都能初始化成功', async () => {
    await runScenario('init', async () => {
      // 空场景:仅 initialize
    });
  });

  it('execute(INSERT) + query: 双 adapter 都能存一行', async () => {
    await runScenario('insert', async (a) => {
      const result = await a.execute(
        'INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
        ['sess-1', 'My First Session', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z'],
      );
      expect(result.changes).toBe(1);
      const rows = await a.query<TestRow>('SELECT * FROM sessions');
      expect(rows.length).toBe(1);
      expect(rows[0]?.id).toBe('sess-1');
      expect(rows[0]?.title).toBe('My First Session');
    });
  });

  it('queryOne: 双 adapter 都能查单行', async () => {
    await runScenario('queryOne', async (a) => {
      await a.execute(
        'INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
        ['sess-q1', 'Query One Test', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z'],
      );
      const row = await a.queryOne<TestRow>('SELECT * FROM sessions WHERE id = ?', ['sess-q1']);
      expect(row?.title).toBe('Query One Test');

      const notFound = await a.queryOne<TestRow>('SELECT * FROM sessions WHERE id = ?', ['nonexistent']);
      expect(notFound).toBeNull();
    });
  });

  it('transaction: 双 adapter 事务正常 commit', async () => {
    await runScenario('transaction-commit', async (a) => {
      const result = await a.transaction(async (tx) => {
        await tx.execute(
          'INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
          ['tx-1', 'TX Session 1', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z'],
        );
        await tx.execute(
          'INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
          ['tx-2', 'TX Session 2', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z'],
        );
        return { inserted: 2 };
      });
      expect(result.inserted).toBe(2);
      const rows = await a.query<TestRow>('SELECT * FROM sessions');
      expect(rows.length).toBe(2);
    });
  });

  it('BetterSqliteAdapter: 5 张核心表 schema 正确初始化', async () => {
    const db = new Database(':memory:');
    const a = new BetterSqliteAdapter({ db, dbName: 'test.db', version: 1 });
    adapters.push(a);
    await a.initialize();

    // 检查 5 张表都已创建
    const tables = await a.query<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    const tableNames = tables.map((t) => t.name);
    expect(tableNames).toContain('sessions');
    expect(tableNames).toContain('projects');
    expect(tableNames).toContain('active_training');
    expect(tableNames).toContain('teaching_state');
    expect(tableNames).toContain('training_records');

    // 验证 active_training 表含 step_responses_json 字段(Sprint 25 C-4)
    const columns = await a.query<{ name: string }>(
      "PRAGMA table_info(active_training)",
    );
    const colNames = columns.map((c) => c.name);
    expect(colNames).toContain('step_responses_json');
  });
});
