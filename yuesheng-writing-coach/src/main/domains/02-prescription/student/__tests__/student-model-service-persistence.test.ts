import { describe, it, expect, beforeAll } from 'vitest';
import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { StudentModelService } from '../student-model-service';
import { ProfileDataAggregator } from '../profile-data-aggregator';
import type { DiagnosisService } from '../../../01-diagnosis/diagnosis.service';
import type { TrainingRecordService } from '../../../04-validation/training/training-record.service';

/**
 * RWR-P1-7 (C-1) 画像持久化层单元测试
 *
 * 覆盖:
 * - 1. ensureSessionRow 自动创建行
 * - 2. appendTeachingHistory 单条追加
 * - 3. appendTeachingHistory 200 条 FIFO 截断
 * - 4. setAttitudePreference 写入并查询同 session
 * - 5. getAttitudePreference 跨 session 取最近一条
 * - 6. getAttitudePreference 无记录时返回 null
 * - 7. ensureSessionRow 幂等(同一 session 多次调用不重复创建)
 */

const MIGRATIONS_DIR = path.join(__dirname, '..', '..', '..', '..', 'db');
const MIGRATION_FILES = [
  '013_manuscripts.sql',
  '018_db_p1a_time_format.sql',
  '021_teaching_progress.sql',
  '022_projects.sql',
  '023_data_migration.sql',
];

/** 最小化 stub aggregator(不测聚合,只测持久化) */
function stubAggregator(): ProfileDataAggregator {
  const fakeDiag = {} as DiagnosisService;
  const fakeTrn = {} as TrainingRecordService;
  return new ProfileDataAggregator(fakeDiag, fakeTrn);
}

function createTestDb(): Database.Database {
  const db = new Database(':memory:');
  // Stub 前置表(沿用 022 测试 schema,018 重建表需要)
  db.exec(`
    CREATE TABLE teaching_state (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL UNIQUE,
      current_phase TEXT NOT NULL DEFAULT 'P0_INIT', current_subphase TEXT,
      completed_actions TEXT DEFAULT '[]', completed_tasks TEXT DEFAULT '[]',
      active_problems TEXT DEFAULT '[]', next_suggested_actions TEXT DEFAULT '[]',
      current_task_id TEXT, diagnosis_summary TEXT, last_user_confirmation TEXT,
      focus_area TEXT DEFAULT NULL, transition_offered INTEGER DEFAULT 0,
      locked_syndromes TEXT DEFAULT '[]', active_training_meta TEXT DEFAULT NULL, updated_at TEXT,
      FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
    );
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '新建会话',
      preview TEXT DEFAULT '', manuscript_id TEXT, chapter_id TEXT,
      project_id TEXT, created_at TEXT, updated_at TEXT
    );
    CREATE TABLE diagnosis_results (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, message_id TEXT NOT NULL,
      syndromes TEXT NOT NULL, suggested_actions TEXT NOT NULL,
      confidence REAL NOT NULL DEFAULT 0, timestamp TEXT,
      next_focus TEXT, created_at TEXT DEFAULT (datetime('now')),
      root_cause_analysis TEXT
    );
    CREATE TABLE user_training_records (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, task_id TEXT NOT NULL,
      syndrome_id TEXT NOT NULL, status TEXT NOT NULL,
      assigned_at TEXT NOT NULL, completed_at TEXT,
      user_response TEXT, ai_feedback TEXT, effectiveness INTEGER, score INTEGER
    );
    CREATE TABLE evidence (
      evidence_id TEXT PRIMARY KEY, type TEXT NOT NULL, level INTEGER NOT NULL,
      novel_id TEXT NOT NULL, chapter_id TEXT, chapter_range TEXT,
      paragraph_index INTEGER, sample_range TEXT, content_json TEXT NOT NULL,
      related_disease TEXT NOT NULL, related_ability TEXT NOT NULL,
      related_observations TEXT, extracted_by TEXT NOT NULL, created_at TEXT NOT NULL
    );
  `);
  db.pragma('foreign_keys = OFF');
  for (const file of MIGRATION_FILES) {
    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf-8');
    db.exec(sql);
  }
  db.pragma('foreign_keys = ON');
  return db;
}

describe('StudentModelService 画像持久化层(C-1)', () => {
  let db: Database.Database;
  let service: StudentModelService;

  beforeAll(() => {
    db = createTestDb();
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-c1-1', 'C1 测试');
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-c1-2', 'C1 测试 2');
    service = new StudentModelService(db, stubAggregator(), '');
  });

  it('应自动创建 student_model 行(ensureSessionRow 兜底)', () => {
    service.appendTeachingHistory('s-c1-1', {
      action: 'introduce',
      syndromeId: 'syn-x',
      outcome: 'success',
    });
    const row = db
      .prepare('SELECT id, session_id FROM student_model WHERE session_id = ?')
      .get('s-c1-1') as { id: string; session_id: string } | undefined;
    expect(row).toBeDefined();
    expect(row?.session_id).toBe('s-c1-1');
  });

  it('应追加一条教学历史(单条)', () => {
    const before = (service as unknown as { db: Database.Database }).db
      .prepare(
        'SELECT teaching_history FROM student_model WHERE session_id = ? ORDER BY created_at ASC LIMIT 1',
      )
      .get('s-c1-1') as { teaching_history: string };
    const list = JSON.parse(before.teaching_history);
    expect(list.length).toBe(1);
    expect(list[0].action).toBe('introduce');
    expect(list[0].syndromeId).toBe('syn-x');
    expect(list[0].outcome).toBe('success');
    expect(list[0].timestamp).toBeGreaterThan(0);
  });

  it('应 FIFO 截断到 200 条(连续追加 250 条)', () => {
    // 切到新 session,避免污染前面的断言
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-c1-bulk', 'bulk');
    const bulkId = 's-c1-bulk';
    for (let i = 0; i < 250; i++) {
      service.appendTeachingHistory(bulkId, {
        action: `act-${i}`,
        syndromeId: '',
        outcome: 'unknown',
      });
    }
    const row = db
      .prepare(
        'SELECT teaching_history FROM student_model WHERE session_id = ? ORDER BY created_at ASC LIMIT 1',
      )
      .get(bulkId) as { teaching_history: string };
    const list = JSON.parse(row.teaching_history);
    expect(list.length).toBe(200);
    // 保留的是最后 200 条
    expect(list[0].action).toBe('act-50');
    expect(list[199].action).toBe('act-249');
  });

  it('应写 attitudePreference 并按 session 查询', () => {
    service.setAttitudePreference('s-c1-1', 'yuesheng');
    expect(service.getAttitudePreference('s-c1-1')).toBe('yuesheng');
  });

  it('应跨 session 取最近一条非空 attitudePreference', () => {
    // s-c1-1 刚设为 yuesheng(最近)
    // 再设置一个更早的
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-c1-old', 'old');
    service.setAttitudePreference('s-c1-old', 'doubao');
    // 不管谁先谁后,跨 session 拿到的是"最近 updated_at"
    // 重新把 s-c1-1 改成 direct(更新 updated_at),应该 win
    service.setAttitudePreference('s-c1-1', 'sensei');
    expect(service.getAttitudePreference()).toBe('sensei');
  });

  it('应返回 null(当没有任何 attitudePreference 记录)', () => {
    // 新建一个全新 session 不写 attitude
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-c1-empty', 'empty');
    expect(service.getAttitudePreference('s-c1-empty')).toBeNull();
  });

  it('应保证 ensureSessionRow 幂等(同一 session 多次调用不重复创建行)', () => {
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-c1-dedup', 'dedup');
    service.appendTeachingHistory('s-c1-dedup', { action: 'a1', syndromeId: '', outcome: 'success' });
    service.appendTeachingHistory('s-c1-dedup', { action: 'a2', syndromeId: '', outcome: 'success' });
    const count = (db
      .prepare('SELECT COUNT(*) as n FROM student_model WHERE session_id = ?')
      .get('s-c1-dedup') as { n: number }).n;
    expect(count).toBe(1);
  });
});
