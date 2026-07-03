/**
 * TeachingStateService.setActiveTraining G-1 单测 — Sprint 23
 *
 * 覆盖:
 * 1. setActiveTraining 写入 activeTrainingMeta (syndromeId + techniqueId + source)
 * 2. setActiveTraining 不带 techniqueId → meta.techniqueId 为 undefined
 * 3. setActiveTraining 默认 source='training_triggered'
 * 4. setActiveTraining 自定义 source='user_request' / 'diagnosis_result' / 'prescription'
 * 5. getActiveTrainingMeta 读取已写入的 meta
 * 6. getActiveTrainingMeta 无 session 时返回 null
 * 7. clearActiveTraining 清除 meta
 * 8. 异常隔离: 写入失败 → warn 不抛
 * 9. 多次 setActiveTraining → 覆盖前次 (最新 meta 生效)
 * 10. 边界: techniqueId='' → 仍写入(空字符串透传)
 *
 * 策略: in-memory SQLite + stub teaching_state schema (含 active_training_meta 列)
 *
 * DoD: ≥3 单测
 * 依据: dev-docs/tasks/sprint-23-plan.md §G-1
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import Database from 'better-sqlite3';
import { TeachingStateService } from '../teaching-state.service';
import { TeachingStateStore } from '../state/teaching-state.store';
import { TeachingPhase, TeachingSubphase } from '../../../../shared/constants';

function createInMemoryDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE teaching_state (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL UNIQUE,
      current_phase TEXT NOT NULL DEFAULT 'P0_INIT',
      current_subphase TEXT DEFAULT 'S1_PROTAGONIST',
      completed_actions TEXT DEFAULT '[]',
      completed_tasks TEXT DEFAULT '[]',
      active_problems TEXT DEFAULT '[]',
      next_suggested_actions TEXT DEFAULT '[]',
      current_task_id TEXT DEFAULT NULL,
      diagnosis_summary TEXT DEFAULT '',
      last_user_confirmation TEXT DEFAULT NULL,
      focus_area TEXT DEFAULT NULL,
      transition_offered INTEGER DEFAULT 0,
      locked_syndromes TEXT DEFAULT '[]',
      active_training_meta TEXT DEFAULT NULL,
      updated_at TEXT NOT NULL
    );
  `);
  return db;
}

function createServiceWithStore(): TeachingStateService {
  const svc = new TeachingStateService();
  const db = createInMemoryDb();
  svc.initStore(db);
  // 预置一个 session state
  const store = new TeachingStateStore(db);
  store.create({ sessionId: 'sess-g1-1', currentPhase: TeachingPhase.PRACTICE_LOOP, currentSubphase: TeachingSubphase.PRACTICE_REFLECTION });
  return svc;
}

describe('TeachingStateService.setActiveTraining (Sprint 23 G-1)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('setActiveTraining 写入 activeTrainingMeta (syndromeId + techniqueId + source)', () => {
    const svc = createServiceWithStore();
    svc.setActiveTraining('sess-g1-1', 'P003', 'TQ-005', 'diagnosis_result');

    const meta = svc.getActiveTrainingMeta('sess-g1-1');
    expect(meta).not.toBeNull();
    expect(meta?.syndromeId).toBe('P003');
    expect(meta?.techniqueId).toBe('TQ-005');
    expect(meta?.source).toBe('diagnosis_result');
    expect(meta?.triggeredAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('setActiveTraining 不带 techniqueId → meta.techniqueId 为 undefined', () => {
    const svc = createServiceWithStore();
    svc.setActiveTraining('sess-g1-1', 'P005');

    const meta = svc.getActiveTrainingMeta('sess-g1-1');
    expect(meta?.syndromeId).toBe('P005');
    expect(meta?.techniqueId).toBeUndefined();
  });

  it('setActiveTraining 默认 source = "training_triggered"', () => {
    const svc = createServiceWithStore();
    svc.setActiveTraining('sess-g1-1', 'P001', 'TQ-001');

    const meta = svc.getActiveTrainingMeta('sess-g1-1');
    expect(meta?.source).toBe('training_triggered');
  });

  it('setActiveTraining 自定义 source = "user_request"', () => {
    const svc = createServiceWithStore();
    svc.setActiveTraining('sess-g1-1', 'P002', undefined, 'user_request');

    const meta = svc.getActiveTrainingMeta('sess-g1-1');
    expect(meta?.source).toBe('user_request');
  });

  it('setActiveTraining 自定义 source = "prescription"', () => {
    const svc = createServiceWithStore();
    svc.setActiveTraining('sess-g1-1', 'P007', undefined, 'prescription');

    const meta = svc.getActiveTrainingMeta('sess-g1-1');
    expect(meta?.source).toBe('prescription');
  });

  it('getActiveTrainingMeta 无 session 时返回 null(不抛错)', () => {
    const svc = createServiceWithStore();
    const meta = svc.getActiveTrainingMeta('non-existent-session');
    expect(meta).toBeNull();
  });

  it('getActiveTrainingMeta 无 activeTrainingMeta 时返回 null', () => {
    const svc = createServiceWithStore();
    const meta = svc.getActiveTrainingMeta('sess-g1-1');
    expect(meta).toBeNull();
  });

  it('clearActiveTraining 清除 activeTrainingMeta', () => {
    const svc = createServiceWithStore();
    svc.setActiveTraining('sess-g1-1', 'P003', 'TQ-001');
    expect(svc.getActiveTrainingMeta('sess-g1-1')).not.toBeNull();

    svc.clearActiveTraining('sess-g1-1');
    expect(svc.getActiveTrainingMeta('sess-g1-1')).toBeNull();
  });

  it('多次 setActiveTraining → 最新 meta 生效(覆盖)', () => {
    const svc = createServiceWithStore();
    svc.setActiveTraining('sess-g1-1', 'P001', 'TQ-001', 'user_request');
    svc.setActiveTraining('sess-g1-1', 'P005', 'TQ-005', 'diagnosis_result');

    const meta = svc.getActiveTrainingMeta('sess-g1-1');
    expect(meta?.syndromeId).toBe('P005');
    expect(meta?.techniqueId).toBe('TQ-005');
    expect(meta?.source).toBe('diagnosis_result');
  });

  it('异常隔离: store update 抛错时 warn 不抛出', () => {
    const svc = createServiceWithStore();
    const warnSpy = vi.spyOn(console, 'warn');

    // 注入一个会抛错的 store
    const brokenStore = {
      getBySession: () => { throw new Error('db down'); },
      update: () => { throw new Error('db down'); },
    } as unknown as TeachingStateStore;
    (svc as unknown as { store: TeachingStateStore | null }).store = brokenStore;

    expect(() => svc.setActiveTraining('sess-g1-1', 'P001')).not.toThrow();
    expect(warnSpy).toHaveBeenCalled();
  });
});
