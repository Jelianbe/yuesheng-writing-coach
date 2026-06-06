import { beforeEach, describe, expect, it, vi } from 'vitest';
import { EvidenceService } from '../evidence.service';
import type { EvidenceRecord } from '../../../renderer/shared/types';

// ---------------------------------------------------------------------------
// Mock better-sqlite3 — native module is not needed at runtime for tests
// ---------------------------------------------------------------------------
vi.mock('better-sqlite3', () => ({ default: vi.fn() }));

// ---------------------------------------------------------------------------
// Helper types matching the shape of better-sqlite3 statement / db
// ---------------------------------------------------------------------------
interface MockStmt {
  run: ReturnType<typeof vi.fn>;
  all: ReturnType<typeof vi.fn>;
  get: ReturnType<typeof vi.fn>;
}

interface MockDb {
  prepare: ReturnType<typeof vi.fn>;
  exec?: ReturnType<typeof vi.fn>;
}

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------
function createMockStmt(): MockStmt {
  return {
    run: vi.fn(),
    all: vi.fn(),
    get: vi.fn(),
  };
}

function createMockDb(): MockDb {
  return {
    prepare: vi.fn(),
    exec: vi.fn(),
  };
}

/**
 * Returns a snake_case row as it would be returned by better-sqlite3.
 * Used to simulate the raw database result that rowToRecord() maps.
 */
function createRow(overrides?: Partial<{
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
  relevance?: string;
}>): Record<string, unknown> {
  return {
    evidence_id: 'ev-001',
    type: 'text',
    level: 2,
    novel_id: 'novel-001',
    chapter_id: null,
    chapter_range: null,
    paragraph_index: null,
    sample_range: null,
    content_json: JSON.stringify({ sample: '原文片段' }),
    related_disease: 'disease-001',
    related_ability: 'ability-001',
    related_observations: null,
    extracted_by: 'parser-v1',
    created_at: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

/** Convenience: a full EvidenceRecord for save() input. */
function createRecord(overrides?: Partial<EvidenceRecord>): EvidenceRecord {
  return {
    evidenceId: 'ev-001',
    type: 'text',
    level: 2,
    novelId: 'novel-001',
    contentJson: JSON.stringify({ sample: '原文片段' }),
    relatedDisease: 'disease-001',
    relatedAbility: 'ability-001',
    extractedBy: 'parser-v1',
    createdAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe('EvidenceService', () => {
  let mockDb: MockDb;
  let mockStmt: MockStmt;
  let service: EvidenceService;

  beforeEach(() => {
    mockStmt = createMockStmt();
    mockDb = createMockDb();
    mockDb.prepare.mockReturnValue(mockStmt);
    service = new EvidenceService(mockDb as any);
  });

  // -----------------------------------------------------------------------
  // save
  // -----------------------------------------------------------------------
  describe('save', () => {
    it('插入一条证据记录到数据库中', () => {
      const evidence = createRecord();

      service.save(evidence);

      expect(mockDb.prepare).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO evidence'),
      );
      expect(mockStmt.run).toHaveBeenCalledWith(
        'ev-001',
        'text',
        2,
        'novel-001',
        JSON.stringify({ sample: '原文片段' }),
        'disease-001',
        'ability-001',
        'parser-v1',
        '2026-01-01T00:00:00.000Z',
      );
    });

    it('使用正确的 INSERT 列名', () => {
      const evidence = createRecord();
      service.save(evidence);

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('evidence_id');
      expect(sql).toContain('type');
      expect(sql).toContain('level');
      expect(sql).toContain('novel_id');
      expect(sql).toContain('content_json');
      expect(sql).toContain('related_disease');
      expect(sql).toContain('related_ability');
      expect(sql).toContain('extracted_by');
      expect(sql).toContain('created_at');
    });

    it('可以保存 type=pattern 和 level=4 的证据', () => {
      const evidence = createRecord({
        evidenceId: 'ev-999',
        type: 'pattern',
        level: 4,
      });

      service.save(evidence);

      expect(mockStmt.run).toHaveBeenCalledWith(
        'ev-999',
        'pattern',
        4,
        expect.any(String),
        expect.any(String),
        expect.any(String),
        expect.any(String),
        expect.any(String),
        expect.any(String),
      );
    });
  });

  // -----------------------------------------------------------------------
  // getByDisease
  // -----------------------------------------------------------------------
  describe('getByDisease', () => {
    it('根据疾病 ID 和作品 ID 查询证据', () => {
      const row = createRow();
      mockStmt.all.mockReturnValue([row]);

      const results = service.getByDisease('disease-001', 'novel-001');

      expect(mockDb.prepare).toHaveBeenCalledWith(
        expect.stringContaining('WHERE related_disease = ? AND novel_id = ?'),
      );
      expect(mockStmt.all).toHaveBeenCalledWith('disease-001', 'novel-001');
      expect(results).toHaveLength(1);
      expect(results[0].evidenceId).toBe('ev-001');
      expect(results[0].relatedDisease).toBe('disease-001');
      expect(results[0].novelId).toBe('novel-001');
    });

    it('当提供 minLevel 时添加 level >= 过滤', () => {
      mockStmt.all.mockReturnValue([]);

      service.getByDisease('disease-001', 'novel-001', 2);

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('AND level >= ?');
      expect(mockStmt.all).toHaveBeenCalledWith('disease-001', 'novel-001', 2);
    });

    it('当 minLevel 为 undefined 时不添加 level >= 过滤条件', () => {
      mockStmt.all.mockReturnValue([]);

      service.getByDisease('disease-001', 'novel-001', undefined);

      const sql: string = mockDb.prepare.mock.calls[0][0];
      // SQL 中只有 ORDER BY 包含 level，不应有 WHERE level >=
      expect(sql).not.toContain('AND level');
      expect(mockStmt.all).toHaveBeenCalledWith('disease-001', 'novel-001');
    });

    it('当 minLevel 为 0 时仍添加过滤（语义上返回全部）', () => {
      mockStmt.all.mockReturnValue([]);

      service.getByDisease('disease-001', 'novel-001', 0);

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('level >= ?');
    });

    it('结果按 level DESC, created_at ASC 排序', () => {
      mockStmt.all.mockReturnValue([]);

      service.getByDisease('disease-001', 'novel-001');

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('ORDER BY level DESC, created_at ASC');
    });

    it('没有匹配证据时返回空数组', () => {
      mockStmt.all.mockReturnValue([]);

      const results = service.getByDisease('unknown-disease', 'novel-001');

      expect(results).toEqual([]);
    });

    it('将数据库行正确映射为 EvidenceRecord（camelCase）', () => {
      const row = createRow({
        evidence_id: 'ev-x',
        type: 'statistical',
        level: 3,
        novel_id: 'novel-x',
        content_json: '{"count":5}',
        related_disease: 'disease-x',
        related_ability: 'ability-x',
        extracted_by: 'bot-v2',
        created_at: '2026-06-01T00:00:00.000Z',
      });
      mockStmt.all.mockReturnValue([row]);

      const [r] = service.getByDisease('disease-x', 'novel-x');

      expect(r).toEqual({
        evidenceId: 'ev-x',
        type: 'statistical',
        level: 3,
        novelId: 'novel-x',
        contentJson: '{"count":5}',
        relatedDisease: 'disease-x',
        relatedAbility: 'ability-x',
        extractedBy: 'bot-v2',
        createdAt: '2026-06-01T00:00:00.000Z',
      });
    });

    it('返回多条匹配结果', () => {
      mockStmt.all.mockReturnValue([
        createRow({ evidence_id: 'ev-1', level: 2 }),
        createRow({ evidence_id: 'ev-2', level: 1 }),
      ]);

      const results = service.getByDisease('disease-001', 'novel-001');

      expect(results).toHaveLength(2);
      expect(results[0].evidenceId).toBe('ev-1');
      expect(results[1].evidenceId).toBe('ev-2');
    });
  });

  // -----------------------------------------------------------------------
  // getByAbility
  // -----------------------------------------------------------------------
  describe('getByAbility', () => {
    it('根据能力 ID 和作者 ID 查询证据', () => {
      mockStmt.all.mockReturnValue([createRow()]);

      const results = service.getByAbility('ability-001', 'author-001');

      expect(mockDb.prepare).toHaveBeenCalledWith(
        expect.stringContaining('WHERE related_ability = ? AND novel_id = ?'),
      );
      expect(mockStmt.all).toHaveBeenCalledWith('ability-001', 'author-001');
      expect(results).toHaveLength(1);
    });

    it('当提供 fromDate 时添加 created_at >= 过滤', () => {
      mockStmt.all.mockReturnValue([]);

      service.getByAbility('ability-001', 'author-001', '2026-01-01');

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('created_at >= ?');
      expect(mockStmt.all).toHaveBeenCalledWith(
        'ability-001',
        'author-001',
        '2026-01-01',
      );
    });

    it('当提供 toDate 时添加 created_at <= 过滤', () => {
      mockStmt.all.mockReturnValue([]);

      service.getByAbility('ability-001', 'author-001', undefined, '2026-06-01');

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('created_at <= ?');
      expect(mockStmt.all).toHaveBeenCalledWith(
        'ability-001',
        'author-001',
        '2026-06-01',
      );
    });

    it('同时提供 fromDate 和 toDate 时添加两个过滤', () => {
      mockStmt.all.mockReturnValue([]);

      service.getByAbility(
        'ability-001',
        'author-001',
        '2026-01-01',
        '2026-06-01',
      );

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('created_at >= ?');
      expect(sql).toContain('created_at <= ?');
      expect(mockStmt.all).toHaveBeenCalledWith(
        'ability-001',
        'author-001',
        '2026-01-01',
        '2026-06-01',
      );
    });

    it('结果按 created_at ASC 排序', () => {
      mockStmt.all.mockReturnValue([]);

      service.getByAbility('ability-001', 'author-001');

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('ORDER BY created_at ASC');
    });

    it('没有匹配时返回空数组', () => {
      mockStmt.all.mockReturnValue([]);

      const results = service.getByAbility('unknown-ability', 'author-001');

      expect(results).toEqual([]);
    });
  });

  // -----------------------------------------------------------------------
  // getChainForDiagnosis
  // -----------------------------------------------------------------------
  describe('getChainForDiagnosis', () => {
    it('返回包含 primaryEvidence 和 supportingEvidence 的证据链', () => {
      mockStmt.all.mockReturnValue([
        createRow({
          evidence_id: 'ev-p1',
          level: 2,
          relevance: 'primary',
        }),
        createRow({
          evidence_id: 'ev-s1',
          level: 1,
          relevance: 'supporting',
        }),
      ]);

      const chain = service.getChainForDiagnosis('diag-001');

      expect(chain).not.toBeNull();
      expect(chain!.diagnosisId).toBe('diag-001');
      expect(chain!.primaryEvidence).toHaveLength(1);
      expect(chain!.primaryEvidence[0].evidenceId).toBe('ev-p1');
      expect(chain!.supportingEvidence).toHaveLength(1);
      expect(chain!.supportingEvidence[0].evidenceId).toBe('ev-s1');
      expect(chain!.statistics).toHaveLength(0);
    });

    it('将 level=3 的证据归类到 statistics', () => {
      mockStmt.all.mockReturnValue([
        createRow({
          evidence_id: 'ev-stat',
          level: 3,
          relevance: 'primary',
        }),
      ]);

      const chain = service.getChainForDiagnosis('diag-001');

      expect(chain!.statistics).toHaveLength(1);
      expect(chain!.statistics[0].evidenceId).toBe('ev-stat');
      // level=3 优先归到 statistics，不论 relevance 值
      expect(chain!.primaryEvidence).toHaveLength(0);
      expect(chain!.supportingEvidence).toHaveLength(0);
    });

    it('将 relevance=contextual 归到 supportingEvidence', () => {
      mockStmt.all.mockReturnValue([
        createRow({
          evidence_id: 'ev-ctx',
          level: 1,
          relevance: 'contextual',
        }),
      ]);

      const chain = service.getChainForDiagnosis('diag-001');

      expect(chain!.supportingEvidence).toHaveLength(1);
      expect(chain!.supportingEvidence[0].evidenceId).toBe('ev-ctx');
      expect(chain!.primaryEvidence).toHaveLength(0);
      expect(chain!.statistics).toHaveLength(0);
    });

    it('使用 JOIN 查询 evidence 和 diagnosis_evidence 表', () => {
      mockStmt.all.mockReturnValue([]);

      service.getChainForDiagnosis('diag-001');

      const sql: string = mockDb.prepare.mock.calls[0][0];
      expect(sql).toContain('FROM evidence e');
      expect(sql).toContain('JOIN diagnosis_evidence de');
      expect(sql).toContain('ON e.evidence_id = de.evidence_id');
      expect(sql).toContain('WHERE de.diagnosis_id = ?');
      expect(mockStmt.all).toHaveBeenCalledWith('diag-001');
    });

    it('没有关联证据时返回 null', () => {
      mockStmt.all.mockReturnValue([]);

      const chain = service.getChainForDiagnosis('diag-999');

      expect(chain).toBeNull();
    });
  });

  // -----------------------------------------------------------------------
  // linkToDiagnosis
  // -----------------------------------------------------------------------
  describe('linkToDiagnosis', () => {
    it('插入诊断-证据关联记录', () => {
      service.linkToDiagnosis('diag-001', 'ev-001', 'primary');

      expect(mockDb.prepare).toHaveBeenCalledWith(
        expect.stringContaining('INSERT OR IGNORE INTO diagnosis_evidence'),
      );
      expect(mockStmt.run).toHaveBeenCalledWith(
        'diag-001',
        'ev-001',
        'primary',
      );
    });

    it('支持 supporting 关联类型', () => {
      service.linkToDiagnosis('diag-001', 'ev-001', 'supporting');

      expect(mockStmt.run).toHaveBeenCalledWith(
        'diag-001',
        'ev-001',
        'supporting',
      );
    });

    it('支持 contextual 关联类型', () => {
      service.linkToDiagnosis('diag-001', 'ev-001', 'contextual');

      expect(mockStmt.run).toHaveBeenCalledWith(
        'diag-001',
        'ev-001',
        'contextual',
      );
    });
  });

  // -----------------------------------------------------------------------
  // getEvidenceById
  // -----------------------------------------------------------------------
  describe('getEvidenceById', () => {
    it('根据证据 ID 查询单条证据', () => {
      const row = createRow({ evidence_id: 'ev-001' });
      mockStmt.get.mockReturnValue(row);

      const record = service.getEvidenceById('ev-001');

      expect(mockDb.prepare).toHaveBeenCalledWith(
        expect.stringContaining('SELECT * FROM evidence WHERE evidence_id = ?'),
      );
      expect(mockStmt.get).toHaveBeenCalledWith('ev-001');
      expect(record).not.toBeNull();
      expect(record!.evidenceId).toBe('ev-001');
    });

    it('证据不存在时返回 null', () => {
      mockStmt.get.mockReturnValue(undefined);

      const record = service.getEvidenceById('non-existent');

      expect(record).toBeNull();
    });
  });

  // -----------------------------------------------------------------------
  // 错误处理
  // -----------------------------------------------------------------------
  describe('错误处理', () => {
    function expectAllMethodsThrow(setupError: () => void): void {
      // save
      setupError();
      expect(() =>
        service.save(createRecord()),
      ).toThrow('DB_ERROR');

      // getByDisease
      setupError();
      expect(() =>
        service.getByDisease('d-1', 'n-1'),
      ).toThrow('DB_ERROR');

      // getByAbility
      setupError();
      expect(() =>
        service.getByAbility('a-1', 'n-1'),
      ).toThrow('DB_ERROR');

      // getChainForDiagnosis
      setupError();
      expect(() =>
        service.getChainForDiagnosis('d-1'),
      ).toThrow('DB_ERROR');

      // linkToDiagnosis
      setupError();
      expect(() =>
        service.linkToDiagnosis('d-1', 'e-1', 'primary'),
      ).toThrow('DB_ERROR');

      // getEvidenceById
      setupError();
      expect(() =>
        service.getEvidenceById('e-1'),
      ).toThrow('DB_ERROR');
    }

    it('prepare 失败时所有方法抛出错误', () => {
      mockDb.prepare.mockImplementation(() => {
        throw new Error('DB_ERROR');
      });

      expectAllMethodsThrow(() => {
        mockDb.prepare.mockImplementation(() => {
          throw new Error('DB_ERROR');
        });
      });
    });

    it('run 失败时 save / linkToDiagnosis 抛出错误', () => {
      mockStmt.run.mockImplementation(() => {
        throw new Error('DB_ERROR');
      });

      expect(() => service.save(createRecord())).toThrow('DB_ERROR');
      expect(() =>
        service.linkToDiagnosis('d-1', 'e-1', 'primary'),
      ).toThrow('DB_ERROR');
    });

    it('all 失败时 getByDisease / getByAbility / getChainForDiagnosis 抛出错误', () => {
      mockStmt.all.mockImplementation(() => {
        throw new Error('DB_ERROR');
      });

      expect(() => service.getByDisease('d-1', 'n-1')).toThrow('DB_ERROR');
      expect(() => service.getByAbility('a-1', 'n-1')).toThrow('DB_ERROR');
      expect(() => service.getChainForDiagnosis('d-1')).toThrow('DB_ERROR');
    });

    it('get 失败时 getEvidenceById 抛出错误', () => {
      mockStmt.get.mockImplementation(() => {
        throw new Error('DB_ERROR');
      });

      expect(() => service.getEvidenceById('e-1')).toThrow('DB_ERROR');
    });
  });

  // -----------------------------------------------------------------------
  // 集成场景：多个方法组合使用
  // -----------------------------------------------------------------------
  describe('多方法集成场景', () => {
    it('保存证据后可通过 ID 查询到', () => {
      // 模拟 save 成功
      mockStmt.run.mockReturnValue(undefined);
      service.save(createRecord());

      // 模拟查询返回刚才保存的行
      const row = createRow({ evidence_id: 'ev-001' });
      mockStmt.get.mockReturnValue(row);

      const found = service.getEvidenceById('ev-001');
      expect(found).not.toBeNull();
      expect(found!.evidenceId).toBe('ev-001');
    });

    it('保存证据后可在疾病查询结果中找到', () => {
      service.save(createRecord());

      mockStmt.all.mockReturnValue([createRow()]);

      const results = service.getByDisease('disease-001', 'novel-001');
      expect(results).toHaveLength(1);
      expect(results[0].evidenceId).toBe('ev-001');
    });

    it('关联证据后可获取完整证据链', () => {
      // 先关联
      mockStmt.run.mockReturnValue(undefined);
      service.linkToDiagnosis('diag-001', 'ev-001', 'primary');

      // 再查询链
      mockStmt.all.mockReturnValue([
        createRow({
          evidence_id: 'ev-001',
          level: 2,
          relevance: 'primary' as any,
        }),
      ]);

      const chain = service.getChainForDiagnosis('diag-001');
      expect(chain).not.toBeNull();
      expect(chain!.primaryEvidence).toHaveLength(1);
      expect(chain!.primaryEvidence[0].evidenceId).toBe('ev-001');
    });
  });
});
