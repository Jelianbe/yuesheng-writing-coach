/**
 * LLM 网关类型定义
 *
 * 重新导出 ApiProxy 中的类型，并定义网关专用接口和配置。
 */

import type {
  ApiChatMessage,
  RewriteEvalParams,
  RewriteEvalResult,
  ChatCompletionTool,
  StreamEvent,
  AccumulatedToolCall,
} from '../../api-proxy';

// --- 重新导出 ApiProxy 类型 ---
export type {
  ApiChatMessage,
  RewriteEvalParams,
  RewriteEvalResult,
  ChatCompletionTool,
  StreamEvent,
  AccumulatedToolCall,
};

/** LLM 提供者统一接口 */
export interface LLMProvider {
  /** 流式聊天 */
  chatStream(messages: ApiChatMessage[], abortSignal?: AbortSignal): AsyncGenerator<string>;
  /** 带工具调用的流式聊天 */
  chatStreamWithTools(
    messages: ApiChatMessage[],
    tools: ChatCompletionTool[],
    abortSignal?: AbortSignal,
  ): AsyncGenerator<StreamEvent>;
  /** 评估修改效果 */
  evaluateRewrite(params: RewriteEvalParams): Promise<RewriteEvalResult>;
  /** 测试 API 连接 */
  testConnection(): Promise<{ success: boolean; error?: string }>;
  /** 获取基础 URL */
  getBaseUrl(): string;
  /** 获取 API Key */
  getApiKey(): string;
  /** 更新配置 */
  updateConfig(config: unknown): void;
}

/** 网关配置 */
export interface GatewayConfig {
  /** 最大并发请求数 */
  maxConcurrency: number;
  /** 最大重试次数 */
  maxRetries: number;
  /** 重试基础延迟（毫秒） */
  retryDelayMs: number;
  /** 请求超时时间（毫秒） */
  requestTimeoutMs: number;
  /** 缓存最大条目数 */
  cacheMaxEntries: number;
}

/** 默认网关配置 */
export const DEFAULT_GATEWAY_CONFIG: GatewayConfig = {
  maxConcurrency: 3,
  maxRetries: 1,
  retryDelayMs: 1000,
  requestTimeoutMs: 30000,
  cacheMaxEntries: 100,
};
