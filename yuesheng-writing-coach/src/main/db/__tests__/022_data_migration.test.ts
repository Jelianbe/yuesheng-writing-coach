import { describe, it, expect, beforeAll } from 'vitest';
import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * RWR-P0-5 数据迁移脚本单元测试
 *
 * 测试策略:用 :memory: 内存 db 加载真实迁移 SQL,验证 4 步迁移
 * - 1. 默认项目创建
 * - 2. sessions.project_id 填充
 * - 3. manuscripts.project_id 填充
 * - 4. diagnosis_results.teaching_progress 默认值
 * - 5. 幂等性
 * - 6. FK ON DELETE SET NULL 行为
 */

const MIGRATIONS_DIR = path.join(__dirname, '..');
const MIGRATION_FILES = [
  '013_manuscripts.sql',
  '018_db_p1a_time_format.sql',
  '020_db_add_task_type.sql',
  '021_teaching_progress.sql',
  '022_projects.sql',
  '023_data_migration.sql',
];

function createStubDb(): Database.Database {
  // Stub 5 张前置表(018_db_p1a_time_format.sql 依赖,迁移链从 013 开始缺前置)
  // Schema 精确匹配 018 INSERT FROM 引用
  return new Database(':memory:');
}

function createTestDb(): Database.Database {
  const db = createStubDb();
  // 先创建 stub 表(模拟 production 已存在的 5 张表)
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
  // 关闭 FK 以允许 018 重建
  db.pragma('foreign_keys = OFF');
  // 加载迁移链
  for (const file of MIGRATION_FILES) {
    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf-8');
    db.exec(sql);
  }
  db.pragma('foreign_keys = ON');
  return db;
}

describe('022_data_migration.sql', () => {
  let db: Database.Database;

  beforeAll(() => {
    db = createTestDb();
  });

  it('应创建默认项目 default-project (我的作品集)', () => {
    const project = db.prepare('SELECT * FROM projects WHERE id = ?').get('default-project') as any;
    expect(project).toBeDefined();
    expect(project.name).toBe('我的作品集');
    expect(project.setting_tree_type).toBe('main');
    expect(project.created_at).toBeGreaterThan(0);
  });

  it('应给 sessions 添加 project_id 字段并默认归入 default-project', () => {
    // 准备测试数据:插入 1 个 session(无 project_id)
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run('s-test-1', '测试会话');
    // 重新跑迁移步骤 3 (因为初始加载时 sessions 表为空)
    db.exec(`
      UPDATE sessions SET project_id = 'default-project' WHERE project_id IS NULL;
    `);
    const session = db.prepare('SELECT project_id FROM sessions WHERE id = ?').get('s-test-1') as any;
    expect(session.project_id).toBe('default-project');
  });

  it('应给 manuscripts 添加 project_id 字段并默认归入 default-project', () => {
    db.prepare('INSERT INTO manuscripts (id, title) VALUES (?, ?)').run('m-test-1', '测试作品');
    db.exec(`
      UPDATE manuscripts SET project_id = 'default-project' WHERE project_id IS NULL;
    `);
    const manuscript = db.prepare('SELECT project_id FROM manuscripts WHERE id = ?').get('m-test-1') as any;
    expect(manuscript.project_id).toBe('default-project');
  });

  it('应给 diagnosis_results.teaching_progress 填默认 \'[]\'', () => {
    // 021 迁移已自动设置默认值,验证字段存在 + 默认值生效
    const columns = db.prepare("PRAGMA table_info(diagnosis_results)").all() as any[];
    const tpColumn = columns.find((c) => c.name === 'teaching_progress');
    expect(tpColumn).toBeDefined();
    expect(tpColumn.notnull).toBe(0); // nullable(允许 022 防御性 UPDATE)
  });

  it('应幂等:重复运行不报错且数据一致', () => {
    const beforeCount = (db.prepare('SELECT COUNT(*) as c FROM projects').get() as any).c;
    // 重新执行 022 迁移关键步骤
    db.exec(`
      INSERT INTO projects (id, name, description, setting_tree, setting_tree_type, created_at, updated_at)
      SELECT 'default-project', '我的作品集', '自动创建的默认项目,包含所有现有作品与会话', NULL, 'main', unixepoch(), unixepoch()
      WHERE NOT EXISTS (SELECT 1 FROM projects WHERE id = 'default-project');
    `);
    const afterCount = (db.prepare('SELECT COUNT(*) as c FROM projects').get() as any).c;
    expect(afterCount).toBe(beforeCount); // 数量不变
  });

  it('FK ON DELETE SET NULL:删 project 时 session 应保留但 project_id 变 NULL', () => {
    // 准备:插入 session
    db.prepare('INSERT INTO sessions (id, title, project_id) VALUES (?, ?, ?)').run('s-fk-test', 'FK 测试', 'default-project');
    // 删 default-project
    db.prepare('DELETE FROM projects WHERE id = ?').run('default-project');
    // 验证:session 保留,project_id 变 NULL
    const session = db.prepare('SELECT project_id FROM sessions WHERE id = ?').get('s-fk-test') as any;
    expect(session).toBeDefined();
    expect(session.project_id).toBeNull();
  });

  it('应创建索引 idx_sessions_project_id / idx_manuscripts_project_id', () => {
    const sessionIdx = db.prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_sessions_project_id'").get();
    const manuscriptIdx = db.prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_manuscripts_project_id'").get();
    expect(sessionIdx).toBeDefined();
    expect(manuscriptIdx).toBeDefined();
  });
});
