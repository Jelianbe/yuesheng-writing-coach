/**
 * CenterPanel selectors 引用稳定性测试（T17-7）
 *
 * 目的：验证 selector 在 store 数据未变化时返回相同引用，
 * 防止不必要 re-render。训练流 stream 高频更新场景下，
 * useTrainingWorkshopState() 不应误触发父组件 re-render。
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import {
  useCenterSessionId,
  useCenterSessionList,
  useTrainingWorkshopState,
  useBridgeState,
  useRetroState,
} from '../selectors';
import { useSessionStore } from '../../../../stores/session.store';
import { useTrainingStore } from '../../../../stores/training.store';
import { act } from 'react';

describe('CenterPanel selectors (T17-7)', () => {
  beforeEach(() => {
    // 重置 store 到初始状态
    useSessionStore.setState({ sessions: [], currentSessionId: null });
    useTrainingStore.setState({
      errorCards: [],
      recommendations: [],
      activeTraining: null,
      isLoading: false,
      bridgeRecommendation: null,
      retroSummary: null,
      retroLoading: false,
    } as never);
  });

  describe('useCenterSessionId', () => {
    it('返回当前会话 ID', () => {
      const { result } = renderHook(() => useCenterSessionId());
      expect(result.current).toBeNull();
    });

    it('store 变化时返回新值', () => {
      const { result } = renderHook(() => useCenterSessionId());
      act(() => {
        useSessionStore.setState({ currentSessionId: 'sess-1' });
      });
      expect(result.current).toBe('sess-1');
    });
  });

  describe('useCenterSessionList', () => {
    it('初始为空数组', () => {
      const { result } = renderHook(() => useCenterSessionList());
      expect(result.current).toEqual([]);
    });

    it('引用稳定：相同 store 状态时返回相同引用', () => {
      const { result, rerender } = renderHook(() => useCenterSessionList());
      const ref1 = result.current;
      rerender();
      expect(result.current).toBe(ref1);
    });
  });

  describe('useTrainingWorkshopState', () => {
    it('返回训练工坊 props（12 字段）', () => {
      const { result } = renderHook(() => useTrainingWorkshopState());
      expect(result.current).toHaveProperty('errorCards');
      expect(result.current).toHaveProperty('recommendations');
      expect(result.current).toHaveProperty('activeTraining');
      expect(result.current).toHaveProperty('isLoading');
    });

    it('useShallow: 无关字段变化时返回相同引用', () => {
      const { result, rerender } = renderHook(() => useTrainingWorkshopState());
      const ref1 = result.current;
      // 触发无关字段变化（centerMode 变化不影响 trainingState）
      act(() => {
        useTrainingStore.setState({ centerMode: 'training' } as never);
      });
      rerender();
      expect(result.current).toBe(ref1);
    });

    it('训练流 stream 字段变化时返回新对象', () => {
      const { result, rerender } = renderHook(() => useTrainingWorkshopState());
      const ref1 = result.current;
      act(() => {
        useTrainingStore.setState({ isLoading: true } as never);
      });
      rerender();
      expect(result.current).not.toBe(ref1);
      expect(result.current.isLoading).toBe(true);
    });
  });

  describe('useBridgeState', () => {
    it('初始为 null', () => {
      const { result } = renderHook(() => useBridgeState());
      expect(result.current).toBeNull();
    });

    it('引用稳定', () => {
      const { result, rerender } = renderHook(() => useBridgeState());
      const ref1 = result.current;
      rerender();
      expect(result.current).toBe(ref1);
    });
  });

  describe('useRetroState', () => {
    it('初始 retroSummary 为 null', () => {
      const { result } = renderHook(() => useRetroState());
      expect(result.current.retroSummary).toBeNull();
      expect(result.current.retroLoading).toBe(false);
    });

    it('引用稳定：训练流 stream 不影响 retro 字段', () => {
      const { result, rerender } = renderHook(() => useRetroState());
      const ref1 = result.current;
      // 触发训练流 stream（activeTraining 变化）
      act(() => {
        useTrainingStore.setState({
          activeTraining: { challengeId: 'c1' } as never,
          isLoading: true,
        });
      });
      rerender();
      // retro 字段未变 → 应返回相同引用
      expect(result.current).toBe(ref1);
    });
  });
});
