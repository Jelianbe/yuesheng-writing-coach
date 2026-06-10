import { describe, it, expect } from 'vitest';
import { SyndromeId, ActionId, TeachingPhase, TeachingSubphase } from '../../../shared/constants';
import { TeachingState } from '../../../renderer/shared/types';
import { mergeSyndromesIntoState } from '../diagnosis.handler';
import { buildDiagnosisEntry } from '../../services/__tests__/test-factories';

function makeBaseState(overrides?: Partial<TeachingState>): TeachingState {
  const defaults: TeachingState = {
    sessionId: 'test-session-001',
    currentPhase: TeachingPhase.PRACTICE_LOOP,
    currentSubphase: TeachingSubphase.PRACTICE_IDENTIFY,
    activeProblems: [],
    completedActions: [],
    completedTasks: [],
    currentTaskId: null,
    lastUserConfirmation: null,
    nextSuggestedActions: [],
    diagnosisSummary: '',
    focusArea: null,
    transitionOffered: false,
    lockedSyndromes: [],
    updatedAt: new Date().toISOString(),
  };
  return { ...defaults, ...overrides };
}

describe('mergeSyndromesIntoState - TeachingState 合并逻辑', () => {
  describe('新增病症', () => {
    it('空状态时添加第一个病症', () => {
      const state = makeBaseState({ activeProblems: [] });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L2',
            evidence: ['设定过大'],
            suggestedActions: [ActionId.NarrowScope],
          },
        ],
        suggestedActions: [ActionId.NarrowScope],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.activeProblems).toBeDefined();

      expect(result.activeProblems![0].id).toBe(SyndromeId.WorldviewBloat);
      expect(result.activeProblems![0].severity).toBe('L2');
      expect(result.activeProblems![0].status).toBe('active');
      expect(result.activeProblems![0].firstDetected).toBeDefined();
      expect(result.nextSuggestedActions).toContain(ActionId.NarrowScope);
    });

    it('已有病症列表时追加新病症', () => {
      const state = makeBaseState({
        activeProblems: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L2',
            evidence: ['设定过大'],
            firstDetected: '2026-05-01T00:00:00.000Z',
            status: 'active',
            detectionCount: 1,
            missedCount: 0,
            suggestedActions: [ActionId.NarrowScope],
          },
        ],
      });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          {
            id: SyndromeId.CharacterTool,
            name: '人物工具化',
            severity: 'L1',
            evidence: ['角色扁平'],
            suggestedActions: [ActionId.ReturnToProtagonist],
          },
        ],
        suggestedActions: [ActionId.ReturnToProtagonist],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.activeProblems).toBeDefined();

      expect(result.activeProblems![0].id).toBe(SyndromeId.WorldviewBloat);
      expect(result.activeProblems![1].id).toBe(SyndromeId.CharacterTool);
      expect(result.nextSuggestedActions).toHaveLength(1);
    });

    it('严重度降低的病症状态变为 improving', () => {
      const state = makeBaseState({
        activeProblems: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L3',
            evidence: [],
            firstDetected: '2026-05-01T00:00:00.000Z',
            status: 'active',
            detectionCount: 1,
            missedCount: 0,
            suggestedActions: [],
          },
        ],
      });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L2',
            evidence: [],
            suggestedActions: [],
          },
        ],
        suggestedActions: [],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.activeProblems).toBeDefined();

      expect(result.activeProblems![0].severity).toBe('L2');
      expect(result.activeProblems![0].status).toBe('improving');
    });
  });

  describe('更新已有病症', () => {
    it('严重度不变的已有病症保持 active 状态', () => {
      const state = makeBaseState({
        activeProblems: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L2',
            evidence: ['旧证据'],
            firstDetected: '2026-05-01T00:00:00.000Z',
            status: 'active',
            detectionCount: 1,
            missedCount: 0,
            suggestedActions: [ActionId.NarrowScope],
          },
        ],
      });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L2',
            evidence: ['新证据'],
            suggestedActions: [ActionId.NarrowScope, ActionId.GroundInReality],
          },
        ],
        suggestedActions: [ActionId.NarrowScope, ActionId.GroundInReality],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.activeProblems).toBeDefined();

      expect(result.activeProblems![0].severity).toBe('L2');
      expect(result.activeProblems![0].evidence).toEqual(['新证据']);
      expect(result.activeProblems![0].status).toBe('active');
    });

    it('严重度降低的病症状态变为 improving', () => {
      const state = makeBaseState({
        activeProblems: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L3',
            evidence: [],
            firstDetected: '2026-05-01T00:00:00.000Z',
            status: 'active',
            detectionCount: 1,
            missedCount: 0,
            suggestedActions: [],
          },
        ],
      });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L2',
            evidence: [],
            suggestedActions: [],
          },
        ],
        suggestedActions: [],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.activeProblems).toBeDefined();

      expect(result.activeProblems![0].severity).toBe('L2');
      expect(result.activeProblems![0].status).toBe('improving');
    });
  });

  describe('多病症并发诊断', () => {
    it('3个病症同时识别的完整合并', () => {
      const state = makeBaseState({ activeProblems: [] });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          {
            id: SyndromeId.WorldviewBloat,
            name: '世界观膨胀',
            severity: 'L3',
            evidence: ['世界观过大', '人物过多'],
            suggestedActions: [ActionId.NarrowScope],
          },
          {
            id: SyndromeId.CharacterTool,
            name: '人物工具化',
            severity: 'L2',
            evidence: ['角色扁平'],
            suggestedActions: [ActionId.ReturnToProtagonist],
          },
          {
            id: SyndromeId.InfoDumping,
            name: '信息倾泻',
            severity: 'L2',
            evidence: ['开篇大段设定'],
            suggestedActions: [ActionId.GroundInReality],
          },
        ],
        suggestedActions: [ActionId.NarrowScope, ActionId.ReturnToProtagonist, ActionId.GroundInReality],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.activeProblems).toBeDefined();

      expect(result.activeProblems!.map((p) => p.id)).toEqual([
        SyndromeId.WorldviewBloat,
        SyndromeId.CharacterTool,
        SyndromeId.InfoDumping,
      ]);
      expect(result.activeProblems![0].status).toBe('active');
      expect(result.activeProblems!.every((p) => p.firstDetected)).toBe(true);
    });
  });

  describe('动作去重', () => {
    it('suggestedActions 合并后自动去重', () => {
      const state = makeBaseState({
        activeProblems: [],
        nextSuggestedActions: [ActionId.NarrowScope, ActionId.StageSplit],
      });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [],
        suggestedActions: [ActionId.NarrowScope, ActionId.ReturnToProtagonist],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);

      expect(result.nextSuggestedActions).toHaveLength(3);
      expect(result.nextSuggestedActions).toContain(ActionId.NarrowScope);
      expect(result.nextSuggestedActions).toContain(ActionId.StageSplit);
      expect(result.nextSuggestedActions).toContain(ActionId.ReturnToProtagonist);
    });
  });

  describe('lockedSyndromes 合并', () => {
    it('新诊断自动锁定', () => {
      const state = makeBaseState({ lockedSyndromes: [] });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          { id: SyndromeId.WorldviewBloat, name: '世界观膨胀', severity: 'L2', evidence: [], suggestedActions: [] },
        ],
        suggestedActions: [],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.lockedSyndromes).toEqual([SyndromeId.WorldviewBloat]);
    });

    it('已有锁定与新诊断合并去重', () => {
      const state = makeBaseState({ lockedSyndromes: [SyndromeId.WorldviewBloat] });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          { id: SyndromeId.WorldviewBloat, name: '世界观膨胀', severity: 'L2', evidence: [], suggestedActions: [] },
          { id: SyndromeId.CharacterTool, name: '人物工具化', severity: 'L1', evidence: [], suggestedActions: [] },
        ],
        suggestedActions: [],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.lockedSyndromes).toHaveLength(2);
      expect(result.lockedSyndromes).toContain(SyndromeId.WorldviewBloat);
      expect(result.lockedSyndromes).toContain(SyndromeId.CharacterTool);
    });

    it('无新诊断时保留现有锁定', () => {
      const state = makeBaseState({ lockedSyndromes: [SyndromeId.WorldviewBloat, SyndromeId.CharacterTool] });
      const diagnosis = buildDiagnosisEntry({ syndromes: [], suggestedActions: [] });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.lockedSyndromes).toEqual([SyndromeId.WorldviewBloat, SyndromeId.CharacterTool]);
    });

    it('空锁定接受新诊断', () => {
      const state = makeBaseState({ lockedSyndromes: undefined as unknown as [] });
      const diagnosis = buildDiagnosisEntry({
        syndromes: [
          { id: SyndromeId.InfoDumping, name: '信息倾泻', severity: 'L2', evidence: [], suggestedActions: [] },
        ],
        suggestedActions: [],
      });

      const result = mergeSyndromesIntoState(state, diagnosis);
      expect(result.lockedSyndromes).toEqual([SyndromeId.InfoDumping]);
    });
  });
});
