import { describe, it, expect, beforeAll } from 'vitest';
import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * RWR-P1-6 (B-2) 教学决策记录表单元测试
 *
 * 测试策略:用 :memory: 内存 db 加载完整迁移链,验证:
 * - 1. teaching_decision_log 表存在
 * - 2. 字段对齐 spec §8.2
 * - 3. decision_id 主键约束
 * - 4. FK ON DELETE CASCADE
 * - 5. 索引创建
 * - 6. 幂等性
 */

const MIGRATIONS_DIR = path.join(__dirname, '..');
const MIGRATION_FILES = [
  '013_manuscripts.sql',
  '018_db_p1a_time_format.sql',
  '020_db_add_task_type.sql',
  '021_teaching_progress.sql',
  '022_projects.sql',
  '023_data_migration.sql',
  '024_teaching_decision_log.sql',
];

function createTestDb(): Database.Database {
  const db = new Database(':memory:');
  // Stub 前置表(沿用 022 测试 schema,018 重建 teaching_state 等表需要)
  db.exec(`
    CREATE TABLE teaching_state (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL UNIQUE,
      current_phase TEXT NOT NULL DEFAULT 'P0_INIT', current_subphase TEXT,
      completed_actions TEXT DEFAULT '[]', completed_tasks TEXT DEFAULT '[]',
      active_problems TEXT DEFAULT '[]', next_suggested_actions TEXT DEFAULT '[]',
      current_task_id TEXT, diagnosis_summary TEXT, last_user_confirmation TEXT,
      focus_area TEXT DEFAULT NULL, transition_offered INTEGER DEFAULT 0,
      locked_syndromes TEXT DEFAULT '[]', updated_at TEXT,
      FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
    );
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '新建会话',
      preview TEXT DEFAULT '', manuscript_id TEXT, chapter_id TEXT,
      created_at TEXT, updated_at TEXT
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

describe('024_teaching_decision_log.sql', () => {
  let db: Database.Database;

  beforeAll(() => {
    db = createTestDb();
  });

  it('应创建 teaching_decision_log 表', () => {
    const table = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='teaching_decision_log'")
      .get();
    expect(table).toBeDefined();
  });

  it('字段应对齐 spec §8.2(decisionId/sessionId/syndromeId/strategyChosen/reason/studentState/decidedAt)', () => {
    const columns = db.prepare('PRAGMA table_info(teaching_decision_log)').all() as Array<{
      name: string;
      notnull: number;
    }>;
    const colNames = columns.map((c) => c.name);
    expect(colNames).toContain('decision_id');
    expect(colNames).toContain('session_id');
    expect(colNames).toContain('syndrome_id');
    expect(colNames).toContain('strategy_chosen');
    expect(colNames).toContain('reason');
    expect(colNames).toContain('student_state_json');
    expect(colNames).toContain('decided_at');
    // outcome / outcome_at / notes 留待 Phase 2 写入(可空)
    expect(colNames).toContain('outcome');
    expect(colNames).toContain('outcome_at');
    expect(colNames).toContain('notes');
  });

  it('应允许 INSERT 一条决策记录', () => {
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-dec-1', '决策测试');
    const studentState = JSON.stringify({
      confidence: 'neutral',
      relapseCount: 0,
      currentStage: 'P1_DIAGNOSIS',
      attitudeLevel: 'balanced',
    });
    db.prepare(`
      INSERT INTO teaching_decision_log
        (decision_id, session_id, syndrome_id, strategy_chosen, reason, student_state_json)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run('dec-001', 's-dec-1', 'syn-x', 'GUIDE', '新诊断症候,启用引导式教学', studentState);

    const row = db
      .prepare('SELECT * FROM teaching_decision_log WHERE decision_id = ?')
      .get('dec-001') as Record<string, unknown>;
    expect(row).toBeDefined();
    expect(row.strategy_chosen).toBe('GUIDE');
    expect(row.reason).toContain('引导式教学');
    expect(row.decided_at).toBeGreaterThan(0);
  });

  it('FK ON DELETE CASCADE:删 session 时决策记录应级联删除', () => {
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-dec-2', 'CASCADE 测试');
    db.prepare(`
      INSERT INTO teaching_decision_log
        (decision_id, session_id, syndrome_id, strategy_chosen, reason, student_state_json)
      VALUES ('dec-002', 's-dec-2', 'syn-y', 'GUIDE', 'r', '{}')
    `).run();
    // 删 session
    db.prepare('DELETE FROM sessions WHERE id = ?').run('s-dec-2');
    const row = db
      .prepare('SELECT * FROM teaching_decision_log WHERE decision_id = ?')
      .get('dec-002');
    expect(row).toBeUndefined();
  });

  it('应创建 idx_teaching_decision_session / idx_teaching_decision_syndrome', () => {
    const idx1 = db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_teaching_decision_session'",
      )
      .get();
    const idx2 = db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_teaching_decision_syndrome'",
      )
      .get();
    expect(idx1).toBeDefined();
    expect(idx2).toBeDefined();
  });

  it('应幂等:重复运行不报错', () => {
    const sql = fs.readFileSync(
      path.join(MIGRATIONS_DIR, '024_teaching_decision_log.sql'),
      'utf-8',
    );
    expect(() => db.exec(sql)).not.toThrow();
  });
});
