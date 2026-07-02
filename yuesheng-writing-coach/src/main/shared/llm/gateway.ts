/**
 * LLM 网关
 *
 * 核心职责：
 * 1. 将 LLMProvider 包装为带限流、重试、超时、缓存的可靠调用层
 * 2. API 不可用时自动降级（fallback），不向上层抛异常
 * 3. 统一管理网关级配置（并发、超时、重试策略）
 *
 * 设计决策：
 * - 聊天流（chatStream / chatStreamWithTools）使用 retry-on-fail 模式包装 generator，
 *   每次重试时重新创建 generator 实例（因为底层 fetch 流一旦失败不可重用）
 * - 评估请求（evaluateRewrite）使用 withRetry + LRU 缓存
 */

import type { LLMProvider, GatewayConfig } from './types';
import { DEFAULT_GATEWAY_CONFIG } from './types';
import { RateLimiter } from './middleware/rate-limiter';
import { withRetry } from './middleware/retry';
import { getFallbackResponse } from './middleware/fallback';
import { LLMCache } from './cache';
import type {
  ApiChatMessage,
  ChatCompletionTool,
  StreamEvent,
  RewriteEvalParams,
  RewriteEvalResult,
} from '../../api-proxy';

/**
 * LLM 网关
 *
 * 装饰 LLMProvider，在其上叠加以下中间件层（按执行顺序）：
 *   限流 → 超时 → 重试 → 降级 / 缓存
 */
export class LLMGateway implements LLMProvider {
  private provider: LLMProvider;
  private rateLimiter: RateLimiter;
  private cache: LLMCache;
  private config: GatewayConfig;

  constructor(provider: LLMProvider, config?: Partial<GatewayConfig>) {
    this.provider = provider;
    this.config = { ...DEFAULT_GATEWAY_CONFIG, ...config };
    this.rateLimiter = new RateLimiter(this.config.maxConcurrency, 1000);
    this.cache = new LLMCache(this.config.cacheMaxEntries);
  }

  /**
   * 流式聊天（带限流 + 超时 + 重试 + 降级）
   *
   * 重试策略：每次失败后重新创建 generator，指数退避延迟。
   * 所有重试均失败后，降级为本地 fallback 文本。
   */
  async *chatStream(
    messages: ApiChatMessage[],
    abortSignal?: AbortSignal,
  ): AsyncGenerator<string> {
    await this.rateLimiter.acquire();

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.config.requestTimeoutMs);
    const combinedSignal = abortSignal
      ? combineAbortSignals(abortSignal, controller.signal)
      : controller.signal;

    let attempts = 0;
    while (true) {
      try {
        const gen = this.provider.chatStream(messages, combinedSignal);
        for await (const chunk of gen) {
          yield chunk;
        }
        break; // 成功，退出重试循环
      } catch (error) {
        attempts++;
        if (attempts > this.config.maxRetries) {
          console.error('[LLMGateway] chatStream 重试耗尽:', error);
          yield getFallbackResponse('stream') as string;
          break;
        }
        console.warn(
          `[LLMGateway] chatStream 第${attempts}次失败，${this.config.retryDelayMs * 2 ** (attempts - 1)}ms 后重试:`,
          error,
        );
        await new Promise(resolve =>
          setTimeout(resolve, this.config.retryDelayMs * 2 ** (attempts - 1)),
        );
      }
    }
    clearTimeout(timeoutId);
  }

  /**
   * 带工具调用的流式聊天（同 chatStream 的中间件策略）
   */
  async *chatStreamWithTools(
    messages: ApiChatMessage[],
    tools: ChatCompletionTool[],
    abortSignal?: AbortSignal,
  ): AsyncGenerator<StreamEvent> {
    await this.rateLimiter.acquire();

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.config.requestTimeoutMs);
    const combinedSignal = abortSignal
      ? combineAbortSignals(abortSignal, controller.signal)
      : controller.signal;

    let attempts = 0;
    while (true) {
      try {
        const gen = this.provider.chatStreamWithTools(messages, tools, combinedSignal);
        for await (const event of gen) {
          yield event;
        }
        break; // 成功，退出重试循环
      } catch (error) {
        attempts++;
        if (attempts > this.config.maxRetries) {
          console.error('[LLMGateway] chatStreamWithTools 重试耗尽:', error);
          yield { type: 'text', content: getFallbackResponse('stream') as string };
          break;
        }
        console.warn(
          `[LLMGateway] chatStreamWithTools 第${attempts}次失败，${this.config.retryDelayMs * 2 ** (attempts - 1)}ms 后重试:`,
          error,
        );
        await new Promise(resolve =>
          setTimeout(resolve, this.config.retryDelayMs * 2 ** (attempts - 1)),
        );
      }
    }
    clearTimeout(timeoutId);
  }

  /**
   * 评估修改效果（带缓存 + 限流 + 重试 + 降级）
   *
   * 缓存键由症候名 + 原文摘要 + 改文摘要组成，避免完全相同的评估重复请求 API。
   */
  async evaluateRewrite(params: RewriteEvalParams): Promise<RewriteEvalResult> {
    const cacheKey = `eval:${params.syndromeName}:${params.originalText.substring(0, 100)}:${params.rewrittenText.substring(0, 100)}`;
    const cached = this.cache.get(cacheKey);
    if (cached) return cached as RewriteEvalResult;

    await this.rateLimiter.acquire();
    try {
      const result = await withRetry(
        () => this.provider.evaluateRewrite(params),
        this.config.maxRetries,
        this.config.retryDelayMs,
        'evaluateRewrite',
      );
      this.cache.set(cacheKey, result);
      return result;
    } catch (error) {
      console.error('[LLMGateway] evaluateRewrite 重试耗尽:', error);
      return getFallbackResponse('eval') as RewriteEvalResult;
    }
  }

  /** 测试连接（直通，不经过网关中间件） */
  async testConnection(): Promise<{ success: boolean; error?: string }> {
    try {
      return await this.provider.testConnection();
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  getBaseUrl(): string {
    return this.provider.getBaseUrl();
  }

  getApiKey(): string {
    return this.provider.getApiKey();
  }

  updateConfig(config: unknown): void {
    this.provider.updateConfig(config);
  }

  /**
   * 动态更新网关配置（重置限流器和缓存实例）
   *
   * @param config - 要更新的配置片段
   */
  updateGatewayConfig(config: Partial<GatewayConfig>): void {
    this.config = { ...this.config, ...config };
    this.rateLimiter = new RateLimiter(this.config.maxConcurrency, 1000);
    this.cache = new LLMCache(this.config.cacheMaxEntries);
  }
}

/**
 * 组合多个 AbortSignal
 *
 * 当任一 signal 被 abort 时，组合 signal 也被 abort。
 * 用于同时支持外部调用方的取消信号和网关内部超时信号。
 */
function combineAbortSignals(...signals: AbortSignal[]): AbortSignal {
  const controller = new AbortController();
  for (const signal of signals) {
    if (signal.aborted) {
      controller.abort(signal.reason);
      return controller.signal;
    }
    signal.addEventListener('abort', () => controller.abort(signal.reason), { once: true });
  }
  return controller.signal;
}
