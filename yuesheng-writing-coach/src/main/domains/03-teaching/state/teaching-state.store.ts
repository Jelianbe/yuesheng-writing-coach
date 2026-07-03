/**
 * 教学状态存储服务
 * 负责：teaching_state 表的 CRUD 操作
 * 依赖：better-sqlite3, TeachingState 类型
 * 设计原则：
 *   1. 所有数组字段在数据库中存储为 JSON 字符串
 *   2. 读取时自动解析 JSON，写入时自动序列化
 *   3. 提供事务支持确保数据一致性
 */

import type Database from 'better-sqlite3';
import { TeachingPhase, TeachingSubphase } from '../../../../shared/constants';
import type { ActiveTrainingMeta } from '../../../../shared/types/index';
import type {
  TeachingState,
  TeachingStateRow,
  CreateTeachingStateInput,
} from './teaching-state.types';

/**
 * 将数据库行转换为 TeachingState 对象
 */
function rowToState(row: TeachingStateRow): TeachingState {
  return {
    sessionId: row.session_id,
    currentPhase: row.current_phase as TeachingPhase,
    currentSubphase: (row.current_subphase ?? 'S1_PROTAGONIST') as TeachingSubphase,
    completedActions: JSON.parse(row.completed_actions),
    completedTasks: JSON.parse(row.completed_tasks),
    activeProblems: JSON.parse(row.active_problems),
    nextSuggestedActions: JSON.parse(row.next_suggested_actions),
    currentTaskId: row.current_task_id,
    diagnosisSummary: row.diagnosis_summary,
    lastUserConfirmation: row.last_user_confirmation,
    focusArea: (row.focus_area ?? null) as TeachingState['focusArea'],
    transitionOffered: row.transition_offered === 1,
    lockedSyndromes: JSON.parse(row.locked_syndromes ?? '[]'),
    // Sprint 23 G-1: 解析 ActiveTraining 业务元数据(JSON 字符串)
    activeTrainingMeta: row.active_training_meta
      ? (JSON.parse(row.active_training_meta) as ActiveTrainingMeta)
      : null,
    updatedAt: row.updated_at,
  };
}

/**
 * 将 TeachingState 对象转换为数据库行
 */
function stateToRow(state: TeachingState): Omit<TeachingStateRow, 'id'> {
  return {
    session_id: state.sessionId,
    current_phase: state.currentPhase,
    current_subphase: state.currentSubphase,
    completed_actions: JSON.stringify(state.completedActions),
    completed_tasks: JSON.stringify(state.completedTasks),
    active_problems: JSON.stringify(state.activeProblems),
    next_suggested_actions: JSON.stringify(state.nextSuggestedActions),
    current_task_id: state.currentTaskId,
    diagnosis_summary: state.diagnosisSummary,
    last_user_confirmation: state.lastUserConfirmation,
    focus_area: state.focusArea,
    transition_offered: state.transitionOffered ? 1 : 0,
    locked_syndromes: JSON.stringify(state.lockedSyndromes),
    // Sprint 23 G-1: 序列化 ActiveTraining 业务元数据
    active_training_meta: state.activeTrainingMeta
      ? JSON.stringify(state.activeTrainingMeta)
      : null,
    updated_at: state.updatedAt,
  };
}

/**
 * 教学状态存储服务
 */
export class TeachingStateStore {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  /**
   * 获取指定会话的教学状态
   * @param sessionId - 会话 ID
   * @returns 教学状态，如果不存在则返回 null
   */
  getBySession(sessionId: string): TeachingState | null {
    const stmt = this.db.prepare(
      'SELECT * FROM teaching_state WHERE session_id = ?',
    );
    const row = stmt.get(sessionId) as TeachingStateRow | undefined;
    return row ? rowToState(row) : null;
  }

  /**
   * 创建新的教学状态记录
   * @param input - 创建输入
   * @returns 创建后的教学状态
   */
  create(input: CreateTeachingStateInput): TeachingState {
    const now = new Date().toISOString();
    const state: TeachingState = {
      sessionId: input.sessionId,
      currentPhase: input.currentPhase ?? TeachingPhase.INIT,
      currentSubphase: input.currentSubphase ?? TeachingSubphase.WORLD_PROTAGONIST,
      completedActions: [],
      completedTasks: [],
      activeProblems: [],
      nextSuggestedActions: [],
      currentTaskId: null,
      diagnosisSummary: '',
      lastUserConfirmation: null,
      focusArea: null,
      transitionOffered: false,
      lockedSyndromes: [],
      updatedAt: now,
    };

    const row = stateToRow(state);

    const stmt = this.db.prepare(`
      INSERT INTO teaching_state (
        session_id, current_phase, current_subphase,
        completed_actions, completed_tasks, active_problems,
        next_suggested_actions, current_task_id, diagnosis_summary,
        last_user_confirmation, focus_area, transition_offered, locked_syndromes,
        active_training_meta, updated_at
      ) VALUES (
        @session_id, @current_phase, @current_subphase,
        @completed_actions, @completed_tasks, @active_problems,
        @next_suggested_actions, @current_task_id, @diagnosis_summary,
        @last_user_confirmation, @focus_area, @transition_offered, @locked_syndromes,
        @active_training_meta, @updated_at
      )
    `);

    stmt.run(row);
    return state;
  }

  /**
   * 更新教学状态（部分更新）
   * @param sessionId - 会话 ID
   * @param updates - 要更新的字段
   * @returns 更新后的教学状态，如果不存在则返回 null
   */
  update(
    sessionId: string,
    updates: Partial<Omit<TeachingState, 'sessionId'>>,
  ): TeachingState | null {
    const existing = this.getBySession(sessionId);
    if (!existing) {
      return null;
    }

    const now = new Date().toISOString();
    const updated = { ...existing, ...updates, updatedAt: now };

    const row = stateToRow(updated);

    const stmt = this.db.prepare(`
      UPDATE teaching_state SET
        current_phase = @current_phase,
        current_subphase = @current_subphase,
        completed_actions = @completed_actions,
        completed_tasks = @completed_tasks,
        active_problems = @active_problems,
        next_suggested_actions = @next_suggested_actions,
        current_task_id = @current_task_id,
        diagnosis_summary = @diagnosis_summary,
        last_user_confirmation = @last_user_confirmation,
        focus_area = @focus_area,
        transition_offered = @transition_offered,
        locked_syndromes = @locked_syndromes,
        active_training_meta = @active_training_meta,
        updated_at = @updated_at
      WHERE session_id = @session_id
    `);

    const result = stmt.run(row);
    if (result.changes === 0) {
      return null;
    }

    return updated;
  }

  /**
   * 用户确认完成当前阶段，推进状态
   * @param sessionId - 会话 ID
   * @param stateMachine - 状态机实例（用于计算新状态）
   * @returns 更新后的教学状态，如果不存在则返回 null
   */
  confirmAndAdvance(
    sessionId: string,
    stateMachine: { confirmPhaseComplete: (state: TeachingState) => TeachingState },
  ): TeachingState | null {
    const existing = this.getBySession(sessionId);
    if (!existing) {
      return null;
    }

    const newState = stateMachine.confirmPhaseComplete(existing);
    return this.update(sessionId, {
      currentPhase: newState.currentPhase,
      currentSubphase: newState.currentSubphase,
      completedActions: newState.completedActions,
      nextSuggestedActions: newState.nextSuggestedActions,
      lastUserConfirmation: newState.lastUserConfirmation,
    });
  }

  /**
   * 删除指定会话的教学状态
   * @param sessionId - 会话 ID
   * @returns 是否删除成功
   */
  delete(sessionId: string): boolean {
    const stmt = this.db.prepare(
      'DELETE FROM teaching_state WHERE session_id = ?',
    );
    const result = stmt.run(sessionId);
    return result.changes > 0;
  }

  /**
   * 获取或创建教学状态
   * 如果不存在则创建初始状态
   * @param sessionId - 会话 ID
   * @returns 教学状态
   */
  getOrCreate(sessionId: string): TeachingState {
    const existing = this.getBySession(sessionId);
    if (existing) {
      return existing;
    }

    return this.create({ sessionId });
  }
}
