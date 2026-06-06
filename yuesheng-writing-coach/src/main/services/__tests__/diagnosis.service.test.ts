import Database from 'better-sqlite3';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { DiagnosisService } from '../diagnosis.service';
import { SyndromeId, ActionId } from '../../../shared/constants';
import { SeverityLevel, DiagnosisEntry } from '../../../renderer/shared/types';

function createMockDiagnosis(overrides?: Partial<DiagnosisEntry>): DiagnosisEntry {
  return {
    sessionId: 'test-session',
    messageId: 'test-msg',
    syndromes: [
      {
        id: SyndromeId.WorldviewBloat,
        name: '世界观膨胀',
        severity: 'L2' as SeverityLevel,
        evidence: ['设定过多'],
        suggestedActions: [ActionId.NarrowScope],
      },
    ],
    suggestedActions: [ActionId.NarrowScope],
    confidence: 0.85,
    timestamp: new Date().toISOString(),
    nextFocus: undefined,
    ...overrides,
  };
}

describe('DiagnosisService', () => {
  let db: Database.Database;
  let service: DiagnosisService;

  beforeAll(() => {
    db = new Database(':memory:');
    db.exec(`
      CREATE TABLE IF NOT EXISTS diagnosis_results (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        syndromes TEXT NOT NULL,
        suggested_actions TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 0,
        timestamp TEXT NOT NULL,
        next_focus TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    `);
    service = new DiagnosisService(db);
  });

  beforeEach(() => {
    db.exec('DELETE FROM diagnosis_results');
  });

  it('保存诊断结果到数据库', () => {
    const diagnosis = createMockDiagnosis();
    service.save(diagnosis);

    const results = service.getBySession('test-session');
    expect(results).toHaveLength(1);
    expect(results[0].sessionId).toBe('test-session');
    expect(results[0].syndromes).toHaveLength(1);
    expect(results[0].syndromes[0].id).toBe(SyndromeId.WorldviewBloat);
  });

  it('保存 P009 角色动机缺失的诊断结果', () => {
    const diagnosis = createMockDiagnosis({
      syndromes: [
        {
          id: SyndromeId.MotivationDeficit,
          name: '角色动机缺失',
          severity: 'L2' as SeverityLevel,
          evidence: ['角色行为缺乏内在驱动力'],
          suggestedActions: [ActionId.ReturnToProtagonist],
        },
      ],
      suggestedActions: [ActionId.StageSplit, ActionId.ReturnToProtagonist],
    });

    service.save(diagnosis);

    const results = service.getBySession('test-session');
    expect(results).toHaveLength(1);
    expect(results[0].syndromes).toHaveLength(1);
    expect(results[0].syndromes[0].id).toBe(SyndromeId.MotivationDeficit);
  });

  it('按会话查询诊断结果', () => {
    service.save(createMockDiagnosis({ sessionId: 'session-a', messageId: 'msg-1' }));
    service.save(createMockDiagnosis({ sessionId: 'session-a', messageId: 'msg-2' }));
    service.save(createMockDiagnosis({ sessionId: 'session-b', messageId: 'msg-3' }));

    const results = service.getBySession('session-a');
    expect(results).toHaveLength(2);

    const resultsB = service.getBySession('session-b');
    expect(resultsB).toHaveLength(1);
  });

  it('获取最近 N 条诊断结果', () => {
    for (let i = 0; i < 10; i++) {
      service.save(createMockDiagnosis({ sessionId: 'test-session', messageId: `msg-${i}` }));
    }

    const recent = service.getRecentBySession('test-session', 3);
    expect(recent).toHaveLength(3);
  });

  it('按会话删除诊断结果', () => {
    service.save(createMockDiagnosis({ sessionId: 'session-a', messageId: 'msg-1' }));
    service.save(createMockDiagnosis({ sessionId: 'session-a', messageId: 'msg-2' }));
    service.save(createMockDiagnosis({ sessionId: 'session-b', messageId: 'msg-3' }));

    service.deleteBySession('session-a');

    expect(service.getBySession('session-a')).toHaveLength(0);
    expect(service.getBySession('session-b')).toHaveLength(1);
  });

  it('JSON 序列化/反序列化正确', () => {
    const diagnosis = createMockDiagnosis({
      syndromes: [
        {
          id: SyndromeId.OCPlanarization,
          name: 'OC平面化',
          severity: 'L2' as SeverityLevel,
          evidence: ['性格从头到尾没变', '标签化描述'],
          score: 5,
          suggestedActions: [ActionId.ContrastShow, ActionId.FlipPerspective],
        },
      ],
      suggestedActions: [ActionId.ContrastShow, ActionId.FlipPerspective],
      confidence: 0.92,
      nextFocus: SyndromeId.CharacterTool,
    });

    service.save(diagnosis);

    const results = service.getBySession('test-session');
    expect(results).toHaveLength(1);
    expect(results[0].syndromes[0].evidence).toEqual(['性格从头到尾没变', '标签化描述']);
    expect(results[0].syndromes[0].score).toBe(5);
    expect(results[0].suggestedActions).toContain(ActionId.ContrastShow);
    expect(results[0].suggestedActions).toContain(ActionId.FlipPerspective);
    expect(results[0].nextFocus).toBe(SyndromeId.CharacterTool);
    expect(results[0].confidence).toBe(0.92);
  });
});
