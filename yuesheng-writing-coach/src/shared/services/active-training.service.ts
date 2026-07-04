/**
 * ActiveTrainingService — Sprint 26 跨端版
 *
 * 双端共用,接 StorageAdapter:
 * - Electron 端: 用 BetterSqliteAdapter(走主进程,经 IPC)
 * - Android 端: 用 CapacitorSqliteAdapter(走 WebView 直接调用)
 *
 * 关键差异(对比 main/domains/03-teaching/state/active-training.store.ts):
 * - 同步 → 异步
 * - `better-sqlite3.Database` → `StorageAdapter`
 * - 直接 prepare/run/get 改为 `adapter.query()` / `adapter.execute()`
 * - 行→ActiveTraining 投影集中到 service 层(JSON 字段自动 parse/stringify)
 *
 * 范围:
 * - 本文件仅做 active_training 表的 CRUD(8 个核心方法)
 * - 状态机业务逻辑(start/advanceStep/submitFlowStep/updateDraft/evaluate/complete/abort + onStateChange)
 *   仍在主进程 active-training.service.ts 中,R-020 边界隔离
 * - T26-2.5 暂不强制主进程切换,新 service 供 Android 端使用
 *
 * 依据: dev-docs/tasks/sprint-26-2-5-plan.md
 * 决策: D-074
 */
import type { StorageAdapter } from '../storage/storage-adapter';
import type { DatabaseRow } from '../storage/storage-types';

/** 训练步骤(主进程侧独立定义,与 renderer 兼容,R-020 边界隔离) */
export interface TrainingStep {
  id: string;
  title: string;
  description: string;
  status: 'completed' | 'active' | 'pending';
}

/** 训练流步骤(flow5 通用流 1-5) */
export interface TrainingFlowStep {
  stepId: 1 | 2 | 3 | 4 | 5;
  name: string;
  instruction: string;
  userAction: string;
  estimatedMinutes: number;
  coachingHint?: string;
}

/** 完整训练流 */
export interface TrainingFlow {
  syndromeId: string;
  techniqueName: string;
  category: string;
  steps: TrainingFlowStep[];
  estimatedTotalMinutes: number;
  abilityNodeIds?: string[];
}

/** 数据库存储状态字面量 */
export type ActiveTrainingStatus = 'in_progress' | 'completed' | 'aborted';

/** 评估结果快照 */
export interface SubmissionResultSnapshot {
  passed: boolean;
  feedback: string;
  score?: number;
  evaluatedAt: string;
}

/** 5 步通用流每步提交的回答 */
export interface StepResponse {
  stepId: 1 | 2 | 3 | 4 | 5;
  content: string;
  submittedAt: string;
}

/** 领域对象: ActiveTraining */
export interface ActiveTraining {
  id: number;
  sessionId: string;
  challengeId: string;
  challengeName: string | null;
  mode: string | null;
  currentStepIndex: number;
  steps: TrainingStep[];
  userDraft: string;
  flowType: 'flow5' | 'legacy' | null;
  trainingFlow: TrainingFlow | null;
  recordId: string | null;
  syndromeId: string | null;
  originalQuote: string | null;
  constraint: string | null;
  submissionResult: SubmissionResultSnapshot | null;
  stepResponses: StepResponse[];
  status: ActiveTrainingStatus;
  startedAt: string;
  updatedAt: string;
  completedAt: string | null;
}

/** 数据库行: ActiveTrainingRow (snake_case + JSON 字符串字段) */
export interface ActiveTrainingRow extends DatabaseRow {
  id: number;
  session_id: string;
  challenge_id: string;
  challenge_name: string | null;
  mode: string | null;
  current_step_index: number;
  steps_json: string;
  user_draft: string;
  flow_type: string | null;
  training_flow_json: string | null;
  record_id: string | null;
  syndrome_id: string | null;
  original_quote: string | null;
  constraint_text: string | null;
  submission_result_json: string | null;
  step_responses_json: string;
  status: string;
  started_at: string;
  updated_at: string;
  completed_at: string | null;
}

/** 创建输入 */
export interface CreateActiveTrainingInput {
  sessionId: string;
  challengeId: string;
  challengeName?: string;
  mode?: string;
  steps: TrainingStep[];
  flowType?: 'flow5' | 'legacy';
  trainingFlow?: TrainingFlow;
  syndromeId?: string;
  originalQuote?: string;
  constraint?: string;
  source: 'training_triggered' | 'user_request' | 'diagnosis_result' | 'prescription';
}

/** 更新输入(部分更新) */
export interface UpdateActiveTrainingInput {
  challengeName?: string;
  mode?: string;
  currentStepIndex?: number;
  steps?: TrainingStep[];
  userDraft?: string;
  flowType?: 'flow5' | 'legacy' | null;
  trainingFlow?: TrainingFlow | null;
  recordId?: string | null;
  syndromeId?: string | null;
  originalQuote?: string | null;
  constraint?: string | null;
  submissionResult?: SubmissionResultSnapshot | null;
  stepResponses?: StepResponse[];
  status?: ActiveTrainingStatus;
  completedAt?: string | null;
}

/** 状态字面量守卫:不合法时回退 in_progress(防御性) */
function isValidActiveTrainingStatus(s: string): s is ActiveTrainingStatus {
  return s === 'in_progress' || s === 'completed' || s === 'aborted';
}

/** 安全的 JSON.parse(失败时回退 + warn) */
function safeParseJson<T>(json: string | null, fallback: T): T {
  if (!json) return fallback;
  try {
    return JSON.parse(json) as T;
  } catch (e) {
    console.warn('[ActiveTrainingService] safeParseJson failed:', e);
    return fallback;
  }
}

function rowToActiveTraining(row: ActiveTrainingRow): ActiveTraining {
  const status: ActiveTrainingStatus = isValidActiveTrainingStatus(row.status)
    ? row.status
    : 'in_progress';

  return {
    id: row.id,
    sessionId: row.session_id,
    challengeId: row.challenge_id,
    challengeName: row.challenge_name,
    mode: row.mode,
    currentStepIndex: row.current_step_index,
    steps: safeParseJson<TrainingStep[]>(row.steps_json, []),
    userDraft: row.user_draft,
    flowType: row.flow_type === 'flow5' || row.flow_type === 'legacy' ? row.flow_type : null,
    trainingFlow: safeParseJson<TrainingFlow | null>(row.training_flow_json, null),
    recordId: row.record_id,
    syndromeId: row.syndrome_id,
    originalQuote: row.original_quote,
    constraint: row.constraint_text,
    submissionResult: safeParseJson<SubmissionResultSnapshot | null>(
      row.submission_result_json,
      null,
    ),
    stepResponses: safeParseJson<StepResponse[]>(row.step_responses_json, []),
    status,
    startedAt: row.started_at,
    updatedAt: row.updated_at,
    completedAt: row.completed_at,
  };
}

export class ActiveTrainingService {
  constructor(private readonly adapter: StorageAdapter) {}

  /**
   * 获取指定 session 的最新训练记录(任意状态,按 id DESC 排序)
   * - 业务语义: 同一 session 可能有多个历史行(completed/aborted),返回最新一行
   */
  async getBySession(sessionId: string): Promise<ActiveTraining | null> {
    try {
      const rows = await this.adapter.query<ActiveTrainingRow>(
        'SELECT * FROM active_training WHERE session_id = ? ORDER BY id DESC LIMIT 1',
        [sessionId],
      );
      return rows[0] ? rowToActiveTraining(rows[0]) : null;
    } catch (e) {
      console.error('[ActiveTrainingService] getBySession failed:', e);
      return null;
    }
  }

  /**
   * 获取当前进行中的训练(status = in_progress)
   */
  async getActiveBySession(sessionId: string): Promise<ActiveTraining | null> {
    try {
      const row = await this.adapter.queryOne<ActiveTrainingRow>(
        'SELECT * FROM active_training WHERE session_id = ? AND status = ?',
        [sessionId, 'in_progress'],
      );
      return row ? rowToActiveTraining(row) : null;
    } catch (e) {
      console.error('[ActiveTrainingService] getActiveBySession failed:', e);
      return null;
    }
  }

  /**
   * 创建活跃训练
   * - 业务规则: 同一 session 已有 in_progress 训练时,先标记为 aborted
   * - 失败返回 null(异常隔离)
   */
  async create(input: CreateActiveTrainingInput): Promise<ActiveTraining | null> {
    try {
      const now = new Date().toISOString();
      // 业务规则: 同一 session 已有 in_progress 训练时,先标记为 aborted
      const existing = await this.getActiveBySession(input.sessionId);
      if (existing) {
        await this.update(input.sessionId, { status: 'aborted', completedAt: now });
      }

      const result = await this.adapter.execute(
        `INSERT INTO active_training (
          session_id, challenge_id, challenge_name, mode,
          current_step_index, steps_json, user_draft,
          flow_type, training_flow_json, record_id, syndrome_id,
          original_quote, constraint_text, submission_result_json,
          step_responses_json,
          status, started_at, updated_at, completed_at
        ) VALUES (
          ?, ?, ?, ?,
          ?, ?, ?,
          ?, ?, ?, ?,
          ?, ?, ?,
          ?,
          ?, ?, ?, ?
        )`,
        [
          input.sessionId,
          input.challengeId,
          input.challengeName ?? null,
          input.mode ?? null,
          0,
          JSON.stringify(input.steps),
          '',
          input.flowType ?? null,
          input.trainingFlow ? JSON.stringify(input.trainingFlow) : null,
          null,
          input.syndromeId ?? null,
          input.originalQuote ?? null,
          input.constraint ?? null,
          null,
          '[]',
          'in_progress',
          now,
          now,
          null,
        ],
      );

      // 读回完整对象
      const created = await this.getById(Number(result.lastInsertId));
      return created;
    } catch (e) {
      console.error('[ActiveTrainingService] create failed:', e);
      return null;
    }
  }

  /**
   * 根据 ID 获取(内部用)
   */
  private async getById(id: number): Promise<ActiveTraining | null> {
    try {
      const row = await this.adapter.queryOne<ActiveTrainingRow>(
        'SELECT * FROM active_training WHERE id = ?',
        [id],
      );
      return row ? rowToActiveTraining(row) : null;
    } catch (e) {
      console.error('[ActiveTrainingService] getById failed:', e);
      return null;
    }
  }

  /**
   * 更新活跃训练(部分更新)
   */
  async update(
    sessionId: string,
    updates: UpdateActiveTrainingInput,
  ): Promise<ActiveTraining | null> {
    try {
      const existing = await this.getBySession(sessionId);
      if (!existing) {
        console.warn(`[ActiveTrainingService] update: no record for session ${sessionId}`);
        return null;
      }

      const now = new Date().toISOString();
      const updated: ActiveTraining = {
        ...existing,
        ...updates,
        updatedAt: now,
      };

      await this.adapter.execute(
        `UPDATE active_training SET
          challenge_name = ?,
          mode = ?,
          current_step_index = ?,
          steps_json = ?,
          user_draft = ?,
          flow_type = ?,
          training_flow_json = ?,
          record_id = ?,
          syndrome_id = ?,
          original_quote = ?,
          constraint_text = ?,
          submission_result_json = ?,
          step_responses_json = ?,
          status = ?,
          updated_at = ?,
          completed_at = ?
        WHERE session_id = ?`,
        [
          updated.challengeName,
          updated.mode,
          updated.currentStepIndex,
          JSON.stringify(updated.steps),
          updated.userDraft,
          updated.flowType,
          updated.trainingFlow ? JSON.stringify(updated.trainingFlow) : null,
          updated.recordId,
          updated.syndromeId,
          updated.originalQuote,
          updated.constraint,
          updated.submissionResult ? JSON.stringify(updated.submissionResult) : null,
          JSON.stringify(updated.stepResponses),
          updated.status,
          updated.updatedAt,
          updated.completedAt,
          sessionId,
        ],
      );

      return updated;
    } catch (e) {
      console.error('[ActiveTrainingService] update failed:', e);
      return null;
    }
  }

  /**
   * 删除指定 session 的活跃训练记录
   * - 业务语义: 通常不主动删除,Complete/Abort 保留行供审计
   * - 此方法供"硬重置"等特殊场景使用
   */
  async delete(sessionId: string): Promise<boolean> {
    try {
      const result = await this.adapter.execute(
        'DELETE FROM active_training WHERE session_id = ?',
        [sessionId],
      );
      return result.changes > 0;
    } catch (e) {
      console.error('[ActiveTrainingService] delete failed:', e);
      return false;
    }
  }

  /**
   * C-4: 更新 5 步分步回答(整数组替换)
   * - 调用方负责合并(同 stepId 多次提交时取最新),service 只接受最终数组
   */
  async updateStepResponses(
    sessionId: string,
    stepResponses: StepResponse[],
  ): Promise<ActiveTraining | null> {
    return this.update(sessionId, { stepResponses });
  }

  /**
   * 获取所有进行中的训练(全局查询,供监控/调试)
   */
  async listActive(): Promise<ActiveTraining[]> {
    try {
      const rows = await this.adapter.query<ActiveTrainingRow>(
        'SELECT * FROM active_training WHERE status = ? ORDER BY updated_at DESC',
        ['in_progress'],
      );
      return rows.map(rowToActiveTraining);
    } catch (e) {
      console.error('[ActiveTrainingService] listActive failed:', e);
      return [];
    }
  }

  /**
   * 按症候 ID 查询(诊断联动)
   */
  async findBySyndrome(syndromeId: string): Promise<ActiveTraining[]> {
    try {
      const rows = await this.adapter.query<ActiveTrainingRow>(
        'SELECT * FROM active_training WHERE syndrome_id = ? ORDER BY updated_at DESC',
        [syndromeId],
      );
      return rows.map(rowToActiveTraining);
    } catch (e) {
      console.error('[ActiveTrainingService] findBySyndrome failed:', e);
      return [];
    }
  }
}
