/**
 * TrainingRecordService — Sprint 26 跨端版
 *
 * 双端共用,接 StorageAdapter:
 * - Electron 端: 用 BetterSqliteAdapter(走主进程,经 IPC)
 * - Android 端: 用 CapacitorSqliteAdapter(走 WebView 直接调用)
 *
 * 关键差异(对比 main/domains/04-validation/training/training-record.service.ts):
 * - 同步 → 异步
 * - `better-sqlite3.Database` → `StorageAdapter`
 * - 直接 prepare/run/get 改为 `adapter.query()` / `adapter.execute()`
 * - 行→TrainingRecord 投影集中到 service 层
 *
 * 范围:
 * - 本文件仅做 user_training_records 表的 CRUD
 * - 业务流程逻辑(assign/complete/skip)以方法形式暴露,主进程旧 service 仍可继续工作
 * - T26-2.4 暂不强制主进程切换,新 service 供 Android 端使用
 *
 * 依据: dev-docs/tasks/sprint-26-2-4-plan.md
 * 决策: D-074
 */
import type { StorageAdapter } from '../storage/storage-adapter';
import type { DatabaseRow } from '../storage/storage-types';

export type TrainingStatus = 'assigned' | 'completed' | 'skipped';
export type TaskType = 'writing' | 'reading' | 'reflection' | 'technique';

export interface TrainingRecord {
  id: string;
  sessionId: string;
  taskId: string;
  syndromeId: string;
  status: TrainingStatus;
  assignedAt: string;
  completedAt: string | null;
  userResponse: string | null;
  aiFeedback: string | null;
  effectiveness: number | null;
  score: number | null;
  taskType: TaskType;
}

/** assign() 输入:不含 id/status/assignedAt/completedAt */
export type AssignTrainingRecordInput = Omit<
  TrainingRecord,
  'id' | 'status' | 'assignedAt' | 'completedAt'
>;

/** complete() 输入:可部分更新 */
export interface CompleteTrainingRecordInput {
  userResponse?: string;
  aiFeedback?: string;
  effectiveness?: number;
  score?: number;
}

/** 数据库行格式(snake_case) */
export interface TrainingRecordRow extends DatabaseRow {
  id: string;
  session_id: string;
  task_id: string;
  syndrome_id: string;
  status: string;
  assigned_at: string;
  completed_at: string | null;
  user_response: string | null;
  ai_feedback: string | null;
  effectiveness: number | null;
  score: number | null;
  task_type: string;
}

function rowToRecord(row: TrainingRecordRow): TrainingRecord {
  return {
    id: row.id,
    sessionId: row.session_id,
    taskId: row.task_id,
    syndromeId: row.syndrome_id,
    status: row.status as TrainingStatus,
    assignedAt: row.assigned_at,
    completedAt: row.completed_at,
    userResponse: row.user_response,
    aiFeedback: row.ai_feedback,
    effectiveness: row.effectiveness,
    score: row.score,
    taskType: row.task_type as TaskType,
  };
}

export class TrainingRecordService {
  constructor(private readonly adapter: StorageAdapter) {}

  /**
   * 分配训练任务
   * - 生成 ID 规则: `${sessionId}_${taskId}_${Date.now()}`(沿用主进程原逻辑)
   * - 状态:assigned,完成时间:null
   */
  async assign(input: AssignTrainingRecordInput): Promise<TrainingRecord> {
    const id = `${input.sessionId}_${input.taskId}_${Date.now()}`;
    const now = new Date().toISOString();
    const record: TrainingRecord = {
      ...input,
      id,
      status: 'assigned',
      assignedAt: now,
      completedAt: null,
    };

    await this.adapter.execute(
      `INSERT INTO user_training_records (
        id, session_id, task_id, syndrome_id, status, assigned_at,
        completed_at, user_response, ai_feedback, effectiveness, score, task_type
      ) VALUES (
        ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?
      )`,
      [
        record.id,
        record.sessionId,
        record.taskId,
        record.syndromeId,
        record.status,
        record.assignedAt,
        record.completedAt,
        record.userResponse,
        record.aiFeedback,
        record.effectiveness,
        record.score,
        record.taskType,
      ],
    );
    return record;
  }

  /**
   * 标记训练完成
   * - status → 'completed'
   * - completed_at → 当前时间
   * - 其他字段(COALESCE 语义):传 null 表示保留旧值
   */
  async complete(
    id: string,
    updates: CompleteTrainingRecordInput,
  ): Promise<TrainingRecord | null> {
    const existing = await this.getById(id);
    if (!existing) return null;

    await this.adapter.execute(
      `UPDATE user_training_records SET
        status = 'completed',
        completed_at = ?,
        user_response = COALESCE(?, user_response),
        ai_feedback = COALESCE(?, ai_feedback),
        effectiveness = COALESCE(?, effectiveness),
        score = COALESCE(?, score)
      WHERE id = ?`,
      [
        new Date().toISOString(),
        updates.userResponse ?? null,
        updates.aiFeedback ?? null,
        updates.effectiveness ?? null,
        updates.score ?? null,
        id,
      ],
    );
    return this.getById(id);
  }

  /**
   * 标记训练跳过
   */
  async skip(id: string): Promise<TrainingRecord | null> {
    const existing = await this.getById(id);
    if (!existing) return null;

    await this.adapter.execute(
      `UPDATE user_training_records
        SET status = 'skipped', completed_at = ?
        WHERE id = ?`,
      [new Date().toISOString(), id],
    );
    return this.getById(id);
  }

  /** 按 ID 查询 */
  async getById(id: string): Promise<TrainingRecord | null> {
    const row = await this.adapter.queryOne<TrainingRecordRow>(
      'SELECT * FROM user_training_records WHERE id = ?',
      [id],
    );
    return row ? rowToRecord(row) : null;
  }

  /** 按会话查询所有记录(按 assigned_at 升序) */
  async getBySession(sessionId: string): Promise<TrainingRecord[]> {
    const rows = await this.adapter.query<TrainingRecordRow>(
      'SELECT * FROM user_training_records WHERE session_id = ? ORDER BY assigned_at ASC',
      [sessionId],
    );
    return rows.map(rowToRecord);
  }

  /** 跨会话查询所有记录 */
  async getAll(): Promise<TrainingRecord[]> {
    const rows = await this.adapter.query<TrainingRecordRow>(
      'SELECT * FROM user_training_records ORDER BY assigned_at ASC',
    );
    return rows.map(rowToRecord);
  }

  /** 按会话删除所有记录,返回删除行数 */
  async deleteBySession(sessionId: string): Promise<number> {
    const result = await this.adapter.execute(
      'DELETE FROM user_training_records WHERE session_id = ?',
      [sessionId],
    );
    return result.changes;
  }
}
