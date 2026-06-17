import crypto from 'node:crypto';
import Database from 'better-sqlite3';
import { DiagnosisEntry, SyndromeResult, ActionId, SyndromeId, DiagnosisAnalysis, TeachingProgress } from '../../../shared/types/index';

export interface DiagnosisRow {
  id: string;
  session_id: string;
  message_id: string;
  syndromes: string;
  suggested_actions: string;
  confidence: number;
  timestamp: string;
  next_focus: string | null;
  created_at: string;
  root_cause_analysis: string | null;
  teaching_progress: string | null;
}

export class DiagnosisService {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  save(diagnosis: DiagnosisEntry): string {
    const id = `diag_${crypto.randomUUID()}`;
    const safeMessageId = diagnosis.messageId || 'unknown';
    // RWR-P0-1: 教学进度可选,旧诊断条目无此字段,NULL 入库保持向后兼容
    const teachingProgressJson = diagnosis.teachingProgress
      ? JSON.stringify(diagnosis.teachingProgress)
      : null;
    const stmt = this.db.prepare(`
      INSERT INTO diagnosis_results (
        id, session_id, message_id, syndromes, suggested_actions,
        confidence, timestamp, next_focus, teaching_progress
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      id,
      diagnosis.sessionId,
      safeMessageId,
      JSON.stringify(diagnosis.syndromes),
      JSON.stringify(diagnosis.suggestedActions),
      diagnosis.confidence,
      diagnosis.timestamp,
      diagnosis.nextFocus ?? null,
      teachingProgressJson,
    );
    return id;
  }

  /** 保存 Diagnosis Agent 的结构化分析结果（按主键 id 更新） */
  saveAnalysis(analysis: DiagnosisAnalysis, id: string): void {
    const stmt = this.db.prepare(`
      UPDATE diagnosis_results
      SET root_cause_analysis = ?
      WHERE id = ?
    `);
    stmt.run(JSON.stringify(analysis), id);
  }

  /** 获取最近的分析结果 */
  getLatestAnalysis(sessionId: string): DiagnosisAnalysis | null {
    const row = this.db.prepare(`
      SELECT root_cause_analysis FROM diagnosis_results
      WHERE session_id = ? AND root_cause_analysis IS NOT NULL
      ORDER BY timestamp DESC LIMIT 1
    `).get(sessionId) as { root_cause_analysis: string } | undefined;
    if (!row) return null;
    return JSON.parse(row.root_cause_analysis);
  }

  getBySession(sessionId: string): DiagnosisEntry[] {
    const rows = this.db.prepare(
      'SELECT * FROM diagnosis_results WHERE session_id = ? ORDER BY timestamp ASC',
    ).all(sessionId) as DiagnosisRow[];

    return rows.map(row => this.rowToEntry(row));
  }

  /** 获取所有会话的诊断结果（跨会话聚合） */
  getAll(): DiagnosisEntry[] {
    const rows = this.db.prepare(
      'SELECT * FROM diagnosis_results ORDER BY timestamp ASC',
    ).all() as DiagnosisRow[];
    return rows.map(row => this.rowToEntry(row));
  }

  getRecentBySession(sessionId: string, limit = 5): DiagnosisEntry[] {
    const rows = this.db.prepare(
      'SELECT * FROM diagnosis_results WHERE session_id = ? ORDER BY timestamp DESC LIMIT ?',
    ).all(sessionId, limit) as DiagnosisRow[];

    return rows.map(row => this.rowToEntry(row)).reverse();
  }

  deleteBySession(sessionId: string): void {
    this.db.prepare('DELETE FROM diagnosis_results WHERE session_id = ?').run(sessionId);
  }

  private rowToEntry(row: DiagnosisRow): DiagnosisEntry {
    const syndromes = JSON.parse(row.syndromes) as SyndromeResult[];
    const suggestedActions = JSON.parse(row.suggested_actions) as ActionId[];
    // RWR-P0-1: 教学进度从 JSON 字符串解析,NULL 保持 undefined 兼容性
    const teachingProgress = row.teaching_progress
      ? (JSON.parse(row.teaching_progress) as TeachingProgress)
      : undefined;

    return {
      sessionId: row.session_id,
      messageId: row.message_id,
      syndromes,
      suggestedActions,
      confidence: row.confidence,
      timestamp: row.timestamp,
      nextFocus: (row.next_focus as SyndromeId) ?? undefined,
      teachingProgress,
    };
  }
}
