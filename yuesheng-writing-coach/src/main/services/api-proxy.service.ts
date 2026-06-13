/**
 * API 代理服务
 * 负责：管理 ApiProxy 实例生命周期，提供流式聊天 + 工具调用封装
 * 依赖：ConfigService（提供 API 配置）
 * DI 注册名：'apiProxyService'
 */

import { ApiProxy, type ChatCompletionTool, type StreamEvent, type RewriteEvalParams, type RewriteEvalResult } from '../api-proxy';
import type { ConfigService } from './config.service';

export class ApiProxyService {
  private proxy: ApiProxy | null = null;
  private configService: ConfigService;

  constructor(configService: ConfigService) {
    this.configService = configService;
  }

  /** 获取或创建 ApiProxy 实例 */
  private getProxy(): ApiProxy {
    if (!this.proxy) {
      const config = this.configService.getConfig();
      this.proxy = new ApiProxy(config);
    }
    return this.proxy;
  }

  /** 更新代理配置（配置变更时调用） */
  updateConfig(): void {
    const config = this.configService.getConfig();
    if (this.proxy) {
      this.proxy.updateConfig(config);
    } else {
      this.proxy = new ApiProxy(config);
    }
  }

  /** 获取基础 URL */
  getBaseUrl(): string {
    return this.getProxy().getBaseUrl();
  }

  /** 获取 API Key */
  getApiKey(): string {
    return this.getProxy().getApiKey();
  }

  /** 流式聊天 */
  async *chatStream(messages: Parameters<ApiProxy['chatStream']>[0], abortSignal?: AbortSignal): AsyncGenerator<string> {
    yield* this.getProxy().chatStream(messages, abortSignal);
  }

  /** 带工具调用的流式聊天 */
  async *chatStreamWithTools(
    messages: Parameters<ApiProxy['chatStreamWithTools']>[0],
    tools: ChatCompletionTool[],
    abortSignal?: AbortSignal,
  ): AsyncGenerator<StreamEvent> {
    yield* this.getProxy().chatStreamWithTools(messages, tools, abortSignal);
  }

  /** 测试连接 */
  async testConnection(): Promise<{ success: boolean; error?: string }> {
    return this.getProxy().testConnection();
  }

  /** 评估修改效果 */
  async evaluateRewrite(params: RewriteEvalParams): Promise<RewriteEvalResult> {
    return this.getProxy().evaluateRewrite(params);
  }
}
