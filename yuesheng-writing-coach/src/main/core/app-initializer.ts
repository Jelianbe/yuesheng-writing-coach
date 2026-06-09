import { app, BrowserWindow } from 'electron';
import Database from 'better-sqlite3';
import * as path from 'path';
import * as fs from 'fs';
import { ServiceContainer } from './service-container';
import { configureServices } from './service-config';
import { IpcRegistry } from './ipc-registry';
import { WindowManager } from './window-manager';
import { setResourcesRoot } from '../services/transition-prompt-loader';

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
    const dbPath = path.join(app.getPath('userData'), 'yuesheng.db');
    const db = new Database(dbPath);
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');
    db.pragma('synchronous = NORMAL');
    db.pragma('cache_size = -64000');
    return db;
  }

  private runMigrations(db: Database.Database): void {
    db.exec(`
      CREATE TABLE IF NOT EXISTS _migrations (
        name TEXT PRIMARY KEY,
        applied_at TEXT DEFAULT (datetime('now'))
      )
    `);

    const hasFocusArea = db.prepare(
      "SELECT 1 FROM pragma_table_info('teaching_state') WHERE name = 'focus_area'"
    ).get();
    if (hasFocusArea) {
      db.prepare(
        "INSERT OR IGNORE INTO _migrations (name) VALUES ('006_add_focus_area.sql')"
      ).run();
    }

    const migrationsDir = app.isPackaged
      ? path.join(process.resourcesPath, 'db')
      : path.join(app.getAppPath(), 'src/main/db');

    const migrationFiles = [
      '003_create_teaching_state.sql',
      '004_create_chat.sql',
      '005_diagnosis.sqlite',
      '006_add_focus_area.sql',
      '007_user_training.sql',
      '008_evidence.sql',
      '010_add_root_cause_analysis.sql',
      '011_add_locked_syndromes.sql',
      '012_add_training_score.sql',
      '013_manuscripts.sql',
      '014_sessions_extend.sql',
      '015_fix_diagnosis_results.sql',
      '016_check_constraints.sql',
      '017_fts5_messages.sql',
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
        console.log(`[Migration] Already applied: ${file}`);
        continue;
      }

      try {
        const sql = fs.readFileSync(filePath, 'utf-8');
        db.exec(sql);
        db.prepare('INSERT INTO _migrations (name) VALUES (?)').run(file);
        console.log(`[Migration] Applied: ${file}`);
      } catch (err) {
        console.error(`[Migration] Failed: ${file}`, err);
        throw err;
      }
    }
  }

  private getResourcesRoot(): string {
    return app.isPackaged ? process.resourcesPath : path.join(app.getAppPath(), 'resources');
  }
}
