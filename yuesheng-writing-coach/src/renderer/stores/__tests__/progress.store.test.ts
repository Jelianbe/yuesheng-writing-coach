// @vitest-environment jsdom
/**
 * progress.store 单测(RWR-P0-2)
 *
 * 覆盖:7 actions + 3 选择器 + persist partialize 行为
 * 环境:jsdom(与同目录 training.store.test.ts 一致)
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  useProgressStore,
  selectCurrentProgress,
  selectProgressMap,
  selectResolvedRatio,
} from '../progress.store';
import type { SessionProgress } from '../../shared/types';

// ===== 工具 =====

/** 构造一个最小可用的 SessionProgress(便于测试) */
function makeProgress(overrides: Partial<SessionProgress> = {}): SessionProgress {
  return {
    sessionId: 's1',
    currentIssue: 'P001',
    totalIssues: 2,
    resolvedIssues: 0,
    stage: 'P2_PRACTICE_LOOP',
    phaseGroup: 'batch-1',
    issues: [
      { syndromeId: 'P001', status: 'identified', label: '视角混乱' },
      { syndromeId: 'P002', status: 'identified', label: '情绪标签化' },
    ],
    displayStatus: 'idle',
    updatedAt: '2026-06-17T00:00:00.000Z',
    ...overrides,
  };
}

/** 重置 store 状态(localStorage 仍可能残留) */
function resetStore() {
  useProgressStore.setState({
    currentProgress: null,
    progressMap: {},
    isLoading: false,
    error: null,
  });
  // 清理 localStorage(避免跨测试污染)
  try {
    localStorage.removeItem('yuesheng-progress');
  } catch {
    /* ignore */
  }
}

// ===== 测试套件 =====

describe('ProgressStore', () => {
  beforeEach(() => {
    resetStore();
  });

  // ----- 基础状态 -----

  describe('初始状态', () => {
    it('应为空 currentProgress / progressMap', () => {
      const state = useProgressStore.getState();
      expect(state.currentProgress).toBeNull();
      expect(state.progressMap).toEqual({});
      expect(state.isLoading).toBe(false);
      expect(state.error).toBeNull();
    });
  });

  // ----- setProgress -----

  describe('setProgress', () => {
    it('应初始化 progressMap 并同步 currentProgress', () => {
      const progress = makeProgress({ sessionId: 's-A' });
      useProgressStore.getState().setProgress(progress);

      const state = useProgressStore.getState();
      expect(state.progressMap['s-A']).toMatchObject({
        sessionId: 's-A',
        totalIssues: 2,
      });
      expect(state.currentProgress?.sessionId).toBe('s-A');
    });

    it('应刷新 updatedAt 时间戳', () => {
      const old = makeProgress({ updatedAt: '2000-01-01T00:00:00.000Z' });
      useProgressStore.getState().setProgress(old);
      const updated = useProgressStore.getState().progressMap['s1'].updatedAt;
      expect(updated).not.toBe('2000-01-01T00:00:00.000Z');
      // ISO 8601 格式校验
      expect(new Date(updated).toString()).not.toBe('Invalid Date');
    });
  });

  // ----- updateResolved -----

  describe('updateResolved', () => {
    it('应将分子 +1 并把对应 issue 状态置为 mastered', () => {
      useProgressStore.getState().setProgress(makeProgress());
      useProgressStore.getState().updateResolved('s1', 'P001');

      const p = useProgressStore.getState().progressMap['s1'];
      expect(p.resolvedIssues).toBe(1);
      expect(p.issues[0].status).toBe('mastered');
      expect(p.issues[1].status).toBe('identified');
    });

    it('对不存在的 sessionId 应安全 no-op', () => {
      useProgressStore.getState().updateResolved('non-exist', 'P001');
      expect(useProgressStore.getState().progressMap['non-exist']).toBeUndefined();
    });
  });

  // ----- markCompleted -----

  describe('markCompleted', () => {
    it('应将 displayStatus 置为 completed', () => {
      useProgressStore.getState().setProgress(
        makeProgress({ displayStatus: 'teaching' })
      );
      useProgressStore.getState().markCompleted('s1');
      const p = useProgressStore.getState().progressMap['s1'];
      expect(p.displayStatus).toBe('completed');
    });
  });

  // ----- resetProgress -----

  describe('resetProgress', () => {
    it('应将分子清零并 displayStatus 回到 idle(issues 保留)', () => {
      useProgressStore.getState().setProgress(
        makeProgress({
          resolvedIssues: 2,
          issues: [
            { syndromeId: 'P001', status: 'mastered', label: '视角混乱' },
            { syndromeId: 'P002', status: 'mastered', label: '情绪标签化' },
          ],
          displayStatus: 'completed',
        })
      );
      useProgressStore.getState().resetProgress('s1');
      const p = useProgressStore.getState().progressMap['s1'];
      expect(p.resolvedIssues).toBe(0);
      expect(p.displayStatus).toBe('idle');
      // issues 数组应保留(历史分析需要)
      expect(p.issues).toHaveLength(2);
    });
  });

  // ----- appendIssues -----

  describe('appendIssues', () => {
    it('应追加新问题并累加 totalIssues', () => {
      useProgressStore.getState().setProgress(makeProgress({ totalIssues: 2 }));
      useProgressStore.getState().appendIssues('s1', [
        { syndromeId: 'P003', label: '节奏拖沓' },
      ]);
      const p = useProgressStore.getState().progressMap['s1'];
      expect(p.totalIssues).toBe(3);
      expect(p.issues).toHaveLength(3);
      expect(p.issues[2].status).toBe('identified');
    });

    it('应自动去重:已存在的 syndromeId 不会重复添加', () => {
      useProgressStore.getState().setProgress(makeProgress());
      useProgressStore.getState().appendIssues('s1', [
        { syndromeId: 'P001', label: '视角混乱(重复)' },
        { syndromeId: 'P004', label: '新问题' },
      ]);
      const p = useProgressStore.getState().progressMap['s1'];
      expect(p.totalIssues).toBe(3); // 2 + 1(去重)
      expect(p.issues[0].label).toBe('视角混乱'); // 保留原值
      expect(p.issues[2].syndromeId).toBe('P004');
    });

    it('跨 BATCH_SIZE=5 边界应切换 phaseGroup', () => {
      // 当前 2 + 新增 4 = 6,跨过 5 应进入 batch-2
      useProgressStore.getState().setProgress(makeProgress({ totalIssues: 2 }));
      useProgressStore.getState().appendIssues('s1', [
        { syndromeId: 'P003', label: 'a' },
        { syndromeId: 'P004', label: 'b' },
        { syndromeId: 'P005', label: 'c' },
        { syndromeId: 'P006', label: 'd' },
      ]);
      const p = useProgressStore.getState().progressMap['s1'];
      expect(p.totalIssues).toBe(6);
      expect(p.phaseGroup).toBe('batch-2');
    });

    it('对不存在的 sessionId 应安全 no-op', () => {
      useProgressStore.getState().appendIssues('non-exist', [
        { syndromeId: 'P999', label: 'x' },
      ]);
      expect(useProgressStore.getState().progressMap['non-exist']).toBeUndefined();
    });
  });

  // ----- markRelapsed -----

  describe('markRelapsed', () => {
    it('应将对应 issue 状态置为 relapsed', () => {
      useProgressStore.getState().setProgress(makeProgress());
      useProgressStore.getState().markRelapsed('s1', 'P001');
      const p = useProgressStore.getState().progressMap['s1'];
      expect(p.issues[0].status).toBe('relapsed');
      expect(p.issues[1].status).toBe('identified');
    });
  });

  // ----- setDisplayStatus -----

  describe('setDisplayStatus', () => {
    it('应更新 displayStatus', () => {
      useProgressStore.getState().setProgress(makeProgress());
      useProgressStore.getState().setDisplayStatus('s1', 'teaching');
      expect(useProgressStore.getState().progressMap['s1'].displayStatus).toBe(
        'teaching'
      );
    });
  });

  // ----- setCurrentProgress -----

  describe('setCurrentProgress', () => {
    it('应从 progressMap 同步 currentProgress', () => {
      useProgressStore.getState().setProgress(makeProgress({ sessionId: 's-X' }));
      // 切换到另一会话
      useProgressStore.getState().setCurrentProgress('non-exist');
      expect(useProgressStore.getState().currentProgress).toBeNull();

      useProgressStore.getState().setCurrentProgress('s-X');
      expect(useProgressStore.getState().currentProgress?.sessionId).toBe('s-X');
    });
  });

  // ----- 选择器 -----

  describe('selectors', () => {
    it('selectCurrentProgress 应返回当前会话进度', () => {
      useProgressStore.getState().setProgress(makeProgress());
      const state = useProgressStore.getState();
      expect(selectCurrentProgress(state)?.sessionId).toBe('s1');
    });

    it('selectProgressMap 应返回完整 map', () => {
      useProgressStore.getState().setProgress(makeProgress({ sessionId: 's-A' }));
      useProgressStore.getState().setProgress(
        makeProgress({ sessionId: 's-B', totalIssues: 5 })
      );
      const state = useProgressStore.getState();
      expect(Object.keys(selectProgressMap(state))).toEqual(
        expect.arrayContaining(['s-A', 's-B'])
      );
    });

    it('selectResolvedRatio 应返回分子分母及比值', () => {
      useProgressStore.getState().setProgress(
        makeProgress({ totalIssues: 4, resolvedIssues: 1 })
      );
      const state = useProgressStore.getState();
      const ratio = selectResolvedRatio('s1')(state);
      expect(ratio).toEqual({ resolved: 1, total: 4, ratio: 0.25 });
    });

    it('selectResolvedRatio 对不存在 sessionId 返回全 0', () => {
      const state = useProgressStore.getState();
      expect(selectResolvedRatio('non-exist')(state)).toEqual({
        resolved: 0,
        total: 0,
        ratio: 0,
      });
    });

    it('selectResolvedRatio 对 totalIssues=0 返回 ratio=0(避免除零)', () => {
      useProgressStore.getState().setProgress(
        makeProgress({ totalIssues: 0, resolvedIssues: 0, issues: [] })
      );
      const state = useProgressStore.getState();
      const ratio = selectResolvedRatio('s1')(state);
      expect(ratio.ratio).toBe(0);
    });
  });

  // ----- persist 行为 -----

  describe('persist middleware', () => {
    it('应将 progressMap 持久化到 localStorage', () => {
      useProgressStore.getState().setProgress(makeProgress());
      const raw = localStorage.getItem('yuesheng-progress');
      expect(raw).not.toBeNull();
      // 上面已守卫非空,这里安全解析
      if (raw === null) throw new Error('localStorage 读取失败');
      const parsed = JSON.parse(raw) as { state: { progressMap: Record<string, SessionProgress> } };
      expect(parsed.state.progressMap['s1']).toMatchObject({
        sessionId: 's1',
        totalIssues: 2,
      });
    });

    it('不应持久化 currentProgress / isLoading / error(partialize 行为)', () => {
      useProgressStore.getState().setProgress(makeProgress());
      const raw = localStorage.getItem('yuesheng-progress');
      if (raw === null) throw new Error('localStorage 读取失败');
      const parsed = JSON.parse(raw) as { state: Record<string, unknown> };
      // partialize 只保留 progressMap
      expect(parsed.state).not.toHaveProperty('currentProgress');
      expect(parsed.state).not.toHaveProperty('isLoading');
      expect(parsed.state).not.toHaveProperty('error');
    });
  });
});
