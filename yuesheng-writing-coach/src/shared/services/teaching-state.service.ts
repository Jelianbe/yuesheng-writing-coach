/**
 * TeachingStateService — Sprint 26 跨端版
 *
 * 双端共用,接 StorageAdapter:
 * - Electron 端: 用 BetterSqliteAdapter(走主进程,经 IPC)
 * - Android 端: 用 CapacitorSqliteAdapter(走 WebView 直接调用)
 *
 * 关键差异(对比 main/domains/03-teaching/state/teaching-state.store.ts):
 * - 同步 → 异步
 * - `better-sqlite3.Database` → `StorageAdapter`
 * - 直接 prepare/run/get 改为 `adapter.query()` / `adapter.execute()`
 * - 行→TeachingState 投影集中到 service 层(JSON 字段自动 parse/stringify)
 *
 * 范围:
 * - 本文件仅做 teaching_state 表的 CRUD
 * - 状态机逻辑(confirmPhase / downgradeSeverity / 状态转换)仍在主进程 teaching-state.service.ts 中
 * - T26-2.3 暂不强制主进程切换,新 service 供 Android 端使用
 *
 * 依据: dev-docs/tasks/sprint-26-2-3-plan.md
 * 决策: D-074
 */
import type { StorageAdapter } from '../storage/storage-adapter';
import type { DatabaseRow } from '../storage/storage-types';
import { TeachingPhase, TeachingSubphase } from '../constants';
import type { ActiveTrainingMeta, TeachingState } from '../types/types-teaching';

/** 数据库行格式(snake_case,JSON 字段为字符串) */
export interface TeachingStateRow extends DatabaseRow {
  id: string;
  session_id: string;
  current_phase: string;
  current_subphase: string | null;
  completed_actions: string;
  completed_tasks: string;
  active_problems: string;
  next_suggested_actions: string;
  current_task_id: string | null;
  diagnosis_summary: string;
  last_user_confirmation: string | null;
  focus_area: string | null;
  transition_offered: number;
  locked_syndromes: string;
  active_training_meta: string | null;
  updated_at: string;
}

/** 创建输入 */
export interface CreateTeachingStateInput {
  sessionId: string;
  currentPhase?: TeachingPhase;
  currentSubphase?: TeachingSubphase;
}

/**
 * 解析 JSON 字段(空字符串/缺失视作 '[]')
 * 防御性:主进程早期数据可能存 NULL 或空字符串,统一降级为默认值
 */
function parseJsonArray(raw: string | null | undefined, fallback: unknown[] = []): unknown[] {
  if (!raw) return fallback;
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : fallback;
  } catch {
    return fallback;
  }
}

function parseJsonObject<T>(raw: string | null | undefined): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function rowToState(row: TeachingStateRow): TeachingState {
  return {
    sessionId: row.session_id,
    currentPhase: row.current_phase as TeachingPhase,
    currentSubphase: (row.current_subphase ?? TeachingSubphase.WORLD_PROTAGONIST) as TeachingSubphase,
    completedActions: parseJsonArray(row.completed_actions) as TeachingState['completedActions'],
    completedTasks: parseJsonArray(row.completed_tasks) as string[],
    activeProblems: parseJsonArray(row.active_problems) as TeachingState['activeProblems'],
    nextSuggestedActions: parseJsonArray(row.next_suggested_actions) as TeachingState['nextSuggestedActions'],
    currentTaskId: row.current_task_id,
    diagnosisSummary: row.diagnosis_summary,
    lastUserConfirmation: row.last_user_confirmation,
    focusArea: (row.focus_area ?? null) as TeachingState['focusArea'],
    transitionOffered: row.transition_offered === 1,
    lockedSyndromes: parseJsonArray(row.locked_syndromes) as string[],
    activeTrainingMeta: parseJsonObject<ActiveTrainingMeta>(row.active_training_meta),
    updatedAt: row.updated_at,
  };
}

function stateToRow(state: TeachingState): Omit<TeachingStateRow, 'id'> {
  return {
    session_id: state.sessionId,
    current_phase: state.currentPhase,
    current_subphase: state.currentSubphase,
    completed_actions: JSON.stringify(state.completedActions ?? []),
    completed_tasks: JSON.stringify(state.completedTasks ?? []),
    active_problems: JSON.stringify(state.activeProblems ?? []),
    next_suggested_actions: JSON.stringify(state.nextSuggestedActions ?? []),
    current_task_id: state.currentTaskId,
    diagnosis_summary: state.diagnosisSummary,
    last_user_confirmation: state.lastUserConfirmation,
    focus_area: state.focusArea,
    transition_offered: state.transitionOffered ? 1 : 0,
    locked_syndromes: JSON.stringify(state.lockedSyndromes ?? []),
    active_training_meta: state.activeTrainingMeta
      ? JSON.stringify(state.activeTrainingMeta)
      : null,
    updated_at: state.updatedAt,
  };
}

export class TeachingStateService {
  constructor(private readonly adapter: StorageAdapter) {}

  async getBySession(sessionId: string): Promise<TeachingState | null> {
    const row = await this.adapter.queryOne<TeachingStateRow>(
      'SELECT * FROM teaching_state WHERE session_id = ?',
      [sessionId],
    );
    return row ? rowToState(row) : null;
  }

  async create(input: CreateTeachingStateInput): Promise<TeachingState> {
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
      activeTrainingMeta: null,
      updatedAt: now,
    };

    const id = this.generateUUID();
    const row = stateToRow(state);
    await this.adapter.execute(
      `INSERT INTO teaching_state (
        id, session_id, current_phase, current_subphase,
        completed_actions, completed_tasks, active_problems,
        next_suggested_actions, current_task_id, diagnosis_summary,
        last_user_confirmation, focus_area, transition_offered, locked_syndromes,
        active_training_meta, updated_at
      ) VALUES (
        ?, ?, ?, ?,
        ?, ?, ?,
        ?, ?, ?,
        ?, ?, ?, ?,
        ?, ?
      )`,
      [
        id,
        row.session_id,
        row.current_phase,
        row.current_subphase,
        row.completed_actions,
        row.completed_tasks,
        row.active_problems,
        row.next_suggested_actions,
        row.current_task_id,
        row.diagnosis_summary,
        row.last_user_confirmation,
        row.focus_area,
        row.transition_offered,
        row.locked_syndromes,
        row.active_training_meta,
        row.updated_at,
      ] as Array<string | number | null>,
    );
    return state;
  }

  async update(
    sessionId: string,
    updates: Partial<Omit<TeachingState, 'sessionId'>>,
  ): Promise<TeachingState | null> {
    const existing = await this.getBySession(sessionId);
    if (!existing) return null;

    const now = new Date().toISOString();
    const updated: TeachingState = { ...existing, ...updates, updatedAt: now };
    const row = stateToRow(updated);

    const result = await this.adapter.execute(
      `UPDATE teaching_state SET
        current_phase = ?,
        current_subphase = ?,
        completed_actions = ?,
        completed_tasks = ?,
        active_problems = ?,
        next_suggested_actions = ?,
        current_task_id = ?,
        diagnosis_summary = ?,
        last_user_confirmation = ?,
        focus_area = ?,
        transition_offered = ?,
        locked_syndromes = ?,
        active_training_meta = ?,
        updated_at = ?
      WHERE session_id = ?`,
      [
        row.current_phase,
        row.current_subphase,
        row.completed_actions,
        row.completed_tasks,
        row.active_problems,
        row.next_suggested_actions,
        row.current_task_id,
        row.diagnosis_summary,
        row.last_user_confirmation,
        row.focus_area,
        row.transition_offered,
        row.locked_syndromes,
        row.active_training_meta,
        row.updated_at,
        row.session_id,
      ] as Array<string | number | null>,
    );
    if (result.changes === 0) return null;
    return updated;
  }

  async getOrCreate(sessionId: string): Promise<TeachingState> {
    const existing = await this.getBySession(sessionId);
    if (existing) return existing;
    return this.create({ sessionId });
  }

  async delete(sessionId: string): Promise<boolean> {
    const result = await this.adapter.execute(
      'DELETE FROM teaching_state WHERE session_id = ?',
      [sessionId],
    );
    return result.changes > 0;
  }

  private generateUUID(): string {
    return globalThis.crypto.randomUUID();
  }
}
