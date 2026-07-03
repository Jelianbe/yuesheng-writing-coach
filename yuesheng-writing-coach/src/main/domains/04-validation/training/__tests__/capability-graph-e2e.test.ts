/**
 * T15-C.6 能力图谱消费链 — 端到端测试
 *
 * 验证全链路通畅：
 *   诊断触发 → 教学状态机 → 训练推荐 → 能力画像
 *
 * 核心不变量（按 R-018 变更溯源）：
 *   1. 诊断结果的 syndromeId（P-XXX）↔ 教学状态机的 activeProblems.syndromeId
 *   2. activeProblems.syndromeId ↔ 训练推荐的 syndromeId
 *   3. 训练推荐同时含 CH-PXXX / TRAIN-PXXX / ABL-XXX 三向 ID（T15-B）
 *   4. 训练记录 taskId 落库后 ↔ 能力画像 abilities[].severityHistory
 *   5. getAbilityHighlights 把 activeProblems 与 ABL 节点串起来（T15-C.4）
 *
 * 测试设计：
 *   - 使用 in-memory SQLite，复用已有 schema（teaching_state / diagnosis_results /
 *     user_training_records / sessions）
 *   - 真实组件（无 mock）：DiagnosisService、TrainingRecordService、
 *     TeachingStateService、AbilityProfileService、TrainingRecommendation、loader
 *   - 不直接调用 SQLite 写入，而是通过 Service 抽象（贴近真实调用栈）
 *
 * @see dev-docs/designs/sprint-15-plan.md §T15-C.6
 * @see dev-docs/designs/adr/005-training-task-single-source-of-truth.md
 */

import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';

// ============ 领域服务 ============
import { DiagnosisService } from '../../../01-diagnosis/diagnosis.service';
import { TrainingRecordService } from '../training-record.service';
import { TeachingStateService } from '../../../03-teaching/teaching-state.service';
import { AbilityProfileService } from '../../../02-prescription/student/ability-profile.service';
import { ProfileDataAggregator } from '../../../02-prescription/student/profile-data-aggregator';

// ============ 推荐与图谱 loader ============
import { generateRecommendations } from '../training-recommendation.service';
import { t0xxToTrain } from '../task-id-mapping.loader';
import {
  getAbilitiesBySyndrome,
  getAllAbilityNodes,
} from '../../../02-prescription/ability-atlas/ability-atlas.loader';

// ============ 类型 ============
import type { DiagnosisEntry, ActiveProblem } from '../../../../../shared/types/index';
import { TeachingPhase, TeachingSubphase } from '../../../../../shared/constants';

// ============ 测试用 fixture ============

const MIGRATIONS_DIR = path.join(__dirname, '..', '..', '..', '..', 'db');
const MIGRATION_FILES = [
  '013_manuscripts.sql',
  '021_teaching_progress.sql',
  '022_projects.sql',
  '023_data_migration.sql',
];

let TEST_RUN_ID = 0;

/** 维护当前测试的 sessionId（解决字母序 e2e-11 < e2e-5 错乱） */
let CURRENT_SESSION_ID = '';

function makeDiagnosis(
  sessionId: string,
  syndromes: Array<{ id: string; severity: 'L1' | 'L2' | 'L3' }>,
  confidence = 0.85,
): DiagnosisEntry {
  return {
    sessionId,
    messageId: `msg-${++TEST_RUN_ID}`,
    syndromes: syndromes.map((s, idx) => ({
      id: s.id,
      name: `症候 ${s.id}`,
      severity: s.severity,
      confidence,
      score: s.severity === 'L3' ? 90 : s.severity === 'L2' ? 60 : 30,
      evidence: [`原文片段 #${idx + 1}`],
      suggestedActions: [],
    })),
    suggestedActions: [],
    confidence,
    timestamp: new Date(Date.now() + TEST_RUN_ID * 1000).toISOString(),
  };
}

/** 构造一份与诊断结果对齐的 activeProblems（教学状态机消费） */
function problemsFromDiagnosis(diag: DiagnosisEntry): ActiveProblem[] {
  return diag.syndromes.map((s) => ({
    id: s.id,
    name: s.name,
    severity: s.severity,
    evidence: s.evidence ?? [],
    firstDetected: diag.timestamp,
    status: 'active' as const,
    detectionCount: 1,
    missedCount: 0,
    suggestedActions: [],
  }));
}

function createTestDb(): Database.Database {
  const db = new Database(':memory:');
  // 最小化 stub 表（沿用 021/022 测试 schema）
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
      user_response TEXT, ai_feedback TEXT, effectiveness INTEGER, score INTEGER,
      task_type TEXT DEFAULT 'writing'
    );
  `);
  db.pragma('foreign_keys = OFF');
  for (const file of MIGRATION_FILES) {
    try {
      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf-8');
      db.exec(sql);
    } catch {
      // 部分 migration 可能依赖不存在的字段，忽略（核心表已建好）
    }
  }
  db.pragma('foreign_keys = ON');
  return db;
}

// ============ 测试主流程 ============

describe('T15-C.6 能力图谱消费链 — 端到端', () => {
  let db: Database.Database;
  let diagnosisSvc: DiagnosisService;
  let trainingSvc: TrainingRecordService;
  let teachingSvc: TeachingStateService;
  let profileSvc: AbilityProfileService;

  beforeAll(() => {
    db = createTestDb();
    diagnosisSvc = new DiagnosisService(db);
    trainingSvc = new TrainingRecordService(db);
    teachingSvc = new TeachingStateService();
    teachingSvc.initStore(db);
    const aggregator = new ProfileDataAggregator(
      diagnosisSvc as unknown as InstanceType<typeof DiagnosisService>,
      trainingSvc,
    );
    profileSvc = new AbilityProfileService(aggregator);
  });

  beforeEach(() => {
    // 每个 case 准备独立 session，避免相互污染
    CURRENT_SESSION_ID = `e2e-${++TEST_RUN_ID}`;
    db.prepare('INSERT INTO sessions (id, title) VALUES (?, ?)').run(CURRENT_SESSION_ID, `E2E Session ${TEST_RUN_ID}`);
  });

  // ----------------------------------------------------------------
  // 场景 1：单症候 P001 全链路（诊断→教学→推荐→画像）
  // ----------------------------------------------------------------
  it('场景1：P001 诊断应能贯通 教学状态→训练推荐→能力画像', () => {
    const sessionId = CURRENT_SESSION_ID;

    // 1) 触发诊断：3 次 P001 L2（确保画像够 3 次样本）
    const diags: DiagnosisEntry[] = [
      makeDiagnosis(sessionId, [{ id: 'P001', severity: 'L2' }]),
      makeDiagnosis(sessionId, [{ id: 'P001', severity: 'L2' }]),
      makeDiagnosis(sessionId, [{ id: 'P001', severity: 'L2' }]),
    ];
    for (const d of diags) diagnosisSvc.save(d);

    const persisted = diagnosisSvc.getBySession(sessionId);
    expect(persisted).toHaveLength(3);
    expect(persisted[0].syndromes[0].id).toBe('P001');

    // 2) 教学状态机：写入 activeProblems + 推进到 PRACTICE_LOOP
    teachingSvc.getOrCreate(sessionId);
    teachingSvc.update(sessionId, {
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_IDENTIFY,
      activeProblems: problemsFromDiagnosis(diags[0]),
      diagnosisSummary: 'P001 世界观膨胀（连续 3 次 L2）',
    });

    const reloaded = teachingSvc.getBySession(sessionId);
    expect(reloaded?.activeProblems).toHaveLength(1);
    expect(reloaded?.activeProblems[0].id).toBe('P001');

    // 3) 训练推荐：基于 activeProblems
    const recs = generateRecommendations(reloaded!.activeProblems);
    expect(recs).toHaveLength(1);
    const r = recs[0];

    // 4) 三向 ID 校验（T15-B）
    expect(r.syndromeId).toBe('P001');
    expect(r.challengeId).toMatch(/^CH-P001-/);
    expect(r.relatedTrainIds).toBeDefined();
    expect(r.relatedTrainIds?.[0]).toMatch(/^TRAIN-P001-/);
    expect(r.abilityNodeIds).toContain('ABL-001'); // P001 → 结构控制
    expect(r.abilityNodeIds).toContain('ABL-005'); // P001 → 世界观工程

    // 5) 能力亮点（T15-C.4）
    const highlights = teachingSvc.getAbilityHighlights(sessionId);
    expect(highlights).toHaveLength(1);
    expect(highlights[0].syndromeId).toBe('P001');
    expect(highlights[0].abilities.length).toBeGreaterThanOrEqual(1);
    const abilityIds = highlights[0].abilities.map((a) => a.atlasId);
    expect(abilityIds).toContain('ABL-001');

    // 6) 完成训练 → 记录入 user_training_records
    const taskId = r.relatedTrainIds![0];
    const record = trainingSvc.assign({
      sessionId,
      taskId,
      syndromeId: 'P001',
      taskType: 'writing',
      userResponse: null,
      aiFeedback: null,
      effectiveness: null,
      score: null,
    });
    expect(record.status).toBe('assigned');

    const completed = trainingSvc.complete(record.id, {
      userResponse: '已重写',
      score: 8,
      effectiveness: 4,
    });
    expect(completed?.status).toBe('completed');
    expect(completed?.score).toBe(8);

    // 7) 能力画像：应反映 ABL-001 的严重度历史
    const profile = profileSvc.computeProfile(sessionId);
    const abl001 = profile.abilities.find((a) => a.abilityId === 'ABL-001');
    expect(abl001).toBeDefined();
    expect(abl001!.relatedSyndromes).toContain('P001');
    expect(abl001!.severityHistory.length).toBeGreaterThanOrEqual(3);
    expect(profile.trainingStats.totalCompleted).toBe(1);
    expect(profile.trainingStats.bySyndrome['P001'].completed).toBe(1);
    expect(profile.weakPoints.some((w) => w.syndromeId === 'P001')).toBe(true);
  });

  // ----------------------------------------------------------------
  // 场景 2：多症候联合 P001 L3 + P003 L2（排序 + 高亮）
  // ----------------------------------------------------------------
  it('场景2：P001 L3 + P003 L2 应正确排序并产出双能力高亮', () => {
    const sessionId = CURRENT_SESSION_ID;

    const diag = makeDiagnosis(sessionId, [
      { id: 'P003', severity: 'L2' },
      { id: 'P001', severity: 'L3' },
    ]);
    diagnosisSvc.save(diag);

    teachingSvc.getOrCreate(sessionId);
    teachingSvc.update(sessionId, {
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_ASSIGN,
      activeProblems: problemsFromDiagnosis(diag),
    });

    const reloaded = teachingSvc.getBySession(sessionId)!;
    const recs = generateRecommendations(reloaded.activeProblems);

    // 排序：L3 优先
    expect(recs).toHaveLength(2);
    expect(recs[0].syndromeId).toBe('P001'); // L3
    expect(recs[1].syndromeId).toBe('P003'); // L2

    // 每条都含三向 ID
    for (const r of recs) {
      expect(r.challengeId).toMatch(/^CH-P\d{3}-/);
      expect(r.relatedTrainIds?.[0]).toMatch(/^TRAIN-P\d{3}-/);
      expect(r.abilityNodeIds?.length).toBeGreaterThan(0);
    }

    // 能力高亮：P001 + P003 各一组
    const highlights = teachingSvc.getAbilityHighlights(sessionId);
    expect(highlights).toHaveLength(2);
    const sids = highlights.map((h) => h.syndromeId).sort();
    expect(sids).toEqual(['P001', 'P003']);
  });

  // ----------------------------------------------------------------
  // 场景 3：训练完成后降级（L2 → L1），推荐列表应过滤
  // ----------------------------------------------------------------
  it('场景3：训练评分达标后 severity 应降级，推荐列表应过滤该症候', () => {
    const sessionId = CURRENT_SESSION_ID;

    const diag = makeDiagnosis(sessionId, [{ id: 'P001', severity: 'L2' }]);
    diagnosisSvc.save(diag);

    teachingSvc.getOrCreate(sessionId);
    teachingSvc.update(sessionId, {
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_TEACHING,
      activeProblems: problemsFromDiagnosis(diag),
    });

    // 降级（L2→L1） — 模拟训练评分 ≥ 8 触发
    teachingSvc.downgradeSeverity(sessionId, 'P001', 9);

    const reloaded = teachingSvc.getBySession(sessionId)!;
    expect(reloaded.activeProblems[0].severity).toBe('L1');

    // L1 不进入推荐
    const recs = generateRecommendations(reloaded.activeProblems);
    expect(recs).toHaveLength(0);
  });

  // ----------------------------------------------------------------
  // 场景 4：能力图谱反向推荐 — 任务→能力反查
  // ----------------------------------------------------------------
  it('场景4：relatedTrainIds 中的 TRAIN-PXXX 任务应能映射到至少一个 ABL-XXX 能力节点', () => {
    const sessionId = CURRENT_SESSION_ID;

    const diag = makeDiagnosis(sessionId, [{ id: 'P002', severity: 'L2' }]);
    diagnosisSvc.save(diag);

    teachingSvc.getOrCreate(sessionId);
    teachingSvc.update(sessionId, {
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_GUIDE,
      activeProblems: problemsFromDiagnosis(diag),
    });

    const reloaded = teachingSvc.getBySession(sessionId)!;
    const recs = generateRecommendations(reloaded.activeProblems);
    const r = recs[0];

    expect(r.relatedTrainIds).toBeDefined();
    expect(r.relatedTrainIds!.length).toBeGreaterThan(0);

    // 反向校验：每个训练任务 ID 应在能力图谱中至少能找到一个相关 ABL 节点
    // ability-atlas.json 的 trainingTasks 存的是 T0XX（能力视角），
    // 通过 task-id-mapping 反向转换到 TRAIN-PXXX（任务视角）再校验。
    const allAbilities = getAllAbilityNodes();
    for (const trainId of r.relatedTrainIds!) {
      const matched = allAbilities.some((a) => {
        if (a.trainingTasks.includes(trainId)) return true;
        // 通过 T0XX 桥接：TRAIN → T0XX → ABL
        for (const t0xx of a.trainingTasks) {
          if (t0xxToTrain(t0xx) === trainId) return true;
        }
        return false;
      });
      expect(matched, `TRAIN ${trainId} 应能映射到至少一个 ABL 节点`).toBe(true);
    }
  });

  // ----------------------------------------------------------------
  // 场景 5：能力画像集成校验 — 多次诊断后画像完整
  // ----------------------------------------------------------------
  it('场景5：跨 3 个症候的多次诊断应产出完整的画像（含 trend / weakPoints / trainingStats）', () => {
    const sessionId = CURRENT_SESSION_ID;

    // 多次诊断覆盖 3 个症候
    const series: DiagnosisEntry[] = [];
    for (let i = 0; i < 3; i++) {
      series.push(makeDiagnosis(sessionId, [
        { id: 'P001', severity: i === 2 ? 'L3' : 'L2' },
        { id: 'P003', severity: 'L2' },
      ]));
    }
    for (const d of series) diagnosisSvc.save(d);

    // 训练完成记录（用真实 assign+complete 链）
    const tr1 = trainingSvc.assign({
      sessionId,
      taskId: 'TRAIN-P001-001',
      syndromeId: 'P001',
      taskType: 'writing',
      userResponse: null,
      aiFeedback: null,
      effectiveness: null,
      score: null,
    });
    trainingSvc.complete(tr1.id, { score: 7, effectiveness: 3 });

    const tr2 = trainingSvc.assign({
      sessionId,
      taskId: 'TRAIN-P003-001',
      syndromeId: 'P003',
      taskType: 'writing',
      userResponse: null,
      aiFeedback: null,
      effectiveness: null,
      score: null,
    });
    trainingSvc.complete(tr2.id, { score: 7, effectiveness: 3 });

    // 画像
    const profile = profileSvc.computeProfile(sessionId);

    // 诊断趋势（应只含本 session 的 3 次）
    expect(profile.diagnosisTrend.totalDiagnoses).toBe(3);
    expect(Object.keys(profile.diagnosisTrend.syndromeFrequency).sort()).toEqual(['P001', 'P003']);

    // 训练统计
    expect(profile.trainingStats.totalAssigned).toBeGreaterThanOrEqual(1);
    expect(profile.trainingStats.completionRate).toBeGreaterThanOrEqual(0);

    // 至少 1 个 ABL 节点能从诊断历史推导出非空 severityHistory
    const withHistory = profile.abilities.filter((a) => a.severityHistory.length > 0);
    expect(withHistory.length).toBeGreaterThan(0);

    // 弱点：P001 出现 3 次 + L3 → 必定出现
    expect(profile.weakPoints.some((w) => w.syndromeId === 'P001')).toBe(true);
  });

  // ----------------------------------------------------------------
  // 场景 6：图谱 loader 不变量 — 8 个能力节点 + 10 个症候覆盖
  // ----------------------------------------------------------------
  it('场景6：能力图谱 loader 应满足覆盖性不变量（8+ 节点 / 10+ 症候）', () => {
    const allAbilities = getAllAbilityNodes();
    expect(allAbilities.length).toBeGreaterThanOrEqual(8);
    for (const a of allAbilities) {
      expect(a.atlasId).toMatch(/^ABL-\d{3}$/);
    }

    // 10 个症候都能查到至少 1 个 ABL
    const syndromeIds = ['P001', 'P002', 'P003', 'P004', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010'];
    const withAbilities = syndromeIds.filter((sid) => getAbilitiesBySyndrome(sid).length > 0);
    // P008 已知为孤儿症候，不强求
    expect(withAbilities.length).toBeGreaterThanOrEqual(8);
  });

  // ----------------------------------------------------------------
  // 场景 7：TeachingStateService.getFullStateWithAbilities 集成
  // ----------------------------------------------------------------
  it('场景7：getFullStateWithAbilities 应返回含 abilityHighlights 的完整状态', () => {
    const sessionId = CURRENT_SESSION_ID;

    const diag = makeDiagnosis(sessionId, [{ id: 'P003', severity: 'L2' }]);
    diagnosisSvc.save(diag);

    teachingSvc.getOrCreate(sessionId);
    teachingSvc.update(sessionId, {
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_IDENTIFY,
      activeProblems: problemsFromDiagnosis(diag),
    });

    const full = teachingSvc.getFullStateWithAbilities(sessionId);
    expect(full).toBeDefined();
    expect(full!.phaseName).toBeDefined();
    expect(full!.subphaseName).toBeDefined();
    expect(full!.phaseProgress).toBeGreaterThanOrEqual(0);
    expect(Array.isArray(full!.abilityHighlights)).toBe(true);
    expect(full!.abilityHighlights.some((h) => h.syndromeId === 'P003')).toBe(true);
  });
});
