/**
 * LLM 网关服务（DI 集成层）
 *
 * 负责：管理 LLMGateway 实例生命周期，注入到所有消费方
 * 依赖：ConfigService（提供 API 配置）
 * DI 注册名：'llmGatewayService'
 */
import { LLMGateway } from '../llm/gateway';
import { DeepSeekAdapter } from '../llm/adapters/deepseek';
import type { ConfigService } from './config.service';
import type { LLMProvider, ApiChatMessage, ChatCompletionTool, StreamEvent, RewriteEvalParams, RewriteEvalResult } from '../llm/types';

export class LLMGatewayService implements LLMProvider {
  private gateway: LLMGateway | null = null;
  private configService: ConfigService;

  constructor(configService: ConfigService) {
    this.configService = configService;
  }

  /** 获取或创建 LLMGateway 实例 */
  private getGateway(): LLMGateway {
    if (!this.gateway) {
      const config = this.configService.getConfig();
      const adapter = new DeepSeekAdapter(config);
      this.gateway = new LLMGateway(adapter);
    }
    return this.gateway;
  }

  /** 更新网关配置（配置变更时调用） */
  updateConfig(): void {
    const config = this.configService.getConfig();
    const adapter = new DeepSeekAdapter(config);
    this.gateway = new LLMGateway(adapter);
  }

  /** 流式聊天 */
  async *chatStream(messages: ApiChatMessage[], abortSignal?: AbortSignal): AsyncGenerator<string> {
    yield* this.getGateway().chatStream(messages, abortSignal);
  }

  /** 带工具调用的流式聊天 */
  async *chatStreamWithTools(
    messages: ApiChatMessage[],
    tools: ChatCompletionTool[],
    abortSignal?: AbortSignal,
  ): AsyncGenerator<StreamEvent> {
    yield* this.getGateway().chatStreamWithTools(messages, tools, abortSignal);
  }

  /** 评估修改效果 */
  async evaluateRewrite(params: RewriteEvalParams): Promise<RewriteEvalResult> {
    return this.getGateway().evaluateRewrite(params);
  }

  /** 测试 API 连接 */
  async testConnection(): Promise<{ success: boolean; error?: string }> {
    return this.getGateway().testConnection();
  }

  getBaseUrl(): string {
    return this.getGateway().getBaseUrl();
  }

  getApiKey(): string {
    return this.getGateway().getApiKey();
  }

  updateConfigExternal(config: unknown): void {
    this.getGateway().updateConfig(config);
  }
}
