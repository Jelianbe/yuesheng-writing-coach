import { ApiConfig } from '../renderer/shared/types';

export interface ApiChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

/** 修改评估参数 */
export interface RewriteEvalParams {
  originalText: string;
  rewrittenText: string;
  syndromeName: string;
  syndromeDesc?: string;
}

/** 修改评估结果 */
export interface RewriteEvalResult {
  improvement: '明显改善' | '略有改善' | '无明显改善';
  analysis: string;
  suggestion: string;
}

/** 修改评估输出最大 token 数（只需简短评价） */
const EVAL_MAX_TOKENS = 1024;

// ============ Tool Calling 类型定义 ============

export interface ToolFunction {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export interface ChatCompletionTool {
  type: 'function';
  function: ToolFunction;
}

export interface AccumulatedToolCall {
  id: string;
  type: 'function';
  function: {
    name: string;
    arguments: string;
  };
}

export type StreamEvent =
  | { type: 'text'; content: string }
  | { type: 'tool_calls'; toolCalls: AccumulatedToolCall[] };

/**
 * 累积 SSE 流中分 chunk 到达的 tool_calls delta
 *
 * SSE 中 tool_calls 会分多个 chunk:
 *   delta.tool_calls[0].function.name="readChapter"
 *   delta.tool_calls[0].function.arguments="{\"chap"
 *   delta.tool_calls[0].function.arguments="terId\":\"..."
 *   delta.tool_calls[1].function.name="searchKnowledge"
 *   ...
 */
export function accumulateToolCalls(
  toolCalls: AccumulatedToolCall[],
  delta: { index: number; id?: string; function?: { name?: string; arguments?: string } }
): AccumulatedToolCall[] {
  while (toolCalls.length <= delta.index) {
    toolCalls.push({ id: '', type: 'function', function: { name: '', arguments: '' } });
  }
  const current = toolCalls[delta.index];
  if (delta.id) current.id = delta.id;
  if (delta.function?.name) current.function.name += delta.function.name;
  if (delta.function?.arguments) current.function.arguments += delta.function.arguments;
  return toolCalls;
}

export class ApiProxy {
  private config: ApiConfig;

  constructor(config: ApiConfig) {
    this.config = config;
  }

  /** 暴露基础 URL 给 probeToolSupport */
  getBaseUrl(): string {
    return this.config.baseUrl.replace(/\/+$/, '');
  }

  /** 暴露 API Key 给 probeToolSupport */
  getApiKey(): string {
    return this.config.apiKey;
  }

  updateConfig(config: ApiConfig): void {
    this.config = config;
  }

  async *chatStream(
    messages: ApiChatMessage[],
    abortSignal?: AbortSignal
  ): AsyncGenerator<string> {
    const response = await fetch(`${this.config.baseUrl.replace(/\/+$/, '')}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.config.apiKey}`,
      },
      body: JSON.stringify({
        model: this.config.modelName,
        messages,
        temperature: this.config.temperature,
        max_tokens: this.config.maxTokens,
        stream: true,
      }),
      signal: abortSignal,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => 'Unknown error');
      throw new Error(`API Error: ${response.status} ${errorText}`);
    }

    const reader = response.body?.getReader();
    if (!reader) throw new Error('No response body');

    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || !trimmed.startsWith('data: ')) continue;

        const data = trimmed.slice(6);
        if (data === '[DONE]') return;

        try {
          const parsed = JSON.parse(data);
          const content = parsed.choices?.[0]?.delta?.content;
          if (content) yield content;
        } catch {
          // skip malformed chunks
        }
      }
    }
  }

  /**
   * 带工具调用的流式聊天
   *
   * 与 chatStream 的区别：
   * - 请求体中附加 tools 参数
   * - 流式解析时检测 tool_calls delta 并累积
   * - yield 两种事件：text（文本块）或 tool_calls（完整工具调用集合）
   */
  async *chatStreamWithTools(
    messages: ApiChatMessage[],
    tools: ChatCompletionTool[],
    abortSignal?: AbortSignal,
  ): AsyncGenerator<StreamEvent> {
    const response = await fetch(`${this.getBaseUrl()}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.config.apiKey}`,
      },
      body: JSON.stringify({
        model: this.config.modelName,
        messages,
        tools,
        temperature: this.config.temperature,
        max_tokens: this.config.maxTokens,
        stream: true,
      }),
      signal: abortSignal,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => 'Unknown error');
      throw new Error(`API Error: ${response.status} ${errorText}`);
    }

    const reader = response.body?.getReader();
    if (!reader) throw new Error('No response body');

    const decoder = new TextDecoder();
    let buffer = '';
    let accumulated: AccumulatedToolCall[] = [];
    let hasToolCalls = false;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || !trimmed.startsWith('data: ')) continue;

        const data = trimmed.slice(6);
        if (data === '[DONE]') break;

        try {
          const parsed = JSON.parse(data);
          const delta = parsed.choices?.[0]?.delta;
          if (!delta) continue;

          // 文本内容：如果有累积的 tool_calls 先发出去，再发文本
          if (delta.content) {
            if (hasToolCalls) {
              yield { type: 'tool_calls', toolCalls: accumulated };
              accumulated = [];
              hasToolCalls = false;
            }
            yield { type: 'text', content: delta.content };
          }

          // tool_calls delta：逐 chunk 累积
          if (delta.tool_calls) {
            for (const tcDelta of delta.tool_calls) {
              accumulated = accumulateToolCalls(accumulated, tcDelta);
              hasToolCalls = true;
            }
          }
        } catch {
          // skip malformed chunks
        }
      }
    }

    // 流结束时如有未发出的 tool_calls
    if (hasToolCalls) {
      yield { type: 'tool_calls', toolCalls: accumulated };
    }
  }

  async testConnection(): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await fetch(`${this.config.baseUrl.replace(/\/+$/, '')}/models`, {
        headers: { 'Authorization': `Bearer ${this.config.apiKey}` },
      });
      if (!response.ok) {
        return { success: false, error: `HTTP ${response.status}` };
      }
      return { success: true };
    } catch (e) {
      return { success: false, error: (e as Error).message };
    }
  }

  /**
   * 评估用户的修改效果
   * 对比原文和修改后的文本，输出改善程度、分析和建议
   */
  async evaluateRewrite(params: RewriteEvalParams): Promise<RewriteEvalResult> {
    const systemPrompt = `你是一个专业的写作教练。你的任务是对比用户修改前后的文本，评估修改效果。

## 评估标准
- 修改是否解决了症候问题（如信息倾倒、角色工具化、节奏停滞等）
- 修改是否保持了原文的合理内容
- 修改是否自然流畅

## 输出要求
请严格按照 JSON 格式输出，不要包含其他内容：
{
  "improvement": "明显改善" | "略有改善" | "无明显改善",
  "analysis": "具体分析修改前后的差异（1-2句话）",
  "suggestion": "如果还需改进，给一句话建议；如果已很好，说'继续保持'"
}`;

    const userMessage = `请评估以下修改：

症候：${params.syndromeName}${params.syndromeDesc ? `（${params.syndromeDesc}）` : ''}

原文：
"""
${params.originalText}
"""

修改后：
"""
${params.rewrittenText}
"""`;

    const response = await fetch(`${this.config.baseUrl.replace(/\/+$/, '')}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.config.apiKey}`,
      },
      body: JSON.stringify({
        model: this.config.modelName,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage },
        ],
        temperature: 0.3, // 低温度确保评估稳定
        max_tokens: EVAL_MAX_TOKENS,
        stream: false,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => 'Unknown error');
      throw new Error(`Evaluate API Error: ${response.status} ${errorText}`);
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content || '';

    // 解析 AI 输出的 JSON
    try {
      // 尝试从内容中提取 JSON（AI 可能输出 markdown 代码块包裹的 JSON）
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        return JSON.parse(jsonMatch[0]) as RewriteEvalResult;
      }
      return JSON.parse(content) as RewriteEvalResult;
    } catch {
      // 解析失败时，返回友好兜底
      return {
        improvement: '略有改善',
        analysis: 'AI 评估解析失败，请人工判断修改效果。',
        suggestion: '建议对比原文通读一遍，确认修改是否自然。',
      };
    }
  }
}
