/**
 * 跨平台 LLM 客户端 — Sprint 31
 *
 * 轻量封装，直接使用 fetch 调用 OpenAI 兼容 API（DeepSeek）。
 * 双端可用：
 *   - Electron main process（Node.js 18+ fetch）
 *   - Capacitor WebView（浏览器 fetch）
 *
 * 用法：
 *   const client = new LlmClient({ apiKey, baseUrl, modelName });
 *   const response = await client.chat([{ role: 'user', content: '你好' }]);
 *
 * 流式用法：
 *   const stream = client.chatStream([...]);
 *   for await (const chunk of stream) { ... }
 *
 * 依据: dev-docs/tasks/sprint-31-plan.md §阶段 2
 */

// ============================================================
// 类型
// ============================================================

export interface LlmClientConfig {
  apiKey: string;
  baseUrl: string;
  modelName: string;
  temperature?: number;
  maxTokens?: number;
}

export interface ChatMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface ChatCompletionChunk {
  content: string;
  finishReason: 'stop' | 'length' | null;
}

export interface ChatCompletionResult {
  content: string;
  finishReason: 'stop' | 'length' | null;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

// ============================================================
// 错误类型
// ============================================================

export class LlmError extends Error {
  constructor(
    message: string,
    public readonly status?: number,
    public readonly code?: string,
  ) {
    super(message);
    this.name = 'LlmError';
  }
}

// ============================================================
// 客户端
// ============================================================

export class LlmClient {
  private readonly config: LlmClientConfig;
  private readonly baseUrl: string;

  constructor(config: LlmClientConfig) {
    if (!config.apiKey) throw new LlmError('API Key 未配置');
    this.config = config;
    this.baseUrl = config.baseUrl.replace(/\/+$/, '');
  }

  /**
   * 非流式对话 — 获取完整回复
   */
  async chat(
    messages: ChatMessage[],
    overrides?: Partial<LlmClientConfig>,
  ): Promise<ChatCompletionResult> {
    const cfg = { ...this.config, ...overrides };
    const body = this.buildBody(messages, cfg, false);

    const response = await fetch(`${this.baseUrl}/v1/chat/completions`, {
      method: 'POST',
      headers: this.buildHeaders(cfg.apiKey),
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      throw await this.parseError(response);
    }

    const json = await response.json();
    return this.parseResponse(json);
  }

  /**
   * 流式对话 — 返回异步迭代器
   * 用法：
   *   for await (const chunk of client.chatStream([...])) {
   *     process(chunk.content);
   *   }
   */
  async *chatStream(
    messages: ChatMessage[],
    overrides?: Partial<LlmClientConfig>,
  ): AsyncGenerator<ChatCompletionChunk, ChatCompletionResult, void> {
    const cfg = { ...this.config, ...overrides };
    const body = this.buildBody(messages, cfg, true);

    const response = await fetch(`${this.baseUrl}/v1/chat/completions`, {
      method: 'POST',
      headers: this.buildHeaders(cfg.apiKey),
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      throw await this.parseError(response);
    }

    if (!response.body) {
      throw new LlmError('响应体为空，不支持流式');
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    let fullContent = '';
    let finishReason: 'stop' | 'length' | null = null;

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || !trimmed.startsWith('data: ')) continue;

          const data = trimmed.slice(6);
          if (data === '[DONE]') {
            finishReason = 'stop';
            continue;
          }

          try {
            const parsed = JSON.parse(data);
            const delta = parsed.choices?.[0]?.delta;
            const finish = parsed.choices?.[0]?.finish_reason;

            if (delta?.content) {
              fullContent += delta.content;
              yield { content: delta.content, finishReason: null };
            }

            if (finish === 'stop') finishReason = 'stop';
            else if (finish === 'length') finishReason = 'length';
          } catch {
            // 跳过无法解析的行
          }
        }
      }
    } finally {
      reader.releaseLock();
    }

    return {
      content: fullContent,
      finishReason: finishReason ?? 'stop',
    };
  }

  // ============================================================
  // 内部方法
  // ============================================================

  private buildHeaders(apiKey: string): Record<string, string> {
    return {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    };
  }

  private buildBody(
    messages: ChatMessage[],
    cfg: LlmClientConfig,
    stream: boolean,
  ): Record<string, unknown> {
    return {
      model: cfg.modelName,
      messages,
      temperature: cfg.temperature ?? 0.7,
      max_tokens: cfg.maxTokens ?? 8192,
      stream,
    };
  }

  private async parseError(response: Response): Promise<LlmError> {
    let detail = '';
    try {
      const json = await response.json();
      detail = json.error?.message ?? JSON.stringify(json);
    } catch {
      detail = response.statusText;
    }
    return new LlmError(
      `API 请求失败 (${response.status}): ${detail}`,
      response.status,
    );
  }

  private parseResponse(json: Record<string, unknown>): ChatCompletionResult {
    const choice = (json.choices as Array<Record<string, unknown>>)?.[0];
    const message = choice?.message as Record<string, unknown> | undefined;
    const usage = json.usage as Record<string, unknown> | undefined;

    return {
      content: (message?.content as string) ?? '',
      finishReason: (choice?.finish_reason as 'stop' | 'length') ?? 'stop',
      usage: usage
        ? {
            promptTokens: (usage.prompt_tokens as number) ?? 0,
            completionTokens: (usage.completion_tokens as number) ?? 0,
            totalTokens: (usage.total_tokens as number) ?? 0,
          }
        : undefined,
    };
  }
}
