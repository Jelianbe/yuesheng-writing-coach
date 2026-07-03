/**
 * ActiveTrainingStore — Sprint 24 A-1
 *
 * 职责: active_training 表的 CRUD 访问层
 * 设计: 与 TeachingStateStore 风格一致(R-019 一致性)
 *   - 数组/对象字段在 DB 中存 JSON 字符串
 *   - 读时自动 JSON.parse,写时自动 JSON.stringify
 *   - 字段转换集中在 rowToActiveTraining / activeTrainingToRow 两个函数
 *
 * 关键约束:
 *   - session_id UNIQUE: 同一 session 同时只有一个活跃训练
 *   - status CHECK: in_progress | completed | aborted(由 isValidActiveTrainingStatus 守卫)
 *   - 异常隔离: 任何 DB 错误仅 console.error,不抛出(上层处理)
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-1
 */

import type Database from 'better-sqlite3';
import type {
  ActiveTraining,
  ActiveTrainingRow,
  CreateActiveTrainingInput,
  UpdateActiveTrainingInput,
  ActiveTrainingStatus,
  StepResponse,
  SubmissionResultSnapshot,
  TrainingStep,
  TrainingFlow,
} from './active-training.types';
import { isValidActiveTrainingStatus } from './active-training.types';

/**
 * 将数据库行转换为 ActiveTraining 领域对象
 */
function rowToActiveTraining(row: ActiveTrainingRow): ActiveTraining {
  // status 字面量守卫: 不合法时回退 in_progress(防御性)
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

/**
 * 安全的 JSON.parse(异常隔离: 失败时返回 fallback)
 */
function safeParseJson<T>(json: string | null, fallback: T): T {
  if (!json) return fallback;
  try {
    return JSON.parse(json) as T;
  } catch (e) {
    console.warn('[ActiveTrainingStore] safeParseJson failed:', e);
    return fallback;
  }
}

/**
 * ActiveTraining 存储服务
 */
export class ActiveTrainingStore {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  /**
   * 获取指定 session 的最新训练记录(任意状态,按 id DESC 排序)
   * - 业务语义: 同一 session 可能有多个历史行(completed/aborted),返回最新一行
   * - 典型用法: 冷启动恢复当前 session 的训练状态
   *
   * @param sessionId 会话 ID
   * @returns ActiveTraining 或 null
   */
  getBySession(sessionId: string): ActiveTraining | null {
    try {
      const stmt = this.db.prepare(
        'SELECT * FROM active_training WHERE session_id = ? ORDER BY id DESC LIMIT 1',
      );
      const row = stmt.get(sessionId) as ActiveTrainingRow | undefined;
      return row ? rowToActiveTraining(row) : null;
    } catch (e) {
      console.error('[ActiveTrainingStore] getBySession failed:', e);
      return null;
    }
  }

  /**
   * 获取当前进行中的训练(status = in_progress)
   * @param sessionId 会话 ID
   * @returns ActiveTraining 或 null(无进行中训练时)
   */
  getActiveBySession(sessionId: string): ActiveTraining | null {
    try {
      const stmt = this.db.prepare(
        'SELECT * FROM active_training WHERE session_id = ? AND status = ?',
      );
      const row = stmt.get(sessionId, 'in_progress') as ActiveTrainingRow | undefined;
      return row ? rowToActiveTraining(row) : null;
    } catch (e) {
      console.error('[ActiveTrainingStore] getActiveBySession failed:', e);
      return null;
    }
  }

  /**
   * 创建活跃训练
   * - 业务语义: 同一 session 已有进行中训练时,先 abort 旧训练(状态机边界)
   * - 异常隔离: 失败时返回 null,调用方处理
   *
   * @param input 创建输入
   * @returns 创建后的 ActiveTraining
   */
  create(input: CreateActiveTrainingInput): ActiveTraining | null {
    try {
      const now = new Date().toISOString();
      // 业务规则: 同一 session 已有 in_progress 训练时,先标记为 aborted
      const existing = this.getActiveBySession(input.sessionId);
      if (existing) {
        this.update(input.sessionId, { status: 'aborted', completedAt: now });
      }

      const stmt = this.db.prepare(`
        INSERT INTO active_training (
          session_id, challenge_id, challenge_name, mode,
          current_step_index, steps_json, user_draft,
          flow_type, training_flow_json, record_id, syndrome_id,
          original_quote, constraint_text, submission_result_json,
          step_responses_json,
          status, started_at, updated_at, completed_at
        ) VALUES (
          @session_id, @challenge_id, @challenge_name, @mode,
          @current_step_index, @steps_json, @user_draft,
          @flow_type, @training_flow_json, @record_id, @syndrome_id,
          @original_quote, @constraint_text, @submission_result_json,
          @step_responses_json,
          @status, @started_at, @updated_at, @completed_at
        )
      `);

      const result = stmt.run({
        session_id: input.sessionId,
        challenge_id: input.challengeId,
        challenge_name: input.challengeName ?? null,
        mode: input.mode ?? null,
        current_step_index: 0,
        steps_json: JSON.stringify(input.steps),
        user_draft: '',
        flow_type: input.flowType ?? null,
        training_flow_json: input.trainingFlow ? JSON.stringify(input.trainingFlow) : null,
        record_id: null,
        syndrome_id: input.syndromeId ?? null,
        original_quote: input.originalQuote ?? null,
        constraint_text: input.constraint ?? null,
        submission_result_json: null,
        step_responses_json: '[]',
        status: 'in_progress',
        started_at: now,
        updated_at: now,
        completed_at: null,
      });

      // 读回完整对象
      const created = this.getById(result.lastInsertRowid as number);
      return created;
    } catch (e) {
      console.error('[ActiveTrainingStore] create failed:', e);
      return null;
    }
  }

  /**
   * 根据 ID 获取(内部用)
   */
  private getById(id: number): ActiveTraining | null {
    try {
      const stmt = this.db.prepare('SELECT * FROM active_training WHERE id = ?');
      const row = stmt.get(id) as ActiveTrainingRow | undefined;
      return row ? rowToActiveTraining(row) : null;
    } catch (e) {
      console.error('[ActiveTrainingStore] getById failed:', e);
      return null;
    }
  }

  /**
   * 更新活跃训练(部分更新)
   * @param sessionId 会话 ID
   * @param updates 部分更新字段
   * @returns 更新后的 ActiveTraining
   */
  update(sessionId: string, updates: UpdateActiveTrainingInput): ActiveTraining | null {
    try {
      const existing = this.getBySession(sessionId);
      if (!existing) {
        console.warn(`[ActiveTrainingStore] update: no record for session ${sessionId}`);
        return null;
      }

      const now = new Date().toISOString();
      const updated: ActiveTraining = {
        ...existing,
        ...updates,
        updatedAt: now,
      };

      const stmt = this.db.prepare(`
        UPDATE active_training SET
          challenge_name = @challenge_name,
          mode = @mode,
          current_step_index = @current_step_index,
          steps_json = @steps_json,
          user_draft = @user_draft,
          flow_type = @flow_type,
          training_flow_json = @training_flow_json,
          record_id = @record_id,
          syndrome_id = @syndrome_id,
          original_quote = @original_quote,
          constraint_text = @constraint_text,
          submission_result_json = @submission_result_json,
          step_responses_json = @step_responses_json,
          status = @status,
          updated_at = @updated_at,
          completed_at = @completed_at
        WHERE session_id = @session_id
      `);

      stmt.run({
        challenge_name: updated.challengeName,
        mode: updated.mode,
        current_step_index: updated.currentStepIndex,
        steps_json: JSON.stringify(updated.steps),
        user_draft: updated.userDraft,
        flow_type: updated.flowType,
        training_flow_json: updated.trainingFlow ? JSON.stringify(updated.trainingFlow) : null,
        record_id: updated.recordId,
        syndrome_id: updated.syndromeId,
        original_quote: updated.originalQuote,
        constraint_text: updated.constraint,
        submission_result_json: updated.submissionResult
          ? JSON.stringify(updated.submissionResult)
          : null,
        step_responses_json: JSON.stringify(updated.stepResponses),
        status: updated.status,
        updated_at: updated.updatedAt,
        completed_at: updated.completedAt,
        session_id: sessionId,
      });

      return updated;
    } catch (e) {
      console.error('[ActiveTrainingStore] update failed:', e);
      return null;
    }
  }

  /**
   * 删除指定 session 的活跃训练记录
   * - 业务语义: 通常不主动删除,Complete/Abort 保留行供审计
   * - 此方法供"硬重置"等特殊场景使用
   */
  delete(sessionId: string): boolean {
    try {
      const stmt = this.db.prepare('DELETE FROM active_training WHERE session_id = ?');
      const result = stmt.run(sessionId);
      return result.changes > 0;
    } catch (e) {
      console.error('[ActiveTrainingStore] delete failed:', e);
      return false;
    }
  }

  /**
   * C-4: 更新 5 步分步回答(整数组替换)
   * - 由 ActiveTrainingService.submitFlowStep() 调用
   * - 业务语义: 调用方负责合并(同 stepId 多次提交时取最新),store 只接受最终数组
   * - 异常隔离: 失败返回 null
   *
   * @param sessionId 会话 ID
   * @param stepResponses 5 步分步回答数组(已合并)
   * @returns 更新后的 ActiveTraining
   */
  updateStepResponses(
    sessionId: string,
    stepResponses: StepResponse[],
  ): ActiveTraining | null {
    return this.update(sessionId, { stepResponses });
  }

  /**
   * 获取所有进行中的训练(全局查询,供监控/调试)
   */
  listActive(): ActiveTraining[] {
    try {
      const stmt = this.db.prepare(
        'SELECT * FROM active_training WHERE status = ? ORDER BY updated_at DESC',
      );
      const rows = stmt.all('in_progress') as ActiveTrainingRow[];
      return rows.map(rowToActiveTraining);
    } catch (e) {
      console.error('[ActiveTrainingStore] listActive failed:', e);
      return [];
    }
  }

  /**
   * 按症候 ID 查询(诊断联动)
   */
  findBySyndrome(syndromeId: string): ActiveTraining[] {
    try {
      const stmt = this.db.prepare(
        'SELECT * FROM active_training WHERE syndrome_id = ? ORDER BY updated_at DESC',
      );
      const rows = stmt.all(syndromeId) as ActiveTrainingRow[];
      return rows.map(rowToActiveTraining);
    } catch (e) {
      console.error('[ActiveTrainingStore] findBySyndrome failed:', e);
      return [];
    }
  }
}
