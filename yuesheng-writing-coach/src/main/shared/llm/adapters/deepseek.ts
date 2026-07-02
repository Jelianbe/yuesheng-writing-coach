/**
 * DeepSeek 适配器
 *
 * 将 ApiProxy（DeepSeek HTTP 客户端）包装为统一的 LLMProvider 接口，
 * 使网关层可以透明地切换底层提供者。
 */

import { ApiProxy } from '../../../api-proxy';
import type { ApiConfig } from '../../../../shared/types/index';
import type { LLMProvider } from '../types';
import type {
  ApiChatMessage,
  ChatCompletionTool,
  StreamEvent,
  RewriteEvalParams,
  RewriteEvalResult,
} from '../../../api-proxy';

/**
 * DeepSeek 适配器
 *
 * 职责：将 ApiProxy 实例适配为 LLMProvider 接口，用于 LLMGateway。
 */
export class DeepSeekAdapter implements LLMProvider {
  private proxy: ApiProxy;

  constructor(config: ApiConfig) {
    this.proxy = new ApiProxy(config);
  }

  async *chatStream(
    messages: ApiChatMessage[],
    abortSignal?: AbortSignal,
  ): AsyncGenerator<string> {
    yield* this.proxy.chatStream(messages, abortSignal);
  }

  async *chatStreamWithTools(
    messages: ApiChatMessage[],
    tools: ChatCompletionTool[],
    abortSignal?: AbortSignal,
  ): AsyncGenerator<StreamEvent> {
    yield* this.proxy.chatStreamWithTools(messages, tools, abortSignal);
  }

  async evaluateRewrite(params: RewriteEvalParams): Promise<RewriteEvalResult> {
    return this.proxy.evaluateRewrite(params);
  }

  async testConnection(): Promise<{ success: boolean; error?: string }> {
    return this.proxy.testConnection();
  }

  getBaseUrl(): string {
    return this.proxy.getBaseUrl();
  }

  getApiKey(): string {
    return this.proxy.getApiKey();
  }

  updateConfig(config: ApiConfig): void {
    this.proxy.updateConfig(config);
  }
}
