/**
 * 学生模型持久化层 — teaching_history + attitude_preference 的 SQLite CRUD
 *
 * 从 student-model-service.ts 拆分，RWR-P3-2 时提取为独立 RowManager。
 * 约束：
 *   - R-021 隐性诊断:teaching_history 系统内部,前端 UI 永不渲染
 *   - R-020 循环依赖:本模块不引用 diagnosis-processor / dispute-tracker
 *   - 本模块是"工具",C-3 训练反馈回路时再触发写入
 */

import * as crypto from 'node:crypto';
import type Database from 'better-sqlite3';
import type {
  AttitudePreferenceLevel,
  TeachingHistoryEntry,
} from '../../../../shared/types/types-teaching';

/** teachingHistory 单 session 最大条数(C-1 决策:防止无界增长的安全网) */
const MAX_TEACHING_HISTORY = 200;

/**
 * 学生模型持久化器
 * 职责：student_model 表的 CRUD，包括 teaching_history 和 attitude_preference
 */
export class StudentModelPersister {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  /**
   * 保证 student_model 行存在;返回行 id
   * 用法:写入前必须先 ensure,避免 INSERT 时撞已存在行(SQLite 写串行)
   */
  ensureSessionRow(sessionId: string): string {
    const existing = this.db
      .prepare(
        'SELECT id FROM student_model WHERE session_id = ? ORDER BY created_at ASC LIMIT 1',
      )
      .get(sessionId) as { id: string } | undefined;
    if (existing) return existing.id;
    const id = `sm_${crypto.randomUUID()}`;
    this.db
      .prepare(
        `INSERT INTO student_model
          (id, session_id, attitude_preference, teaching_history, created_at, updated_at)
        VALUES (?, ?, NULL, '[]', unixepoch(), unixepoch())`,
      )
      .run(id, sessionId);
    return id;
  }

  /**
   * 追加一条教学历史
   * 入参不含 timestamp(内部填 Date.now())
   * 触发方:C-3 训练反馈回路 / 诊断完成回调
   */
  appendTeachingHistory(
    sessionId: string,
    entry: Omit<TeachingHistoryEntry, 'timestamp'>,
  ): void {
    this.ensureSessionRow(sessionId);
    const row = this.db
      .prepare(
        'SELECT teaching_history FROM student_model WHERE session_id = ? ORDER BY created_at ASC LIMIT 1',
      )
      .get(sessionId) as { teaching_history: string } | undefined;
    if (!row) return;
    const list: TeachingHistoryEntry[] = JSON.parse(row.teaching_history);
    list.push({ ...entry, timestamp: Date.now() });
    // FIFO 截断 200 条
    const trimmed =
      list.length > MAX_TEACHING_HISTORY
        ? list.slice(-MAX_TEACHING_HISTORY)
        : list;
    this.db
      .prepare(
        `UPDATE student_model
          SET teaching_history = ?, updated_at = unixepoch()
        WHERE session_id = ?`,
      )
      .run(JSON.stringify(trimmed), sessionId);
  }

  /**
   * 写用户态度档位(当前 session)
   * 触发方:config 变更监听 / 用户手动选择
   */
  setAttitudePreference(
    sessionId: string,
    level: AttitudePreferenceLevel,
  ): void {
    this.ensureSessionRow(sessionId);
    this.db
      .prepare(
        `UPDATE student_model
          SET attitude_preference = ?, updated_at = unixepoch()
        WHERE session_id = ?`,
      )
      .run(level, sessionId);
  }

  /**
   * 读态度档位
   * 不传参 = 跨 session 取最近一条非空(用户上次选的)
   * 传参 = 限定该 session
   */
  getAttitudePreference(
    sessionId?: string,
  ): AttitudePreferenceLevel | null {
    if (sessionId) {
      const row = this.db
        .prepare(
          `SELECT attitude_preference FROM student_model
          WHERE session_id = ? AND attitude_preference IS NOT NULL
          ORDER BY updated_at DESC LIMIT 1`,
        )
        .get(sessionId) as { attitude_preference: string | null } | undefined;
      return (row?.attitude_preference as AttitudePreferenceLevel) ?? null;
    }
    // 跨 session:最近一条非空
    const row = this.db
      .prepare(
        `SELECT attitude_preference FROM student_model
        WHERE attitude_preference IS NOT NULL
        ORDER BY updated_at DESC LIMIT 1`,
      )
      .get() as { attitude_preference: string | null } | undefined;
    return (row?.attitude_preference as AttitudePreferenceLevel) ?? null;
  }
}
