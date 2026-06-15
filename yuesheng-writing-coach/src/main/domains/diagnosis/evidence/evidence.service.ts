import Database from 'better-sqlite3';
import { EvidenceRecord, EvidenceChain } from '../../../../shared/types/index';

interface EvidenceRow {
  evidence_id: string;
  type: string;
  level: number;
  novel_id: string;
  chapter_id: string | null;
  chapter_range: string | null;
  paragraph_index: number | null;
  sample_range: string | null;
  content_json: string;
  related_disease: string;
  related_ability: string;
  related_observations: string | null;
  extracted_by: string;
  created_at: string;
}

export class EvidenceService {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  save(evidence: EvidenceRecord): void {
    const stmt = this.db.prepare(`
      INSERT INTO evidence (evidence_id, type, level, novel_id, content_json, related_disease, related_ability, extracted_by, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    stmt.run(
      evidence.evidenceId,
      evidence.type,
      evidence.level,
      evidence.novelId,
      evidence.contentJson,
      evidence.relatedDisease,
      evidence.relatedAbility,
      evidence.extractedBy,
      evidence.createdAt,
    );
  }

  getByDisease(diseaseId: string, novelId: string, minLevel?: number): EvidenceRecord[] {
    let sql = 'SELECT * FROM evidence WHERE related_disease = ? AND novel_id = ?';
    const params: (string | number)[] = [diseaseId, novelId];
    if (minLevel !== undefined) {
      sql += ' AND level >= ?';
      params.push(minLevel);
    }
    sql += ' ORDER BY level DESC, created_at ASC';
    const rows = this.db.prepare(sql).all(...params) as EvidenceRow[];
    return rows.map(r => this.rowToRecord(r));
  }

  /**
   * 按症候 ID + 会话 ID 查询证据
   * 通过 diagnosis_evidence 关联表获取该会话中该症候的原文证据
   */
  getBySyndrome(syndromeId: string, sessionId: string): EvidenceRecord[] {
    const sql = `
      SELECT e.*
      FROM evidence e
      JOIN diagnosis_evidence de ON e.evidence_id = de.evidence_id
      JOIN diagnosis_results dr ON de.diagnosis_id = dr.id
      WHERE e.related_disease = ? AND dr.session_id = ?
      ORDER BY e.level DESC, e.created_at ASC
    `;
    const rows = this.db.prepare(sql).all(syndromeId, sessionId) as EvidenceRow[];
    return rows.map(r => this.rowToRecord(r));
  }

  getByAbility(abilityId: string, authorId: string, fromDate?: string, toDate?: string): EvidenceRecord[] {
    let sql = 'SELECT * FROM evidence WHERE related_ability = ? AND novel_id = ?';
    const params: (string | number)[] = [abilityId, authorId];
    if (fromDate) {
      sql += ' AND created_at >= ?';
      params.push(fromDate);
    }
    if (toDate) {
      sql += ' AND created_at <= ?';
      params.push(toDate);
    }
    sql += ' ORDER BY created_at ASC';
    const rows = this.db.prepare(sql).all(...params) as EvidenceRow[];
    return rows.map(r => this.rowToRecord(r));
  }

  getChainForDiagnosis(diagnosisId: string): EvidenceChain | null {
    const stmt = this.db.prepare(`
      SELECT e.*, de.relevance
      FROM evidence e
      JOIN diagnosis_evidence de ON e.evidence_id = de.evidence_id
      WHERE de.diagnosis_id = ?
    `);
    const rows = stmt.all(diagnosisId) as (EvidenceRow & { relevance: string })[];
    if (rows.length === 0) return null;

    const chain: EvidenceChain = {
      diagnosisId,
      primaryEvidence: [],
      supportingEvidence: [],
      statistics: [],
    };

    for (const row of rows) {
      const record = this.rowToRecord(row);
      if (row.level === 3) {
        chain.statistics.push(record);
      } else if (row.relevance === 'primary') {
        chain.primaryEvidence.push(record);
      } else {
        chain.supportingEvidence.push(record);
      }
    }

    return chain;
  }

  linkToDiagnosis(diagnosisId: string, evidenceId: string, relevance: 'primary' | 'supporting' | 'contextual'): void {
    this.db.prepare(`
      INSERT OR IGNORE INTO diagnosis_evidence (diagnosis_id, evidence_id, relevance)
      VALUES (?, ?, ?)
    `).run(diagnosisId, evidenceId, relevance);
  }

  getEvidenceById(evidenceId: string): EvidenceRecord | null {
    const row = this.db.prepare('SELECT * FROM evidence WHERE evidence_id = ?').get(evidenceId) as EvidenceRow | undefined;
    return row ? this.rowToRecord(row) : null;
  }

  private rowToRecord(row: EvidenceRow): EvidenceRecord {
    return {
      evidenceId: row.evidence_id,
      type: row.type as EvidenceRecord['type'],
      level: row.level as EvidenceRecord['level'],
      novelId: row.novel_id,
      contentJson: row.content_json,
      relatedDisease: row.related_disease,
      relatedAbility: row.related_ability,
      extractedBy: row.extracted_by,
      createdAt: row.created_at,
    };
  }
}
