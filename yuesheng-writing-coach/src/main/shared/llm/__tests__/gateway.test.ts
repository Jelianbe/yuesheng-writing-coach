/**
 * LLMGateway 单元测试
 *
 * 覆盖场景：
 * - evaluateRewrite 在相同参数重复调用时返回缓存结果（去重）
 * - evaluateRewrite 在 provider 抛出异常时返回 fallback
 * - chatStream 在 provider 抛出异常时 yield fallback 内容
 * - testConnection 在 provider 失败时返回 error 结果
 * - Gateway 遵守 requestTimeoutMs 配置（使用 vi.useFakeTimers）
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { LLMGateway } from '../gateway';
import { getFallbackResponse } from '../middleware/fallback';
import type { LLMProvider } from '../types';
import type {
  ApiChatMessage,
  StreamEvent,
  RewriteEvalParams,
  RewriteEvalResult,
} from '../types';

// ============================================================
// Helper: 创建 Mock LLMProvider
// ============================================================
function createMockProvider(overrides?: Partial<LLMProvider>): LLMProvider {
  const defaultProvider: LLMProvider = {
    chatStream: vi.fn().mockImplementation(
      async function* (): AsyncGenerator<string> {
        yield 'mock chunk';
      },
    ),
    chatStreamWithTools: vi.fn().mockImplementation(
      async function* (): AsyncGenerator<StreamEvent> {
        yield { type: 'text', content: 'mock tool chunk' };
      },
    ),
    evaluateRewrite: vi
      .fn()
      .mockResolvedValue({
        improvement: '略有改善' as const,
        analysis: 'mock analysis',
        suggestion: 'mock suggestion',
      }),
    testConnection: vi.fn().mockResolvedValue({ success: true }),
    getBaseUrl: vi.fn().mockReturnValue('https://mock.api.com'),
    getApiKey: vi.fn().mockReturnValue('mock-key'),
    updateConfig: vi.fn(),
  };

  return { ...defaultProvider, ...overrides };
}

// ============================================================
// 测试套件
// ============================================================
describe('LLMGateway', () => {
  describe('evaluateRewrite', () => {
    it('相同参数重复调用时返回缓存结果（去重）', async () => {
      const evaluateRewrite = vi
        .fn<(params: RewriteEvalParams) => Promise<RewriteEvalResult>>()
        .mockResolvedValue({
          improvement: '略有改善',
          analysis: 'analysis',
          suggestion: 'suggestion',
        });

      const provider = createMockProvider({ evaluateRewrite });
      const gateway = new LLMGateway(provider, { maxRetries: 0 });

      const params: RewriteEvalParams = {
        originalText: '你好世界',
        rewrittenText: 'Hello World',
        syndromeName: '欧化句式',
      };

      // 第一次调用 -> 应调用 provider
      const result1 = await gateway.evaluateRewrite(params);
      expect(result1.analysis).toBe('analysis');
      expect(evaluateRewrite).toHaveBeenCalledTimes(1);

      // 第二次调用（相同参数）-> 应命中缓存，不调用 provider
      const result2 = await gateway.evaluateRewrite(params);
      expect(result2.analysis).toBe('analysis');
      expect(evaluateRewrite).toHaveBeenCalledTimes(1);
    });

    it('provider 抛出异常时返回 fallback', async () => {
      const evaluateRewrite = vi
        .fn<(params: RewriteEvalParams) => Promise<RewriteEvalResult>>()
        .mockRejectedValue(new Error('API unavailable'));

      const provider = createMockProvider({ evaluateRewrite });
      const gateway = new LLMGateway(provider, { maxRetries: 0 });

      const params: RewriteEvalParams = {
        originalText: '原文',
        rewrittenText: '改文',
        syndromeName: '语病',
      };

      const result = await gateway.evaluateRewrite(params);
      const expected = getFallbackResponse('eval') as RewriteEvalResult;

      expect(result.improvement).toBe(expected.improvement);
      expect(result.analysis).toBe(expected.analysis);
      expect(result.suggestion).toBe(expected.suggestion);
    });
  });

  describe('chatStream', () => {
    it('provider 抛出异常时 yield fallback 内容', async () => {
      const chatStream = vi
        .fn<(messages: ApiChatMessage[], signal?: AbortSignal) => AsyncGenerator<string>>()
        .mockImplementation(async function* (): AsyncGenerator<string> {
          yield ''; // 必须先 yield 才能 throw（否则 require-yield 报错）
          throw new Error('Stream failed');
        });

      const provider = createMockProvider({ chatStream });
      const gateway = new LLMGateway(provider, { maxRetries: 0 });

      const messages: ApiChatMessage[] = [{ role: 'user', content: 'test' }];
      const gen = gateway.chatStream(messages);

      const chunks: string[] = [];
      for await (const chunk of gen) {
        chunks.push(chunk);
      }

      // 先 yield 了部分内容（''），然后抛出异常，网关捕获后 yield fallback
      expect(chunks).toHaveLength(2);
      expect(chunks[0]).toBe('');
      expect(chunks[1]).toBe(getFallbackResponse('stream'));
    });
  });

  describe('testConnection', () => {
    it('provider 失败时返回 error 结果', async () => {
      const testConnection = vi
        .fn<() => Promise<{ success: boolean; error?: string }>>()
        .mockRejectedValue(new Error('Connection refused'));

      const provider = createMockProvider({ testConnection });
      const gateway = new LLMGateway(provider);

      const result = await gateway.testConnection();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Connection refused');
    });

    it('provider 成功时返回 success 结果', async () => {
      const testConnection = vi
        .fn<() => Promise<{ success: boolean; error?: string }>>()
        .mockResolvedValue({ success: true });

      const provider = createMockProvider({ testConnection });
      const gateway = new LLMGateway(provider);

      const result = await gateway.testConnection();

      expect(result.success).toBe(true);
      expect(result.error).toBeUndefined();
    });
  });

  describe('超时配置', () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('Gateway 遵守 requestTimeoutMs 配置', async () => {
      // 创建一个 provider，其 chatStream 一直挂起直到 AbortSignal 触发
      const chatStream = vi
        .fn<
          (messages: ApiChatMessage[], signal?: AbortSignal) => AsyncGenerator<string>
        >()
        .mockImplementation(
          async function* (
            _messages: ApiChatMessage[],
            signal?: AbortSignal,
          ): AsyncGenerator<string> {
            // 挂起直到被 abort；当 timeout 触发时 signal 会被 abort
            await new Promise<void>((_resolve, reject) => {
              if (signal?.aborted) {
                reject(new DOMException('The operation was aborted', 'AbortError'));
                return;
              }
              signal?.addEventListener(
                'abort',
                () => {
                  reject(new DOMException('The operation was aborted', 'AbortError'));
                },
                { once: true },
              );
            });
            yield 'should never reach';
          },
        );

      const provider = createMockProvider({ chatStream });
      const gateway = new LLMGateway(provider, {
        requestTimeoutMs: 1000,
        maxRetries: 0,
      });

      const messages: ApiChatMessage[] = [{ role: 'user', content: 'hi' }];
      const gen = gateway.chatStream(messages);

      // 开始迭代（触发超时计时器）
      const nextPromise = gen.next();

      // 前进 1000ms 触发超时
      await vi.advanceTimersByTimeAsync(1000);

      const result = await nextPromise;
      expect(result.done).toBe(false);
      expect(result.value).toBe(getFallbackResponse('stream'));
    });
  });
});
