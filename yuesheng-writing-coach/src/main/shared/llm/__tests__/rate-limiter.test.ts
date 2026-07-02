/**
 * RateLimiter（令牌桶限流器）单元测试
 *
 * 覆盖场景：
 * - acquire() 在令牌可用时立即返回
 * - acquire() 在令牌耗尽时等待补充
 * - availableTokens 属性正确反映已消耗的令牌
 * - 并发 acquire 被正确限流
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { RateLimiter } from '../middleware/rate-limiter';

describe('RateLimiter', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('acquire()', () => {
    it('当令牌可用时立即返回', async () => {
      const limiter = new RateLimiter(3, 1000);

      // 前 3 次 acquire 应使用初始令牌，无需等待
      await expect(limiter.acquire()).resolves.toBeUndefined();
      await expect(limiter.acquire()).resolves.toBeUndefined();
      await expect(limiter.acquire()).resolves.toBeUndefined();

      // 此时可用令牌应为 0
      expect(limiter.availableTokens).toBe(0);
    });

    it('当令牌耗尽时等待补充', async () => {
      const limiter = new RateLimiter(1, 1000);

      // 消耗唯一令牌
      await limiter.acquire();
      expect(limiter.availableTokens).toBe(0);

      // 第 2 次 acquire 应该等待 refill
      const acquirePromise = limiter.acquire();

      // 时间尚未前进，令牌不可用，promise 不应 resolve
      await vi.advanceTimersByTimeAsync(0);
      expect(limiter.availableTokens).toBe(0);

      // 前进 1000ms 使一个令牌被补充
      await vi.advanceTimersByTimeAsync(1000);
      await expect(acquirePromise).resolves.toBeUndefined();
    });
  });

  describe('availableTokens', () => {
    it('反映已消耗的令牌数', async () => {
      const limiter = new RateLimiter(5, 1000);

      expect(limiter.availableTokens).toBe(5);

      await limiter.acquire();
      expect(limiter.availableTokens).toBe(4);

      await limiter.acquire();
      expect(limiter.availableTokens).toBe(3);

      await limiter.acquire();
      // 消耗 3 个，剩余 2 个
      expect(limiter.availableTokens).toBe(2);
    });
  });

  describe('并发限流', () => {
    it('并发 acquire 被正确限流（仅 maxTokens 个立即通过）', async () => {
      const limiter = new RateLimiter(2, 1000);

      // 记录 acquire 完成的顺序
      const completionOrder: number[] = [];
      const mark = (id: number) => completionOrder.push(id);

      // 启动 4 个并发 acquire（void 抑制未使用变量 lint）
      void limiter.acquire().then(() => mark(1));
      void limiter.acquire().then(() => mark(2));
      void limiter.acquire().then(() => mark(3));
      void limiter.acquire().then(() => mark(4));

      // 让微任务执行完毕（前 2 个应立即完成）
      await vi.advanceTimersByTimeAsync(0);

      // 只有 p1 和 p2 应已完成
      expect(completionOrder).toContain(1);
      expect(completionOrder).toContain(2);
      expect(completionOrder).not.toContain(3);
      expect(completionOrder).not.toContain(4);

      // 前进一个 refill 间隔（p3 应获得补充的令牌）
      await vi.advanceTimersByTimeAsync(1000);
      await vi.advanceTimersByTimeAsync(0);
      expect(completionOrder.length).toBe(3);

      // 再前进一个 refill 间隔（p4 应获得下一个补充的令牌）
      await vi.advanceTimersByTimeAsync(1000);
      await vi.advanceTimersByTimeAsync(0);
      expect(completionOrder.length).toBe(4);
    });
  });
});
