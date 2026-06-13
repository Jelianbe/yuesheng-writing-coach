# Function Calling (Tool Use) 集成方案 — V2

> V2 迭代：保留原有流式入口不重写、增加精确 chunk 累积器、test-call 探测兼容性、工具调用状态改为必选

## 概述

用标准的 OpenAI Function Calling 方案替换当前的「应用层正则替换章节 ID」做法，让 AI 自主决定何时读取章节、搜索知识库或调用其他工具。

V2 核心原则：**不破坏已有流式稳定性**，所有改动以新增代码为主。

---

## 一、总体架构

```
用户: "帮我看看昨天写的第六章"
  ↓
handleStreamResponseWithTools (新入口)
  ↓ 发送 messages + tools 到 API（流式）
API 返回: tool_calls → readChapter({titleHint: "第六章"})
  ↓ 执行工具、结果转为 tool message
API 第二次调用: messages + tool_result（流式）
  ↓
最终文本流式吐给前端
```

关键变更：不修改 `handleStreamResponse`，新增 `handleStreamResponseWithTools`。两个入口由调度层根据模型兼容性选择。

---

## 二、SSE 流中 tool_calls 的精确累积实现

这是最大技术难点。OpenAI/DeepSeek 的 tool_calls 在 SSE 中分多个 chunk：

```json
// chunk 1: delta.tool_calls[0].index=0, delta.tool_calls[0].function.name="readChapter"
// chunk 2: delta.tool_calls[0].index=0, delta.tool_calls[0].function.arguments="{\"chap"
// chunk 3: delta.tool_calls[0].index=0, delta.tool_calls[0].function.arguments="terId\":\""
// chunk 4: delta.tool_calls[0].index=0, delta.tool_calls[0].function.arguments="abc123\"}"
// chunk 5: delta.tool_calls[1].index=1, delta.tool_calls[1].function.name="searchKnowledge"
// ...
```

**累积器实现**：

```typescript
interface AccumulatedToolCall {
  id: string;
  type: 'function';
  function: {
    name: string;
    arguments: string; // 逐 chunk 追加
  };
}

function accumulateToolCalls(
  toolCalls: AccumulatedToolCall[],
  delta: { index: number; id?: string; function?: { name?: string; arguments?: string } }
): AccumulatedToolCall[] {
  // 确保数组长度足够
  while (toolCalls.length <= delta.index) {
    toolCalls.push({
      id: '',
      type: 'function',
      function: { name: '', arguments: '' },
    });
  }

  const current = toolCalls[delta.index];

  if (delta.id) {
    current.id = delta.id;
  }
  if (delta.function?.name) {
    current.function.name += delta.function.name;
  }
  if (delta.function?.arguments) {
    current.function.arguments += delta.function.arguments;
  }

  return toolCalls;
}
```

---

## 三、文件修改清单

### 1. `src/main/api-proxy.ts` — 新增 `chatStreamWithTools` 方法

```typescript
interface StreamChunk {
  type: 'text';
  content: string;
}

interface StreamToolCall {
  type: 'tool_calls';
  toolCalls: AccumulatedToolCall[];
}

type StreamEvent = StreamChunk | StreamToolCall;

async *chatStreamWithTools(
  messages: ApiChatMessage[],
  tools: ChatCompletionTool[],
  abortSignal?: AbortSignal,
): AsyncGenerator<StreamEvent> {
  const response = await fetch(`${this.config.baseUrl}/chat/completions`, {
    method: 'POST',
    headers: { /* same as chatStream */ },
    body: JSON.stringify({
      model: this.config.modelName,
      messages,
      tools,                    // <-- 新增
      temperature: this.config.temperature,
      max_tokens: this.config.maxTokens,
      stream: true,
    }),
    signal: abortSignal,
  });

  // TODO: 错误处理同 chatStream

  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let accumulatedToolCalls: AccumulatedToolCall[] = [];
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

        if (delta.content) {
          // 如果前面累积了 tool_calls，先把 tool_calls 发出去
          if (hasToolCalls) {
            yield { type: 'tool_calls', toolCalls: accumulatedToolCalls };
            accumulatedToolCalls = [];
            hasToolCalls = false;
          }
          yield { type: 'text', content: delta.content };
        }

        if (delta.tool_calls) {
          for (const tcDelta of delta.tool_calls) {
            accumulatedToolCalls = accumulateToolCalls(accumulatedToolCalls, tcDelta);
            hasToolCalls = true;
          }
        }
      } catch { /* skip malformed */ }
    }
  }

  // 流结束时如果还有未发出的 tool_calls
  if (hasToolCalls) {
    yield { type: 'tool_calls', toolCalls: accumulatedToolCalls };
  }
}
```

### 2. `src/main/ipc/chat.handler.ts` — 新增 `chatStreamWithTools` 方法

**注意**：⚠️ 不要修改 `handleStreamResponse`，而是新增独立的 `handleStreamResponseWithTools`：

```typescript
// ============ 工具调用处理（新增） ============

interface ToolCall {
  id: string;
  type: 'function';
  function: { name: string; arguments: string };
}

const MAX_TOOL_ROUNDS = 3;

const toolHandlers: Record<string, (args: unknown) => Promise<unknown>> = {
  readChapter: async (args) => {
    const { chapterId, titleHint } = args as { chapterId?: string; titleHint?: string };
    const db = deps!.db;

    if (chapterId) {
      const row = db.prepare('SELECT id, title, content FROM chapters WHERE id = ?').get(chapterId) as
        { id: string; title: string; content: string } | undefined;
      if (!row) return { error: '章节不存在', found: false };
      return { found: true, title: row.title, content: row.content, wordCount: row.content?.length ?? 0 };
    }

    if (titleHint) {
      const row = db.prepare('SELECT id, title, content FROM chapters WHERE title LIKE ? ORDER BY updated_at DESC LIMIT 1').get(`%${titleHint}%`) as
        { id: string; title: string; content: string } | undefined;
      if (!row) return { error: '未找到匹配章节', found: false };
      return { found: true, title: row.title, content: row.content, wordCount: row.content?.length ?? 0 };
    }

    const recent = db.prepare('SELECT id, title, length(content) as wordCount FROM chapters ORDER BY updated_at DESC LIMIT 5').all();
    return { found: false, recentChapters: recent, message: '未指定章节，以下是最近的 5 个章节' };
  },
};

async function handleStreamResponseWithTools(
  messages: ApiChatMessage[],
  activeSessionId: string,
  diagnosisAnalysis: DiagnosisAnalysis | null,
  isNarrative: boolean,
): Promise<{ success: boolean; messageId?: string; sessionId?: string; error?: string }> {
  const proxy = getApiProxy();
  const messageId = generateId();
  let fullResponse = '';

  currentAbortController?.abort();
  currentAbortController = new AbortController();

  const tools: ChatCompletionTool[] = [
    {
      type: 'function',
      function: {
        name: 'readChapter',
        description: '读取用户已保存的章节内容。当用户提到某个章节、作品、或要求看看/分析/读某段文字时调用。',
        parameters: {
          type: 'object',
          properties: {
            chapterId: { type: 'string', description: '章节 UUID' },
            titleHint: { type: 'string', description: '章节标题关键词，用于模糊匹配' },
          },
        },
      },
    },
  ];

  try {
    for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
      let currentRoundText = '';
      const toolCallsInRound: ToolCall[] = [];

      for await (const event of proxy.chatStreamWithTools(messages, tools, currentAbortController!.signal)) {
        if (event.type === 'text') {
          currentRoundText += event.content;
          fullResponse += event.content;
          deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
            sessionId: activeSessionId, chunk: event.content,
          });
        } else if (event.type === 'tool_calls') {
          toolCallsInRound.push(...event.toolCalls);
        }
      }

      if (toolCallsInRound.length === 0) {
        // 没有工具调用，这就是最终响应
        break;
      }

      // 前端提示工具调用
      for (const tc of toolCallsInRound) {
        deps?.mainWindow?.webContents.send('chat:tool:executing', {
          toolName: tc.function.name,
          args: tc.function.arguments,
        });
      }

      // 执行工具，将结果追加到 messages
      for (const tc of toolCallsInRound) {
        const fnName = tc.function.name;
        let args: unknown = {};
        try { args = JSON.parse(tc.function.arguments); } catch { args = {}; }

        const handler = toolHandlers[fnName];
        const result = handler ? await handler(args) : { error: `Unknown tool: ${fnName}` };

        messages.push({ role: 'assistant', content: null, tool_calls: [tc] } as any);
        messages.push({ role: 'tool', tool_call_id: tc.id, content: JSON.stringify(result) } as any);
      }

      // 如果还有工具要调用，清空当前轮文本（仅保留最终轮）
      fullResponse = fullResponse.slice(0, fullResponse.length - currentRoundText.length);
    }

    currentAbortController = null;

    deps!.sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
    deps!.sessionService.autoGenerateTitle(activeSessionId);

    try { processDiagnosisFromAI(fullResponse, activeSessionId, messageId); } catch (err) {
      console.error('[Chat] Diagnosis processing failed:', err);
    }

    deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: activeSessionId, fullResponse, messageId,
    });

    return { success: true, messageId, sessionId: activeSessionId };
  } catch (error) {
    // AbortError 和普通错误处理同 handleStreamResponse… 略（复用同一段逻辑）
    // ...
  }
}
```

### 3. `src/main/ipc/chat.handler.ts` — 调度层：选择入口

```typescript
// 在 chat:send handler 中，原本调用 handleStreamResponse 的位置改为：
const useTools = await probeToolSupport(deps!.configService.getConfig().modelName);
const result = useTools
  ? await handleStreamResponseWithTools(messages, activeSessionId, diagnosisAnalysis, isNarrative)
  : await handleStreamResponse(messages, activeSessionId, diagnosisAnalysis, isNarrative);
```

**Model 兼容性探测**（V2 改用 test call 而非字符串匹配）：

```typescript
let _toolSupportCache: boolean | null = null;

async function probeToolSupport(modelName: string): Promise<boolean> {
  if (_toolSupportCache !== null) return _toolSupportCache;

  // 已知不支持的黑名单
  const blacklist = ['llama-2', 'mixtral-8x7b']; // 根据实际使用的模型调整
  if (blacklist.some(b => modelName.toLowerCase().includes(b))) {
    _toolSupportCache = false;
    return false;
  }

  // 白名单 — 可以直接放行，不用 test call
  const whitelist = ['deepseek', 'gpt-', 'claude-'];
  if (whitelist.some(w => modelName.toLowerCase().includes(w))) {
    _toolSupportCache = true;
    return true;
  }

  // 未知模型：通过 test call 探测
  try {
    const proxy = getApiProxy();
    const testMessages = [{ role: 'user', content: 'hi' }];
    const testTools: ChatCompletionTool[] = [{
      type: 'function',
      function: {
        name: 'ping',
        description: 'ping',
        parameters: { type: 'object', properties: {} },
      },
    }];

    // 发送非流式请求，检测是否返回 tool_calls
    const response = await fetch(`${proxy.getBaseUrl()}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${proxy.getApiKey()}`,
      },
      body: JSON.stringify({
        model: modelName,
        messages: testMessages,
        tools: testTools,
        max_tokens: 10,
        stream: false,
      }),
    });

    const data = await response.json();
    _toolSupportCache = !!data.choices?.[0]?.message?.tool_calls;
  } catch {
    _toolSupportCache = false;
  }

  return _toolSupportCache;
}
```

### 4. `src/main/api-proxy.ts` — 添加 `getBaseUrl()` 和 `getApiKey()` getter

当前 `ApiProxy` 的 `config` 是私有字段，对外暴露 getter 供 `probeToolSupport` 使用。

### 5. `src/renderer/App.tsx` — 前端工具调用提示（**必选**，非可选）

```typescript
// 监听 chat:tool:executing 事件
useEffect(() => {
  const cleanup = window.electronAPI.on('chat:tool:executing', (data: unknown) => {
    const { toolName, args } = data as { toolName: string; args: string };
    // 在聊天界面底部显示工具调用状态
    setToolStatus(toolName === 'readChapter' ? '📖 正在读取章节…' : '🔍 正在搜索知识库…');
    // 3秒后自动清除
    setTimeout(() => setToolStatus(''), 3000);
  });
  return () => cleanup();
}, []);
```

---

## 四、改动汇总

| # | 文件 | 改动 | 行数 |
|---|------|------|------|
| 1 | `api-proxy.ts` | 新增 `chatStreamWithTools()` + `accumulateToolCalls()` + `getBaseUrl()`/`getApiKey()` | ~80 行 |
| 2 | `chat.handler.ts` | 新增 `handleStreamResponseWithTools` + `toolHandlers` + `probeToolSupport` | ~130 行 |
| 3 | `chat.handler.ts` | 调度层：`chat:send` handler 中增加入口选择逻辑 | ~5 行 |
| 4 | `App.tsx` | 新增 `chat:tool:executing` 监听 + 工具调用状态提示 | ~15 行 |
| **总计** | | | **~230 行** |

## 五、风险与缓解（V2 更新版）

| 风险 | 等级 | 缓解 |
|------|------|------|
| 破坏现有 `handleStreamResponse` | 🔴 已消除 | V2 不修改原有函数，新增独立入口 |
| tool_calls chunk 累积错误 | 🟡 明确实现 | V2 已给出精确的 `accumulateToolCalls` 函数 |
| 未知模型兼容性误判 | 🟡 已改进 | V2 用 test call 探测替代字符串匹配 |
| 用户感知不到工具调用 | 🟢 已解决 | V2 将前端提示改为必选项 |
| 工具调用消耗额外 Token | 🟢 可控 | MAX_TOOL_ROUNDS = 3，单次调用无额外消耗 |

## 六、实施顺序

1. `api-proxy.ts`：添加 `getBaseUrl()` / `getApiKey()` getter
2. `api-proxy.ts`：添加 `accumulateToolCalls` 函数 + `chatStreamWithTools` 方法
3. `chat.handler.ts`：添加 `toolHandlers` + `handleStreamResponseWithTools`
4. `chat.handler.ts`：添加 `probeToolSupport` + 调度入口选择
5. `App.tsx`：添加 `chat:tool:executing` 监听
6. 端到端测试

## 七、回退方案

如果 Function Calling 上线后出现问题，只需在 `chat:send` handler 中将 `useTools` 强制设为 `false`，立即回退到原有正则方案。两个流式入口共存，互不影响。
