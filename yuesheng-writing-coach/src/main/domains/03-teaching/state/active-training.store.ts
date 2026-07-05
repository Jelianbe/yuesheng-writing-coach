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
  DraftSnapshot,
  DraftSnapshotRow,
  CreateDraftSnapshotInput,
  AuditLog,
  AuditLogRow,
  CreateAuditLogInput,
} from './active-training.types';
import {
  isValidActiveTrainingStatus,
  isValidDraftSnapshotTrigger,
  isValidAuditLogTrigger,
  isValidAuditActor,
} from './active-training.types';

/** 草稿内容字符上限(与 active_training.user_draft 一致) */
const DRAFT_MAX_LENGTH = 50000;

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
 * 将数据库行转换为 DraftSnapshot 领域对象
 */
function rowToDraftSnapshot(row: DraftSnapshotRow): DraftSnapshot {
  const trigger = isValidDraftSnapshotTrigger(row.trigger) ? row.trigger : 'advance';
  return {
    id: row.id,
    activeTrainingId: row.active_training_id,
    stepIndex: row.step_index,
    content: row.content,
    trigger,
    snapshotAt: row.snapshot_at,
    restoredFromId: row.restored_from_id,
  };
}

/**
 * 将数据库行转换为 AuditLog 领域对象
 */
function rowToAuditLog(row: AuditLogRow): AuditLog {
  const trigger = isValidAuditLogTrigger(row.trigger) ? row.trigger : 'start';
  const actor = isValidAuditActor(row.actor) ? row.actor : 'main';
  return {
    id: row.id,
    activeTrainingId: row.active_training_id,
    trigger,
    fromState: row.from_state,
    toState: row.to_state,
    actor,
    contextJson: row.context_json,
    occurredAt: row.occurred_at,
  };
}

/**
 * 截断超长草稿并记录警告
 */
function truncateDraft(content: string): string {
  if (content.length <= DRAFT_MAX_LENGTH) return content;
  console.warn(
    `[ActiveTrainingStore] draft exceeds ${DRAFT_MAX_LENGTH} chars, truncating from ${content.length}`,
  );
  return content.slice(0, DRAFT_MAX_LENGTH);
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

  // ─── 草稿快照(C-1) ───

  /**
   * 创建草稿快照
   * - 自动截断超过 50K 的内容并 warn
   * - 失败返回 null(异常隔离)
   */
  createDraftSnapshot(input: CreateDraftSnapshotInput): DraftSnapshot | null {
    try {
      const content = truncateDraft(input.content);
      const stmt = this.db.prepare(`
        INSERT INTO active_training_drafts (
          active_training_id, step_index, content, trigger, snapshot_at, restored_from_id
        ) VALUES (
          @active_training_id, @step_index, @content, @trigger, @snapshot_at, @restored_from_id
        )
      `);
      const now = new Date().toISOString();
      const result = stmt.run({
        active_training_id: input.activeTrainingId,
        step_index: input.stepIndex,
        content,
        trigger: input.trigger,
        snapshot_at: now,
        restored_from_id: input.restoredFromId ?? null,
      });
      return this.getDraftSnapshotById(result.lastInsertRowid as number);
    } catch (e) {
      console.error('[ActiveTrainingStore] createDraftSnapshot failed:', e);
      return null;
    }
  }

  /**
   * 根据 ID 获取草稿快照
   */
  getDraftSnapshotById(id: number): DraftSnapshot | null {
    try {
      const stmt = this.db.prepare('SELECT * FROM active_training_drafts WHERE id = ?');
      const row = stmt.get(id) as DraftSnapshotRow | undefined;
      return row ? rowToDraftSnapshot(row) : null;
    } catch (e) {
      console.error('[ActiveTrainingStore] getDraftSnapshotById failed:', e);
      return null;
    }
  }

  /**
   * 获取指定活跃训练的所有快照(按时间倒序,最近优先)
   */
  getDraftSnapshotsByTrainingId(activeTrainingId: number): DraftSnapshot[] {
    try {
      const stmt = this.db.prepare(
        'SELECT * FROM active_training_drafts WHERE active_training_id = ? ORDER BY snapshot_at DESC, id DESC',
      );
      const rows = stmt.all(activeTrainingId) as DraftSnapshotRow[];
      return rows.map(rowToDraftSnapshot);
    } catch (e) {
      console.error('[ActiveTrainingStore] getDraftSnapshotsByTrainingId failed:', e);
      return [];
    }
  }

  /**
   * 回退到指定快照
   * - 读取快照 content 更新 active_training.user_draft
   * - 同时创建一条 trigger='restore' 的新快照记录
   * - 失败返回 null(异常隔离)
   */
  restoreDraftSnapshot(activeTrainingId: number, snapshotId: number): ActiveTraining | null {
    try {
      const snapshot = this.getDraftSnapshotById(snapshotId);
      if (!snapshot) {
        console.warn(`[ActiveTrainingStore] restoreDraftSnapshot: snapshot ${snapshotId} not found`);
        return null;
      }
      if (snapshot.activeTrainingId !== activeTrainingId) {
        console.warn(
          `[ActiveTrainingStore] restoreDraftSnapshot: snapshot ${snapshotId} does not belong to training ${activeTrainingId}`,
        );
        return null;
      }

      const training = this.getById(activeTrainingId);
      if (!training) {
        console.warn(
          `[ActiveTrainingStore] restoreDraftSnapshot: training ${activeTrainingId} not found`,
        );
        return null;
      }

      const updated = this.update(training.sessionId, { userDraft: snapshot.content });
      if (!updated) return null;

      this.createDraftSnapshot({
        activeTrainingId,
        stepIndex: updated.currentStepIndex,
        content: snapshot.content,
        trigger: 'restore',
        restoredFromId: snapshotId,
      });

      return updated;
    } catch (e) {
      console.error('[ActiveTrainingStore] restoreDraftSnapshot failed:', e);
      return null;
    }
  }

  // ─── C-2: 审计日志操作 ───

  /**
   * 创建审计日志
   * - 与草稿快照不同:审计错误自然抛出(不静默),调用方决定是否阻断状态转换
   * - context_json 截断至 2KB(避免 payload 膨胀)
   * - 返回创建的 AuditLog
   */
  createAuditLog(input: CreateAuditLogInput): AuditLog {
    const contextJson =
      input.contextJson && input.contextJson.length > 2048
        ? input.contextJson.slice(0, 2048)
        : input.contextJson;

    const stmt = this.db.prepare(`
      INSERT INTO active_training_audit_log (
        active_training_id, trigger, from_state, to_state, actor, context_json, occurred_at
      ) VALUES (
        @active_training_id, @trigger, @from_state, @to_state, @actor, @context_json, @occurred_at
      )
    `);
    const now = new Date().toISOString();
    const result = stmt.run({
      active_training_id: input.activeTrainingId,
      trigger: input.trigger,
      from_state: input.fromState ?? null,
      to_state: input.toState,
      actor: input.actor,
      context_json: contextJson,
      occurred_at: now,
    });
    return this.getAuditLogById(result.lastInsertRowid as number);
  }

  /**
   * 根据 ID 获取审计日志
   */
  getAuditLogById(id: number): AuditLog {
    const stmt = this.db.prepare('SELECT * FROM active_training_audit_log WHERE id = ?');
    const row = stmt.get(id) as AuditLogRow | undefined;
    if (!row) throw new Error(`AuditLog ${id} not found`);
    return rowToAuditLog(row);
  }

  /**
   * 获取指定训练的所有审计日志(按时间倒序)
   */
  getAuditLogsByTrainingId(activeTrainingId: number): AuditLog[] {
    try {
      const stmt = this.db.prepare(
        'SELECT * FROM active_training_audit_log WHERE active_training_id = ? ORDER BY occurred_at DESC, id DESC',
      );
      const rows = stmt.all(activeTrainingId) as AuditLogRow[];
      return rows.map(rowToAuditLog);
    } catch (e) {
      console.error('[ActiveTrainingStore] getAuditLogsByTrainingId failed:', e);
      return [];
    }
  }

  /**
   * 按 session 维度获取最近 N 条审计日志
   */
  getRecentTransitions(sessionId: string, limit: number = 10): AuditLog[] {
    try {
      const stmt = this.db.prepare(`
        SELECT al.* FROM active_training_audit_log al
        INNER JOIN active_training at ON at.id = al.active_training_id
        WHERE at.session_id = ?
        ORDER BY al.occurred_at DESC, al.id DESC
        LIMIT ?
      `);
      const rows = stmt.all(sessionId, limit) as AuditLogRow[];
      return rows.map(rowToAuditLog);
    } catch (e) {
      console.error('[ActiveTrainingStore] getRecentTransitions failed:', e);
      return [];
    }
  }
}
