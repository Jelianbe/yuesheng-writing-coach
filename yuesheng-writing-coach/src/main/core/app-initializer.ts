import type { BrowserWindow } from 'electron';
import { app } from 'electron';
import Database from 'better-sqlite3';
import * as path from 'path';
import * as fs from 'fs';
import type { ServiceContainer } from './service-container';
import { configureServices } from './service-config';
import { IpcRegistry } from './ipc-registry';
import { WindowManager } from './window-manager';
import { setResourcesRoot } from '../domains/03-teaching/transition-prompt-loader';

export class AppInitializer {
  private container: ServiceContainer;
  private windowManager: WindowManager;
  private db!: Database.Database;

  constructor(container: ServiceContainer) {
    this.container = container;
    this.windowManager = new WindowManager();
  }

  async initialize(): Promise<BrowserWindow> {
    this.db = this.initDatabase();
    this.runMigrations(this.db);

    const resourcesRoot = this.getResourcesRoot();
    setResourcesRoot(resourcesRoot);

    const isDev = process.env.NODE_ENV === 'development';
    configureServices(this.container, this.db, resourcesRoot, isDev);

    const mainWindow = this.windowManager.create();

    const ipcRegistry = new IpcRegistry(this.container, mainWindow);
    ipcRegistry.registerAll();

    return mainWindow;
  }

  getMainWindow(): BrowserWindow | null {
    return this.windowManager.get();
  }

  recreateWindow(): BrowserWindow | null {
    return this.windowManager.create();
  }

  private initDatabase(): Database.Database {
    // 数据库存储在项目目录下（Trae 安全沙箱白名单内），而非 Electron 默认的 %APPDATA%
    const dbDir = path.join(app.getAppPath(), 'data');
    fs.mkdirSync(dbDir, { recursive: true });
    const dbPath = path.join(dbDir, 'yuesheng.db');

    // 尝试从旧位置（%APPDATA%）复制数据库（如首次迁移）
    if (!fs.existsSync(dbPath)) {
      const oldDbPath = path.join(app.getPath('userData'), 'yuesheng.db');
      try {
        if (fs.existsSync(oldDbPath)) {
          fs.copyFileSync(oldDbPath, dbPath);
        }
      } catch {
        // 旧数据库复制失败（权限等），忽略，创建全新数据库
        console.warn('[DB] 无法从 %APPDATA% 复制旧数据库，将创建全新数据库');
      }
    }

    const db = new Database(dbPath);
    // 使用 DELETE 而非 WAL 模式，减少 SQLite 额外文件
    db.pragma('journal_mode = DELETE');
    db.pragma('foreign_keys = ON');
    db.pragma('synchronous = NORMAL');
    db.pragma('cache_size = -64000');
    return db;
  }

  private ensureBaseSchema(db: Database.Database): void {
    // 如果 teaching_state 表不存在，说明数据库为空，需要创建基础表结构
    const hasTeachingState = db.prepare(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='teaching_state'"
    ).get();
    if (hasTeachingState) return;

    console.warn('[DB] 创建基础表结构');
    db.exec(`
      -- sessions
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '新建会话',
        preview TEXT DEFAULT '',
        manuscript_id TEXT,
        chapter_id TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      -- chat_messages 表已废弃，实际使用 messages 表（由 004_create_chat.sql 迁移创建）
      -- 保留此注释以记录历史，不再创建冗余表

      -- diagnosis_results
      CREATE TABLE IF NOT EXISTS diagnosis_results (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        syndromes TEXT NOT NULL,
        suggested_actions TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 0,
        timestamp TEXT NOT NULL,
        next_focus TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        root_cause_analysis TEXT,
        UNIQUE(session_id, message_id)
      );
      CREATE INDEX IF NOT EXISTS idx_diagnosis_session ON diagnosis_results(session_id, timestamp);
      CREATE INDEX IF NOT EXISTS idx_diagnosis_message ON diagnosis_results(message_id);

      -- teaching_state
      CREATE TABLE IF NOT EXISTS teaching_state (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL UNIQUE,
        current_phase TEXT NOT NULL DEFAULT 'P0_INIT',
        current_subphase TEXT,
        completed_actions TEXT DEFAULT '[]',
        completed_tasks TEXT DEFAULT '[]',
        active_problems TEXT DEFAULT '[]',
        next_suggested_actions TEXT DEFAULT '[]',
        current_task_id TEXT,
        diagnosis_summary TEXT DEFAULT '',
        last_user_confirmation TEXT,
        focus_area TEXT DEFAULT NULL,
        transition_offered INTEGER DEFAULT 0,
        locked_syndromes TEXT DEFAULT '[]',
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_teaching_state_session ON teaching_state(session_id);
      CREATE INDEX IF NOT EXISTS idx_teaching_state_phase ON teaching_state(current_phase);
      CREATE INDEX IF NOT EXISTS idx_teaching_state_focus_area ON teaching_state(focus_area);

      -- user_training_records
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
        score INTEGER
      );
      CREATE INDEX IF NOT EXISTS idx_training_session ON user_training_records(session_id, assigned_at);
      CREATE INDEX IF NOT EXISTS idx_training_task ON user_training_records(task_id);
      CREATE INDEX IF NOT EXISTS idx_training_status ON user_training_records(session_id, status);

      -- evidence
      CREATE TABLE IF NOT EXISTS evidence (
        evidence_id TEXT PRIMARY KEY,
        type TEXT NOT NULL CHECK(type IN ('text', 'pattern', 'statistical', 'comparison')),
        level INTEGER NOT NULL CHECK(level IN (1, 2, 3, 4)),
        novel_id TEXT NOT NULL,
        chapter_id TEXT,
        chapter_range TEXT,
        paragraph_index INTEGER,
        sample_range TEXT,
        content_json TEXT NOT NULL,
        related_disease TEXT NOT NULL,
        related_ability TEXT NOT NULL,
        related_observations TEXT,
        extracted_by TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      CREATE INDEX IF NOT EXISTS idx_evidence_disease ON evidence(related_disease);
      CREATE INDEX IF NOT EXISTS idx_evidence_ability ON evidence(related_ability);
      CREATE INDEX IF NOT EXISTS idx_evidence_novel ON evidence(novel_id);
      CREATE INDEX IF NOT EXISTS idx_evidence_level ON evidence(level);

      -- 标记已有迁移文件为已应用（只标记实际存在的文件）
      INSERT INTO _migrations (name) VALUES ('003_create_teaching_state.sql');
      INSERT INTO _migrations (name) VALUES ('004_create_chat.sql');
      INSERT INTO _migrations (name) VALUES ('005_diagnosis.sqlite');
      INSERT INTO _migrations (name) VALUES ('006_add_focus_area.sql');
      INSERT INTO _migrations (name) VALUES ('007_user_training.sql');
      INSERT INTO _migrations (name) VALUES ('008_evidence.sql');
      INSERT INTO _migrations (name) VALUES ('010_add_root_cause_analysis.sql');
      INSERT INTO _migrations (name) VALUES ('011_add_locked_syndromes.sql');
      INSERT INTO _migrations (name) VALUES ('012_add_training_score.sql');
    `);
  }

  private runMigrations(db: Database.Database): void {
    db.exec(`
      CREATE TABLE IF NOT EXISTS _migrations (
        name TEXT PRIMARY KEY,
        applied_at TEXT DEFAULT (datetime('now'))
      )
    `);

    this.ensureBaseSchema(db);

    const migrationsDir = process.env.NODE_ENV === 'development' || !app.isPackaged
      ? path.join(app.getAppPath(), 'src/main/db')
      : path.join(process.resourcesPath, 'db');

    const migrationFiles = [
      '013_manuscripts.sql',
      '018_db_p1a_time_format.sql',
      '020_db_add_task_type.sql',
      '021_teaching_progress.sql',
      '022_projects.sql',
      '023_data_migration.sql',
      '026_active_training.sql',
      '027_active_training_step_responses.sql',
      '028_active_training_drafts.sql',
      '029_active_training_audit_log.sql',
    ];

    for (const file of migrationFiles) {
      const filePath = path.join(migrationsDir, file);
      if (!fs.existsSync(filePath)) {
        console.warn(`[Migration] File not found: ${filePath}`);
        continue;
      }

      const alreadyApplied = db.prepare(
        'SELECT 1 FROM _migrations WHERE name = ?'
      ).get(file);
      if (alreadyApplied) {
        console.warn(`[Migration] Already applied: ${file}`);
        continue;
      }

      try {
        const sql = fs.readFileSync(filePath, 'utf-8');
        db.exec(sql);
        db.prepare('INSERT INTO _migrations (name) VALUES (?)').run(file);
        console.warn(`[Migration] Applied: ${file}`);
      } catch (err) {
        // 018 是 TEXT→INTEGER 格式转换迁移，如果旧表不存在则跳过
        //（例如从 ensureBaseSchema 新建数据库时）
        const is018Skippable = file === '018_db_p1a_time_format.sql';
        if (is018Skippable) {
          console.warn(`[Migration] Skipped ${file} (format conversion, not needed for fresh DB)`);
          db.prepare('INSERT OR IGNORE INTO _migrations (name) VALUES (?)').run(file);
        } else {
          console.error(`[Migration] Failed: ${file}`, err);
          throw err;
        }
      }
    }
  }

  private getResourcesRoot(): string {
    const isDev = process.env.NODE_ENV === 'development' || !app.isPackaged;
    return isDev ? path.join(app.getAppPath(), 'resources') : process.resourcesPath;
  }
}
