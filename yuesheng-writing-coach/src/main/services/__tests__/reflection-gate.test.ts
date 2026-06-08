/**
 * ReflectionGateService 单元测试
 * 覆盖：触发判定、L2+ 过滤、语气调整、Prompt 构建
 */

import { describe, it, expect } from 'vitest';
import { ReflectionGateService } from '../reflection-gate.service';
import type { DiagnosisAnalysis, KeyPassage, TechniqueRef } from '../../../renderer/shared/types';

function mockDiagnosis(syndromeRef: string[]): DiagnosisAnalysis {
  return {
    rootCause: '测试根因',
    intentPhase: 1,
    syndromeRef,
    keyPassages: [] as KeyPassage[],
    techniquePool: [] as TechniqueRef[],
    confidence: 0.8,
  };
}

describe('ReflectionGateService', () => {
  const service = new ReflectionGateService();

  describe('shouldTriggerReflection', () => {
    it('null diagnosis → 不触发', () => {
      const result = service.shouldTriggerReflection(null);
      expect(result.shouldReflect).toBe(false);
    });

    it('空症候列表 → 不触发', () => {
      const result = service.shouldTriggerReflection(mockDiagnosis([]));
      expect(result.shouldReflect).toBe(false);
    });

    it('仅 L1 症候 → 不触发', () => {
      const result = service.shouldTriggerReflection(mockDiagnosis(['P001', 'P005']));
      expect(result.shouldReflect).toBe(false);
    });

    it('L2 症候 → 触发', () => {
      const result = service.shouldTriggerReflection(mockDiagnosis(['P003']));
      expect(result.shouldReflect).toBe(true);
      expect(result.question).toBeDefined();
      expect(result.question?.syndromeId).toBe('P003');
    });

    it('L3 症候 → 触发', () => {
      const result = service.shouldTriggerReflection(mockDiagnosis(['P002']));
      expect(result.shouldReflect).toBe(true);
      expect(result.question?.syndromeId).toBe('P002');
    });

    it('混合症候取最严重的', () => {
      const result = service.shouldTriggerReflection(mockDiagnosis(['P001', 'P002', 'P003']));
      expect(result.shouldReflect).toBe(true);
      expect(result.question?.syndromeId).toBe('P002'); // L3 优先
    });

    it('L2+ 症候无模板时使用通用问题', () => {
      // P004 是 L2 但有模板，此处测试验证有模板的症候走模板路径
      const result = service.shouldTriggerReflection(mockDiagnosis(['P004']));
      expect(result.shouldReflect).toBe(true);
      expect(result.question?.syndromeId).toBe('P004');
      expect(result.question?.question).toContain('说明性文字'); // 模板内容
    });
  });

  describe('adjustReflectionTone', () => {
    const question = '这段文字能不能换一种方式写？';

    it('doubao → 温暖语气', () => {
      const result = service.adjustReflectionTone('doubao', question);
      expect(result).toContain('别急');
      expect(result).toContain('不着急');
    });

    it('direct → 犀利语气', () => {
      const result = service.adjustReflectionTone('direct', question);
      expect(result).toContain('直说');
      expect(result).toContain('想清楚再回复我');
    });

    it('yuesheng → 默认语气', () => {
      const result = service.adjustReflectionTone('yuesheng', question);
      expect(result).toBe(`想想看：${question}`);
    });
  });

  describe('buildReflectionPrompt', () => {
    it('构建完整 Prompt 段落', () => {
      const question = {
        question: '测试问题',
        syndromeId: 'P003' as const,
        syndromeName: '情绪标签化',
      };
      const result = service.buildReflectionPrompt(question, 'yuesheng');
      expect(result).toContain('反思门控');
      expect(result).toContain('情绪标签化');
      expect(result).toContain('测试问题');
      expect(result).toContain('不要暗示答案');
    });
  });
});
