/**
 * LLMCache（LRU 缓存）单元测试
 *
 * 覆盖场景：
 * - get() 对缺失的键返回 undefined
 * - set() / get() 读写正常
 * - 超过 maxEntries 时淘汰最旧条目
 * - clear() 清空全部缓存
 * - TTL 过期（使用 vi.advanceTimersByTime）
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { LLMCache } from '../cache';

describe('LLMCache', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('get()', () => {
    it('对缺失的键返回 undefined', () => {
      const cache = new LLMCache(10);
      expect(cache.get('nonexistent')).toBeUndefined();
    });
  });

  describe('set() / get()', () => {
    it('读写正常', () => {
      const cache = new LLMCache(10);

      cache.set('key1', { data: 42 });
      cache.set('key2', 'hello');

      expect(cache.get('key1')).toEqual({ data: 42 });
      expect(cache.get('key2')).toBe('hello');
    });
  });

  describe('淘汰策略', () => {
    it('超过 maxEntries 时淘汰最旧条目', () => {
      const cache = new LLMCache(2);

      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3); // 应淘汰 'a'

      // 'a' 被淘汰
      expect(cache.get('a')).toBeUndefined();
      // 'b' 和 'c' 仍存在
      expect(cache.get('b')).toBe(2);
      expect(cache.get('c')).toBe(3);
    });
  });

  describe('clear()', () => {
    it('清空全部缓存', () => {
      const cache = new LLMCache(10);

      cache.set('x', 100);
      cache.set('y', 200);
      expect(cache.get('x')).toBe(100);

      cache.clear();

      expect(cache.get('x')).toBeUndefined();
      expect(cache.get('y')).toBeUndefined();
    });
  });

  describe('TTL 过期', () => {
    it('超过 TTL 后 get() 返回 undefined', async () => {
      const ttlMs = 5 * 60 * 1000; // 5 分钟，默认值
      const cache = new LLMCache(10, ttlMs);

      cache.set('ephemeral', 'value');

      // TTL 未到，值仍存在
      await vi.advanceTimersByTimeAsync(ttlMs - 1);
      expect(cache.get('ephemeral')).toBe('value');

      // 超过 TTL，值应被清除
      await vi.advanceTimersByTimeAsync(2);
      expect(cache.get('ephemeral')).toBeUndefined();
    });
  });
});
