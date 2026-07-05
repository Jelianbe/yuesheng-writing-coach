/**
 * progress.handler.test.ts — 写作进度追踪 IPC 集成测试
 *
 * 覆盖: progress:overview 的 6 个 SQL 聚合路径
 * - 使用 real better-sqlite3 :memory: 数据库
 * - 创建 chapters / user_training_records / sessions 表并插入测试数据
 *
 * 依据: qa-baseline.md §3.3
 */
import { describe, it, expect, beforeEach } from 'vitest';
import Database from 'better-sqlite3';
import { initProgressHandlers } from '../progress.handler';
import { clearRegistry, _getRegistryForTest } from '../../core/service-bridge';

const CHANNEL = 'progress:overview';

/**
 * 创建测试所需的表 (与生产环境对齐)
 */
function createTables(db: Database.Database): void {
  db.exec(`
    CREATE TABLE chapters (
      id TEXT PRIMARY KEY,
      manuscript_id TEXT,
      title TEXT,
      content TEXT,
      word_count INTEGER DEFAULT 0,
      sort_order INTEGER DEFAULT 0,
      status TEXT DEFAULT 'draft',
      created_at INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at INTEGER NOT NULL DEFAULT (unixepoch())
    );
    CREATE TABLE user_training_records (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      syndrome_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('assigned','completed','skipped')),
      assigned_at INTEGER NOT NULL DEFAULT (unixepoch()),
      completed_at INTEGER,
      user_response TEXT,
      ai_feedback TEXT,
      effectiveness INTEGER,
      score INTEGER
    );
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      manuscript_id TEXT,
      title TEXT,
      created_at INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at INTEGER NOT NULL DEFAULT (unixepoch())
    );
  `);
}

/**
 * 插入测试 chapters 数据
 * @param db 数据库实例
 * @param days 生成几天的数据
 * @param wordCount 每天的字数
 */
function insertChapters(db: Database.Database, days: number, wordCount: number): void {
  const insert = db.prepare(
    `INSERT INTO chapters (id, manuscript_id, title, word_count, updated_at)
     VALUES (?, ?, ?, ?, ?)`,
  );
  const now = Math.floor(Date.now() / 1000);
  for (let i = 0; i < days; i++) {
    insert.run(
      `chap-${i}`,
      'manu-1',
      `第${i + 1}章`,
      wordCount,
      now - i * 86400, // 每天一条
    );
  }
}

beforeEach(() => {
  clearRegistry();
});

describe('progress:overview — 进度总览 IPC 集成', () => {
  // PH-1: 字数统计
  it('[PH-1] 字数统计: today/weekly/monthly/total 正确', async () => {
    const db = new Database(':memory:');
    createTables(db);
    const now = Math.floor(Date.now() / 1000);
    // 今天: 500 字; 本周内(非今天): 1000 字 x2; 本月内(本周外): 500 字 x5
    const insert = db.prepare(
      `INSERT INTO chapters (id, manuscript_id, title, word_count, updated_at)
       VALUES (?, ?, ?, ?, ?)`,
    );
    // 今天
    insert.run('chap-today', 'manu-1', '今日章节', 500, now);
    // 本周 (4 天前, 仍在 7 天内)
    insert.run('chap-w1', 'manu-1', '周章节1', 1000, now - 86400 * 4);
    insert.run('chap-w2', 'manu-1', '周章节2', 1000, now - 86400 * 5);
    // 本月 (15 天前, 仍在 30 天内但超出 7 天)
    insert.run('chap-m1', 'manu-1', '月章节1', 500, now - 86400 * 15);
    insert.run('chap-m2', 'manu-1', '月章节2', 500, now - 86400 * 16);
    // 总计
    insert.run('chap-old', 'manu-1', '历史章节', 2000, now - 86400 * 60);

    initProgressHandlers({ db });
    const handler = _getRegistryForTest().get(CHANNEL)!;
    const result = await handler({}) as Record<string, unknown>;

    expect(result.todayWordCount).toBe(500);
    expect(result.weeklyWordCount).toBe(2500);  // 500 + 1000 + 1000
    expect(result.monthlyWordCount).toBe(3500);  // 500 + 1000 + 1000 + 500 + 500
    expect(result.totalWordCount).toBe(5500);    // 500 + 1000 + 1000 + 500 + 500 + 2000
    db.close();
  });

  // PH-2: 写作连续天数 — 连续 5 天
  it('[PH-2] 连续 5 天写作时 writingStreak = 5', async () => {
    const db = new Database(':memory:');
    createTables(db);
    insertChapters(db, 5, 300);

    initProgressHandlers({ db });
    const handler = _getRegistryForTest().get(CHANNEL)!;
    const result = await handler({}) as { writingStreak: number };

    expect(result.writingStreak).toBe(5);
    db.close();
  });

  // PH-3: 写作连续天数 — 有中断
  it('[PH-3] 写作中断时 writingStreak < 总天数', async () => {
    const db = new Database(':memory:');
    createTables(db);
    const now = Math.floor(Date.now() / 1000);
    const insert = db.prepare(
      `INSERT INTO chapters (id, manuscript_id, title, word_count, updated_at)
       VALUES (?, ?, ?, ?, ?)`,
    );
    // 连续 3 天, 间隔 2 天, 再写 2 天
    for (let i = 0; i < 3; i++) {
      insert.run(`chap-a${i}`, 'manu-1', `A${i}`, 100, now - i * 86400);
    }
    // 2 天前都是第 3 天的范围, 所以间隔需要从第 4 天开始算
    // 第 0,1,2 天写, 第 3,4 天不写, 第 5,6 天写
    for (let i = 5; i <= 6; i++) {
      insert.run(`chap-b${i}`, 'manu-1', `B${i}`, 100, now - i * 86400);
    }

    initProgressHandlers({ db });
    const handler = _getRegistryForTest().get(CHANNEL)!;
    const result = await handler({}) as { writingStreak: number };

    // 最新是今天, 往前连续 3 天, 然后中断
    expect(result.writingStreak).toBe(3);
    db.close();
  });

  // PH-4: 训练统计
  it('[PH-4] 训练统计: total/completed/averageScore 正确', async () => {
    const db = new Database(':memory:');
    createTables(db);
    const now = Math.floor(Date.now() / 1000);
    const insert = db.prepare(
      `INSERT INTO user_training_records (id, session_id, task_id, syndrome_id, status, assigned_at, completed_at, score)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    );
    insert.run('r1', 's1', 't1', 'P001', 'completed', now, now, 8);
    insert.run('r2', 's1', 't2', 'P002', 'completed', now, now, 7);
    insert.run('r3', 's2', 't3', 'P001', 'completed', now, now, 9);
    insert.run('r4', 's2', 't4', 'P003', 'assigned', now, null, null);
    insert.run('r5', 's3', 't5', 'P002', 'skipped', now, null, null);

    initProgressHandlers({ db });
    const handler = _getRegistryForTest().get(CHANNEL)!;
    const result = await handler({}) as { totalTraining: number; completedTraining: number; averageScore: number | null };

    expect(result.totalTraining).toBe(5);
    expect(result.completedTraining).toBe(3);
    // averageScore: (8 + 7 + 9) / 3 = 8
    expect(result.averageScore).toBe(8);
    db.close();
  });

  // PH-5: 每日柱状图
  it('[PH-5] 跨 7 天的每日字数返回 7 条柱状图数据', async () => {
    const db = new Database(':memory:');
    createTables(db);
    insertChapters(db, 7, 200);

    initProgressHandlers({ db });
    const handler = _getRegistryForTest().get(CHANNEL)!;
    const result = await handler({}) as { dailyWordCounts: Array<{ date: string; count: number }> };

    expect(result.dailyWordCounts.length).toBe(7);
    for (const d of result.dailyWordCounts) {
      expect(d.count).toBe(200);
    }
    db.close();
  });

  // PH-6: 空数据库
  it('[PH-6] 空数据库返回全零/空', async () => {
    const db = new Database(':memory:');
    createTables(db);

    initProgressHandlers({ db });
    const handler = _getRegistryForTest().get(CHANNEL)!;
    const result = await handler({}) as Record<string, unknown>;

    expect(result.todayWordCount).toBe(0);
    expect(result.weeklyWordCount).toBe(0);
    expect(result.monthlyWordCount).toBe(0);
    expect(result.totalWordCount).toBe(0);
    expect(result.writingStreak).toBe(0);
    expect(result.totalTraining).toBe(0);
    expect(result.completedTraining).toBe(0);
    expect(result.averageScore).toBeNull();
    expect((result.dailyWordCounts as unknown[]).length).toBe(0);
    expect((result.dailyTrainingCounts as unknown[]).length).toBe(0);
    db.close();
  });
});
