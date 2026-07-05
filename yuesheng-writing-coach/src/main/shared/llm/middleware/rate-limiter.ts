/**
 * 令牌桶限流器
 *
 * 基于令牌桶算法实现请求速率限制，用于控制 LLM API 的并发请求数。
 * 每 `refillIntervalMs` 毫秒补充一个令牌，令牌耗尽时请求需等待。
 */
export class RateLimiter {
  private tokens: number;
  private lastRefill: number;

  /**
   * @param maxTokens - 最大令牌数（即最大并发数）
   * @param refillIntervalMs - 每补充一个令牌的间隔（毫秒）
   */
  constructor(
    private readonly maxTokens: number,
    private readonly refillIntervalMs: number,
  ) {
    this.tokens = maxTokens;
    this.lastRefill = Date.now();
  }

  /** 补充令牌 */
  private refill(): void {
    const now = Date.now();
    const elapsed = now - this.lastRefill;
    const newTokens = Math.floor(elapsed / this.refillIntervalMs);
    if (newTokens > 0) {
      this.tokens = Math.min(this.maxTokens, this.tokens + newTokens);
      this.lastRefill = now;
    }
  }

  /**
   * 获取一个令牌；如无可用的令牌则等待直到下一个 refill 间隔。
   */
  async acquire(): Promise<void> {
    this.refill();
    if (this.tokens > 0) {
      this.tokens--;
      return;
    }
    // 等待下一次补充
    const waitMs = this.refillIntervalMs - (Date.now() - this.lastRefill);
    if (waitMs > 0) {
      await new Promise(resolve => setTimeout(resolve, waitMs));
    }
    return this.acquire();
  }

  /** 当前可用令牌数 */
  get availableTokens(): number {
    this.refill();
    return this.tokens;
  }
}
