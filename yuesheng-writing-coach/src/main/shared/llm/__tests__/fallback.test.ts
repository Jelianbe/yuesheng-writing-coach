/**
 * 本地降级响应（fallback）单元测试
 *
 * 覆盖场景：
 * - getFallbackResponse('eval') 返回合法的 RewriteEvalResult 结构
 * - getFallbackResponse('stream') 返回字符串
 */

import { describe, it, expect } from 'vitest';
import { getFallbackResponse } from '../middleware/fallback';
import type { RewriteEvalResult } from '../../../api-proxy';

describe('getFallbackResponse', () => {
  describe("type = 'eval'", () => {
    it('返回合法的 RewriteEvalResult 结构', () => {
      const result = getFallbackResponse('eval') as RewriteEvalResult;

      // 检查结构完整性
      expect(result).toHaveProperty('improvement');
      expect(result).toHaveProperty('analysis');
      expect(result).toHaveProperty('suggestion');

      // 检查 improvement 取值
      expect(result.improvement).toBe('略有改善');

      // 检查字段类型
      expect(typeof result.analysis).toBe('string');
      expect(typeof result.suggestion).toBe('string');

      // 检查内容非空
      expect(result.analysis.length).toBeGreaterThan(0);
      expect(result.suggestion.length).toBeGreaterThan(0);
    });
  });

  describe("type = 'stream'", () => {
    it('返回字符串', () => {
      const result: unknown = getFallbackResponse('stream');

      expect(typeof result).toBe('string');
      expect((result as string).length).toBeGreaterThan(0);
      expect(result).toBe('AI 暂时不可用，请稍后重试。');
    });
  });
});
