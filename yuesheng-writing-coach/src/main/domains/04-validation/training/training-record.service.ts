/**
 * 训练记录服务
 * 负责：user_training_records 表的 CRUD 操作
 * 依赖：better-sqlite3
 */

import type Database from 'better-sqlite3';

export interface TrainingRecord {
  id: string;
  sessionId: string;
  taskId: string;
  syndromeId: string;
  status: 'assigned' | 'completed' | 'skipped';
  assignedAt: string;
  completedAt: string | null;
  userResponse: string | null;
  aiFeedback: string | null;
  effectiveness: number | null;
  /** Evaluator Agent 评分（1-10） */
  score: number | null;
  /** 任务类型：writing | reading | reflection | technique */
  taskType: string;
}

export interface TrainingRecordRow {
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
    status: row.status as TrainingRecord['status'],
    assignedAt: row.assigned_at,
    completedAt: row.completed_at,
    userResponse: row.user_response,
    aiFeedback: row.ai_feedback,
    effectiveness: row.effectiveness,
    score: row.score,
    taskType: row.task_type,
  };
}

function recordToRow(record: Omit<TrainingRecord, 'id'> & { id?: string }): Omit<TrainingRecordRow, 'id'> & { id?: string } {
  return {
    id: record.id,
    session_id: record.sessionId,
    task_id: record.taskId,
    syndrome_id: record.syndromeId,
    status: record.status,
    assigned_at: record.assignedAt,
    completed_at: record.completedAt,
    user_response: record.userResponse,
    ai_feedback: record.aiFeedback,
    effectiveness: record.effectiveness,
    score: record.score,
    task_type: record.taskType,
  };
}

export class TrainingRecordService {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  /**
   * 分配训练任务
   */
  assign(record: Omit<TrainingRecord, 'id' | 'status' | 'assignedAt' | 'completedAt'>): TrainingRecord {
    const id = `${record.sessionId}_${record.taskId}_${Date.now()}`;
    const now = new Date().toISOString();
    const fullRecord: TrainingRecord = {
      ...record,
      id,
      status: 'assigned',
      assignedAt: now,
      completedAt: null,
    };

    const stmt = this.db.prepare(`
      INSERT INTO user_training_records
      (id, session_id, task_id, syndrome_id, status, assigned_at, completed_at, user_response, ai_feedback, effectiveness, score, task_type)
      VALUES (@id, @session_id, @task_id, @syndrome_id, @status, @assigned_at, @completed_at, @user_response, @ai_feedback, @effectiveness, @score, @task_type)
    `);
    stmt.run(recordToRow(fullRecord));
    return fullRecord;
  }

  /**
   * 标记训练完成
   */
  complete(
    id: string,
    updates: { userResponse?: string; aiFeedback?: string; effectiveness?: number; score?: number },
  ): TrainingRecord | null {
    const existing = this.getById(id);
    if (!existing) return null;

    const stmt = this.db.prepare(`
      UPDATE user_training_records
      SET status = 'completed',
          completed_at = @completed_at,
          user_response = COALESCE(@user_response, user_response),
          ai_feedback = COALESCE(@ai_feedback, ai_feedback),
          effectiveness = COALESCE(@effectiveness, effectiveness),
          score = COALESCE(@score, score)
      WHERE id = @id
    `);

    stmt.run({
      id,
      completed_at: new Date().toISOString(),
      user_response: updates.userResponse ?? null,
      ai_feedback: updates.aiFeedback ?? null,
      effectiveness: updates.effectiveness ?? null,
      score: updates.score ?? null,
    });

    return this.getById(id);
  }

  /**
   * 标记训练跳过
   */
  skip(id: string): TrainingRecord | null {
    const existing = this.getById(id);
    if (!existing) return null;

    this.db.prepare(`
      UPDATE user_training_records SET status = 'skipped', completed_at = @completed_at WHERE id = @id
    `).run({ id, completed_at: new Date().toISOString() });

    return this.getById(id);
  }

  /**
   * 按 ID 查询
   */
  getById(id: string): TrainingRecord | null {
    const row = this.db.prepare('SELECT * FROM user_training_records WHERE id = ?').get(id) as TrainingRecordRow | undefined;
    return row ? rowToRecord(row) : null;
  }

  /**
   * 按会话查询所有记录
   */
  getBySession(sessionId: string): TrainingRecord[] {
    const rows = this.db.prepare(
      'SELECT * FROM user_training_records WHERE session_id = ? ORDER BY assigned_at ASC',
    ).all(sessionId) as TrainingRecordRow[];
    return rows.map(rowToRecord);
  }

  /**
   * 查询所有会话的训练记录（跨会话聚合）
   */
  getAll(): TrainingRecord[] {
    const rows = this.db.prepare(
      'SELECT * FROM user_training_records ORDER BY assigned_at ASC',
    ).all() as TrainingRecordRow[];
    return rows.map(rowToRecord);
  }

  /** 删除会话的所有记录 */
  deleteBySession(sessionId: string): void {
    this.db.prepare('DELETE FROM user_training_records WHERE session_id = ?').run(sessionId);
  }
}
