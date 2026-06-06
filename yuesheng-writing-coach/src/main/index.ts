// 月笙写作教练 - 主进程入口
// 负责：窗口管理、应用生命周期、IPC 注册

import { app, BrowserWindow } from 'electron';
import * as path from 'path';
import * as fs from 'fs';
import Database from 'better-sqlite3';
import { registerConfigHandlers, setConfigService as setConfigHandlerService } from './ipc/config.handler';
import { registerDiagnosisHandlers, setMainWindow as setDiagnosisMainWindow, setDiagnosisMerger, setTeachingStateGetter, setDiagnosisService, setEvidenceService as setEvidenceServiceForDiagnosis, setGrowthTrendService, setConfigService as setDiagnosisConfigService } from './ipc/diagnosis.handler';
import { registerTeachingStateHandlers, initStore as initTeachingStore, setMainWindow as setTeachingMainWindow, setPromptBuilder, getPromptBuilder, registerDiagnosisMerger, getTeachingStateContext, getStoreForPromptLoader } from './ipc/teaching-state.handler';
import { PromptLoader } from './services/prompt-loader';
import { MessageRouter } from './services/message-router';
import { SessionService } from './services/session.service';
import { DiagnosisService } from './services/diagnosis.service';
import { registerChatHandlers, setMainWindow as setChatMainWindow, setSessionService, setDiagnosisService as setChatDiagnosisService, setPromptLoader, setMessageRouter, setStudentModelService, setTeachingStrategyService, setProblemPrioritizer, setConfigService as setChatConfigService } from './ipc/chat.handler';
import { registerSessionHandlers, setSessionService as setSessionHandlerService } from './ipc/session.handler';
import { registerAbilityProfileHandlers, setAbilityProfileService } from './ipc/ability-profile.handler';
import { registerEvidenceHandlers, setEvidenceService } from './ipc/evidence.handler';
import { registerTrainingHandlers, setTrainingRecordService, setStudentModelService as setTrainingStudentModelService, setMainWindow as setTrainingMainWindow, setConfigService as setTrainingConfigService } from './ipc/training.handler';
import { TrainingRecordService } from './services/training-record.service';
import { AbilityProfileService } from './services/ability-profile.service';
import { StudentModelService } from './services/student-model.service';
import { GrowthTrendService } from './services/growth-trend.service';
import { EvidenceService } from './services/evidence.service';
import { PromptBuilder } from './services/prompt-builder';
import { TeachingStrategyService } from './services/teaching-strategy.service';
import { ProblemPrioritizer } from './services/problem-prioritizer.service';
import { DynamicContextService } from './services/dynamic-context.service';
import { ConfigService } from './services/config.service';
import { injectMockDiagnosisData } from './services/mock-data-injector';
import { setResourcesRoot } from './services/transition-prompt-loader';

let mainWindow: BrowserWindow | null = null;

/**
 * 初始化数据库
 */
function initDatabase(): Database.Database {
  const dbPath = path.join(app.getPath('userData'), 'yuesheng.db');
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  return db;
}

/**
 * 运行数据库迁移（带跟踪表，确保幂等性）
 */
function runMigrations(db: Database.Database): void {
  // 创建迁移跟踪表
  db.exec(`
    CREATE TABLE IF NOT EXISTS _migrations (
      name TEXT PRIMARY KEY,
      applied_at TEXT DEFAULT (datetime('now'))
    )
  `);

  // 兼容旧版无跟踪的数据库：检查已有字段/表，标记为已迁移
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
  ];

  for (const file of migrationFiles) {
    const filePath = path.join(migrationsDir, file);
    if (!fs.existsSync(filePath)) {
      console.warn(`[Migration] File not found: ${filePath}`);
      continue;
    }

    // 检查是否已应用
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

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  // 设置主窗口引用（用于诊断结果推送和教学状态推送）
  setDiagnosisMainWindow(mainWindow);
  setTeachingMainWindow(mainWindow);
  setChatMainWindow(mainWindow);

  // 开发模式加载 Vite dev server
  if (process.env.NODE_ENV === 'development') {
    mainWindow.loadURL('http://localhost:5173');
    mainWindow.webContents.openDevTools();
  } else {
    // 生产模式加载打包文件
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(() => {
  // 初始化数据库和迁移
  const db = initDatabase();
  runMigrations(db);

  // 统一计算资源根路径，消除 Service 对 app 模块的直接依赖
  const resourcesRoot = app.isPackaged ? process.resourcesPath : path.join(app.getAppPath(), 'resources');
  setResourcesRoot(resourcesRoot);

  // 创建 ConfigService 实例并注入到所有 IPC handler，消除静态 getInstance() 调用
  const configService = new ConfigService();
  setConfigHandlerService(configService);
  setDiagnosisConfigService(configService);
  setChatConfigService(configService);
  setTrainingConfigService(configService);

  // 开发模式下注入模拟数据
  if (process.env.NODE_ENV === 'development') {
    injectMockDiagnosisData(db);
  }

  const sessionService = new SessionService(db);
  initTeachingStore(db);

  const diagnosisService = new DiagnosisService(db);
  setDiagnosisService(diagnosisService);
  // 注册 DiagnosisMerger（由 teaching-state.handler 内部提供 getStore）
  registerDiagnosisMerger(setDiagnosisMerger);
  // 注入只读 TeachingState getter（用于 DIAGNOSIS_QUERY）
  setTeachingStateGetter((sessionId: string) => {
    const context = getTeachingStateContext(sessionId);
    if (!context) return null;
    return { activeProblems: context.activeProblems };
  });

  const trainingRecordService = new TrainingRecordService(db);
  const abilityProfileService = new AbilityProfileService(db, diagnosisService, trainingRecordService, resourcesRoot);
  setAbilityProfileService(abilityProfileService);

  const studentModelService = new StudentModelService(db, diagnosisService, trainingRecordService, resourcesRoot);
  setStudentModelService(studentModelService);

  // 创建成长趋势服务并注册到 diagnosis handler
  const growthTrendService = new GrowthTrendService(studentModelService);
  setGrowthTrendService(growthTrendService);

  // 创建教学策略服务和问题优先级排序服务
  const teachingStrategyService = new TeachingStrategyService(resourcesRoot);
  const problemPrioritizer = new ProblemPrioritizer(resourcesRoot);

  // 注入到 chat handler
  setTeachingStrategyService(teachingStrategyService);
  setProblemPrioritizer(problemPrioritizer);

  const evidenceService = new EvidenceService(db);
  setEvidenceService(evidenceService);
  setEvidenceServiceForDiagnosis(evidenceService); // wire to diagnosis handler

  // 创建 PromptBuilder 并注册到 teaching-state.handler
  const promptBuilder = new PromptBuilder();
  setPromptBuilder(promptBuilder);

  // 注入 PromptLoader 和 MessageRouter
  const promptLoader = new PromptLoader(resourcesRoot);
  promptLoader.setStateContextGetter((sessionId: string) => {
    const context = getTeachingStateContext(sessionId);
    if (!context || !context.currentPhase || !context.currentSubphase) return null;
    return { currentPhase: context.currentPhase, currentSubphase: context.currentSubphase };
  });
  // 注入 PromptBuilder 和 Store getter（连接教学进度到 System Prompt）
  promptLoader.setPromptBuilder(promptBuilder);
  promptLoader.setStoreGetter(getStoreForPromptLoader);

  // 创建 DynamicContextService 并注入 PromptLoader
  const dynamicContextService = new DynamicContextService(resourcesRoot);
  promptLoader.setDynamicContextService(dynamicContextService);

  setPromptLoader(promptLoader);
  setMessageRouter(new MessageRouter());

  // 注册 IPC handlers
  registerConfigHandlers();
  registerDiagnosisHandlers();
  registerTeachingStateHandlers();
  registerAbilityProfileHandlers();
  registerEvidenceHandlers();

  // 注册训练 IPC handlers
  setTrainingRecordService(trainingRecordService);
  setTrainingStudentModelService(studentModelService);
  setTrainingMainWindow(mainWindow);
  registerTrainingHandlers();

  setSessionService(sessionService);
  setChatDiagnosisService(diagnosisService);
  registerChatHandlers();
  setSessionHandlerService(sessionService);
  registerSessionHandlers();

  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
