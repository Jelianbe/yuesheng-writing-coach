/**
 * truncation.test.ts — ADR-003 D 阶段：长文截断单元测试
 *
 * 覆盖：
 * - 空内容 / 短内容（不触发截断）
 * - 超阈值内容（保留头尾 + 省略标记）
 * - 极端阈值（小于省略标记长度时降级）
 * - 自定义 maxChars / headRatio
 * - 告警日志（silent 选项）
 * - 头尾比例正确性
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { MAX_CHARS, truncateChapterContent } from '../truncation';

// 截断时插入的标记（与 truncation.ts 保持一致）
const TRUNCATION_MARKER = '\n\n[... 章节内容过长，中间部分已省略 ...]\n\n';

describe('truncateChapterContent', () => {
  let warnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  });

  afterEach(() => {
    warnSpy.mockRestore();
  });

  describe('空内容 / 短内容', () => {
    it('空字符串应原样返回且不截断', () => {
      const result = truncateChapterContent('');
      expect(result.text).toBe('');
      expect(result.truncated).toBe(false);
      expect(result.originalLength).toBe(0);
      expect(result.truncatedLength).toBe(0);
    });

    it('null/undefined 输入应降级为空字符串', () => {
      // @ts-expect-error 测试防御：故意传入非法值
      const result = truncateChapterContent(null);
      expect(result.text).toBe('');
      expect(result.truncated).toBe(false);
    });

    it('长度等于 MAX_CHARS 的内容不应截断', () => {
      const content = 'a'.repeat(MAX_CHARS);
      const result = truncateChapterContent(content);
      expect(result.truncated).toBe(false);
      expect(result.text).toBe(content);
      expect(result.originalLength).toBe(MAX_CHARS);
    });

    it('长度小于 MAX_CHARS 的内容不应截断', () => {
      const content = 'a'.repeat(MAX_CHARS - 1);
      const result = truncateChapterContent(content);
      expect(result.truncated).toBe(false);
      expect(result.text).toBe(content);
    });
  });

  describe('超阈值内容', () => {
    it('超出 MAX_CHARS 时应截断并标记 truncated=true', () => {
      const content = 'a'.repeat(MAX_CHARS + 1000);
      const result = truncateChapterContent(content, { silent: true });
      expect(result.truncated).toBe(true);
      expect(result.originalLength).toBe(MAX_CHARS + 1000);
      expect(result.truncatedLength).toBeLessThanOrEqual(MAX_CHARS);
    });

    it('截断后应包含头尾原始内容', () => {
      const head = 'A'.repeat(100);
      const tail = 'B'.repeat(100);
      const content = head + 'C'.repeat(MAX_CHARS * 2) + tail;
      const result = truncateChapterContent(content, { silent: true });
      expect(result.text.startsWith(head)).toBe(true);
      expect(result.text.endsWith(tail)).toBe(true);
    });

    it('截断后应包含省略标记', () => {
      const content = 'a'.repeat(MAX_CHARS * 2);
      const result = truncateChapterContent(content, { silent: true });
      expect(result.text).toContain('[... 章节内容过长，中间部分已省略 ...]');
    });

    it('默认头尾比例应为 0.7', () => {
      const content = 'a'.repeat(MAX_CHARS * 2);
      const result = truncateChapterContent(content, { silent: true });
      // 头 = (MAX_CHARS - markerLength) * 0.7
      const expectedHeadLen = Math.floor((MAX_CHARS - TRUNCATION_MARKER.length) * 0.7);
      const head = result.text.slice(0, expectedHeadLen);
      expect(head).toBe('a'.repeat(expectedHeadLen));
    });
  });

  describe('自定义参数', () => {
    it('应支持自定义 maxChars', () => {
      const content = 'a'.repeat(2000);
      const result = truncateChapterContent(content, { maxChars: 1000, silent: true });
      expect(result.truncated).toBe(true);
      expect(result.truncatedLength).toBeLessThanOrEqual(1000);
    });

    it('应支持自定义 headRatio=0.5', () => {
      const content = 'a'.repeat(2000);
      const result = truncateChapterContent(content, { maxChars: 1000, headRatio: 0.5, silent: true });
      expect(result.truncated).toBe(true);
      // 头 = (1000 - markerLength) * 0.5
      const expectedHeadLen = Math.floor((1000 - TRUNCATION_MARKER.length) * 0.5);
      const head = result.text.slice(0, expectedHeadLen);
      expect(head).toBe('a'.repeat(expectedHeadLen));
    });

    it('头尾和应等于 maxChars 减去省略标记长度', () => {
      const content = 'x'.repeat(5000);
      const result = truncateChapterContent(content, { maxChars: 1000, silent: true });
      const headPart = result.text.split(TRUNCATION_MARKER)[0];
      const tailPart = result.text.split(TRUNCATION_MARKER)[1];
      expect(headPart.length + tailPart.length).toBe(1000 - TRUNCATION_MARKER.length);
    });
  });

  describe('极端阈值', () => {
    it('maxChars 小于 marker 长度时应降级为仅保留头部', () => {
      const content = 'a'.repeat(5000);
      const result = truncateChapterContent(content, { maxChars: 10, silent: true });
      expect(result.truncated).toBe(true);
      // 头 = max(0, 10 - markerLength) = 0
      const head = result.text.split(TRUNCATION_MARKER)[0];
      expect(head).toBe('');
      // 降级时仍插入省略标记（不再追加尾部）
      expect(result.text).toContain('章节内容过长，中间部分已省略');
    });
  });

  describe('告警日志', () => {
    it('silent=false 时应输出告警', () => {
      const content = 'a'.repeat(MAX_CHARS + 100);
      truncateChapterContent(content, { chapterId: 'ch-test', source: 'unit-test' });
      expect(warnSpy).toHaveBeenCalled();
      const logLine = warnSpy.mock.calls[0]?.[0] as string;
      expect(logLine).toContain('[Truncation]');
      expect(logLine).toContain('chapterId=ch-test');
      expect(logLine).toContain('unit-test');
    });

    it('silent=true 时不应输出告警', () => {
      const content = 'a'.repeat(MAX_CHARS + 100);
      truncateChapterContent(content, { silent: true });
      expect(warnSpy).not.toHaveBeenCalled();
    });

    it('未截断时不应输出告警', () => {
      const content = 'a'.repeat(100);
      truncateChapterContent(content, { chapterId: 'ch-test' });
      expect(warnSpy).not.toHaveBeenCalled();
    });
  });

  describe('MAX_CHARS 常量', () => {
    it('应等于 4000（ADR-003 决策）', () => {
      expect(MAX_CHARS).toBe(4000);
    });
  });
});
