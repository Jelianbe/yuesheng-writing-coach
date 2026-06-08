import { describe, it, expect } from 'vitest';
import { TeachingPhase, TeachingSubphase } from '../../../shared/constants';
import {
  getPhaseName,
  getSubphaseName,
  getNextPhase,
  getFirstSubphaseOf,
  getNextSubphase,
  calculatePhaseProgress,
} from '../teaching-state-machine';

describe('teaching-state-machine', () => {
  describe('getPhaseName', () => {
    it('返回正确的阶段中文名称', () => {
      expect(getPhaseName(TeachingPhase.INIT)).toBe('初次见面');
      expect(getPhaseName(TeachingPhase.WORLD)).toBe('世界观搭建');
      expect(getPhaseName(TeachingPhase.PRACTICE_LOOP)).toBe('诊断与训练');
      expect(getPhaseName(TeachingPhase.REVIEW)).toBe('复盘总结');
    });
  });

  describe('getSubphaseName', () => {
    it('返回正确的子阶段中文名称', () => {
      expect(getSubphaseName(TeachingSubphase.WORLD_PROTAGONIST)).toBe('确定主角');
      expect(getSubphaseName(TeachingSubphase.PRACTICE_IDENTIFY)).toBe('识别问题');
      expect(getSubphaseName(TeachingSubphase.REVIEW_SUMMARY)).toBe('总结复盘');
    });
  });

  describe('getNextPhase', () => {
    it('INIT → ENGAGE → WORLD', () => {
      expect(getNextPhase(TeachingPhase.INIT)).toBe(TeachingPhase.ENGAGE);
      expect(getNextPhase(TeachingPhase.ENGAGE)).toBe(TeachingPhase.WORLD);
    });

    it('WORLD → PRACTICE_LOOP', () => {
      expect(getNextPhase(TeachingPhase.WORLD)).toBe(TeachingPhase.PRACTICE_LOOP);
    });

    it('PRACTICE_LOOP 不自动离开', () => {
      expect(getNextPhase(TeachingPhase.PRACTICE_LOOP)).toBe(TeachingPhase.PRACTICE_LOOP);
    });

    it('REVIEW → PRACTICE_LOOP', () => {
      expect(getNextPhase(TeachingPhase.REVIEW)).toBe(TeachingPhase.PRACTICE_LOOP);
    });
  });

  describe('getFirstSubphaseOf', () => {
    it('返回 WORLD 阶段的第一个子阶段', () => {
      expect(getFirstSubphaseOf(TeachingPhase.WORLD)).toBe(TeachingSubphase.WORLD_NATURAL_LAW);
    });

    it('返回 PRACTICE_LOOP 阶段的第一个子阶段', () => {
      expect(getFirstSubphaseOf(TeachingPhase.PRACTICE_LOOP)).toBe(TeachingSubphase.PRACTICE_IDENTIFY);
    });

    it('INIT 阶段无子阶段时抛出错误', () => {
      expect(() => getFirstSubphaseOf(TeachingPhase.INIT)).toThrow();
    });
  });

  describe('getNextSubphase', () => {
    it('推进到下一个子阶段', () => {
      const next = getNextSubphase(TeachingPhase.WORLD, TeachingSubphase.WORLD_NATURAL_LAW);
      expect(next).toBe(TeachingSubphase.WORLD_PROTAGONIST);
    });

    it('子阶段末尾返回 null', () => {
      const next = getNextSubphase(TeachingPhase.WORLD, TeachingSubphase.WORLD_DAILY_DETAIL);
      expect(next).toBeNull();
    });

    it('不存在的子阶段返回 null', () => {
      const next = getNextSubphase(TeachingPhase.WORLD, TeachingSubphase.REVIEW_SUMMARY);
      expect(next).toBeNull();
    });
  });

  describe('calculatePhaseProgress', () => {
    it('WORLD 阶段第一个子阶段进度为 0.2', () => {
      expect(calculatePhaseProgress(TeachingPhase.WORLD, TeachingSubphase.WORLD_NATURAL_LAW)).toBe(0.2);
    });

    it('WORLD 阶段最后一个子阶段进度为 1', () => {
      expect(calculatePhaseProgress(TeachingPhase.WORLD, TeachingSubphase.WORLD_DAILY_DETAIL)).toBe(1);
    });

    it('PRACTICE_LOOP 第一阶段进度为 0.2', () => {
      expect(calculatePhaseProgress(TeachingPhase.PRACTICE_LOOP, TeachingSubphase.PRACTICE_IDENTIFY)).toBe(0.2);
    });

    it('不存在的子阶段返回 0', () => {
      expect(calculatePhaseProgress(TeachingPhase.WORLD, TeachingSubphase.PRACTICE_IDENTIFY)).toBe(0);
    });
  });
});
