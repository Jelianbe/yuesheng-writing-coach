/**
 * LLM 评估结果 LRU 缓存
 *
 * 基于 Map 实现的轻量 LRU（最近最少使用）缓存，支持 TTL 过期。
 * 用于缓存 evaluateRewrite 的结果，减少重复 API 调用。
 */
export class LLMCache {
  private cache = new Map<string, { value: unknown; expiry: number }>();

  /**
   * @param maxEntries - 最大缓存条目数（超过时淘汰最旧条目）
   * @param ttlMs - 每个缓存的存活时间（毫秒），默认 5 分钟
   */
  constructor(
    private readonly maxEntries: number,
    private readonly ttlMs: number = 5 * 60 * 1000,
  ) {}

  /**
   * 获取缓存值
   *
   * @param key - 缓存键
   * @returns 缓存值，如不存在或已过期返回 undefined
   */
  get(key: string): unknown | undefined {
    const entry = this.cache.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expiry) {
      this.cache.delete(key);
      return undefined;
    }
    return entry.value;
  }

  /**
   * 写入缓存
   *
   * @param key - 缓存键
   * @param value - 缓存值
   */
  set(key: string, value: unknown): void {
    if (this.cache.size >= this.maxEntries) {
      const firstKey = this.cache.keys().next().value;
      if (firstKey !== undefined) this.cache.delete(firstKey);
    }
    this.cache.set(key, { value, expiry: Date.now() + this.ttlMs });
  }

  /** 清空全部缓存 */
  clear(): void {
    this.cache.clear();
  }
}
