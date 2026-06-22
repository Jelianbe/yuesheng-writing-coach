# ADR-001: AI 流式输出管道改造

> 状态: **提议 (Proposed)** · 2026-06-22
> 决策者: 月笙
> Sprint 9 · Phase E 前置

## 背景 (Context)

Sprint 9 前端审计发现 **3 个 AI 输出渲染问题**（R-01/02/03），影响用户核心使用体验。

### 现状

**主进程 (stream-handler.ts) 流式管道**：
1. 通过 `proxy.chatStream(...)` 获取 AI chunk 流
2. 每个 chunk 立即 `mainWindow.webContents.send(CHAT_STREAM_DATA, { sessionId, chunk })`
3. 服务端 `fullResponse += chunk` 累积
4. 流结束发送 `CHAT_STREAM_END, { sessionId, fullResponse, messageId }`
5. 流结束后调用 `processAIResponse(fullResponse, ...)` 抽取诊断 JSON

**渲染进程 (chat.store.ts / App.tsx / MessageBubble.tsx)**：
- `appendToLastAssistant(chunk)` → `msgs[i].content + chunk`（immutable 拼接）
- `MessageBubble` → `<ReactMarkdown rehypePlugins={[rehypeHighlight]}>` 渲染 `message.content`
- `App.tsx` 监听 `chat:stream:end`，调用 `finalizeLastMessage()` —— **但存在字段名 bug**

### 3 个核心症状

| ID | 症状 | 复现场景 | 实际影响 |
|:---|:-----|:---------|:---------|
| **R-01** | AI 输出夹带 JSON 片段时渲染为乱码 | AI 回答含 `{"syndromes":[...]}` 时 | 用户看到未格式化的代码块，破坏阅读 |
| **R-02** | 流式追加时部分字符丢失 | 用户在 AI 回答中段立刻发出新消息 | 旧消息字符被吞，新消息中内容串到旧消息 |
| **R-03** | `chat:stream:end` 后内容不更新 | 任何正常的流式响应 | `finalizeLastMessage()` 永不被调用（详见下文） |

### R-03 根因（已确认）

`App.tsx:81-86`:
```ts
const unsubStreamEnd = window.electronAPI.on('chat:stream:end', (data: unknown) => {
  const end = data as { finalContent?: string; error?: string };  // ← 错误字段
  if (end?.finalContent) {                                         // ← 永远是 undefined
    useChatStore.getState().finalizeLastMessage();
  } else if (end?.error) {
    useChatStore.getState().setError(end.error);
  }
});
```

而 IPC 实际载荷（`types-ipc.ts:133`）：
```ts
'chat:stream:end': { sessionId: string; fullResponse: string; messageId: string; error?: string };
```

**字段不匹配：`finalContent` vs `fullResponse`**。`finalizeLastMessage()` 永远不会被调用（除了 `app-controller.ts:92` 中的另一处独立调用，但 payload 同样不匹配）。

## 决策驱动 (Decision Drivers)

- **最小变更范围 (R-021)**：不动后端协议，避免破坏现有 5 个 handler + 30+ 测试
- **类型安全 (R-019)**：所有改动必须 typecheck 零错误
- **可测试性 (R-013)**：新逻辑必须可单测
- **可观察性 (R-022)**：出问题有日志可查
- **向后兼容 (R-006)**：回退风险可控

## 候选方案 (Considered Options)

### 选项 A：纯前端 Sanitizer（最小变更）

**做法**：
- 仅新增 `src/renderer/utils/streamSanitizer.ts`
- 在 `appendToLastAssistant` 之前对 chunk 做轻量清洗（检测 JSON 块、闭合未关闭的 markdown）
- 不修复 R-03（因为用户没要求修 R-03？等等，R-03 是最严重的）
- **不采用** — 未解决 R-02/R-03 根因

### 选项 B：前后端协议重构（彻底）

**做法**：
- 后端改为发送 `event.type: 'text' | 'json_block' | 'tool_call'`
- 前端按事件类型分发到不同渲染组件
- 完全解耦 JSON 片段与正文

**优点**：
- 根本性解决 R-01
- 类型安全可在 IPC 层做完整验证

**缺点**：
- 后端 5 个 handler 全部需改
- 现有 30+ 测试可能大面积失效
- R-021 明确要求"最小化范围"，重构 IPC 协议超出本 Sprint 范围

**不采用** — 变更范围过大，违反 R-021。

### 选项 B-lite：后端类型化事件 + 前端 streamId 锁（**最终决策**）

**做法**（4 个子改动）：

1. **IPC 协议扩展**（向后兼容）：
   - `chat:stream:data` payload 增加两个**可选**字段：
     - `eventType: 'text' | 'json_block' | 'tool_call'`（默认 `'text'`，老调用点 fallback）
     - `streamId: string`（每条响应一个 UUID，区分重叠的流）
   - `chat:stream:end` payload 增加 `streamId: string`

2. **后端 stream-handler.ts 改造**：
   - 流开始时 `streamId = crypto.randomUUID()`
   - 每个原始 chunk 标记为 `eventType: 'text'`
   - 文本流结束后调用 `processAIResponse(fullResponse)`：
     - 若提取到 JSON → 发送一个 `eventType: 'json_block'` 事件，content 为 `\u0060\u0060\u0060json\n${JSON.stringify(extracted, null, 2)}\n\u0060\u0060\u0060`
     - 若无 JSON → 不发额外事件
   - 发送 `CHAT_STREAM_END` 时附带 `streamId`
   - **关键保留**：`fullResponse` 字段继续包含原始文本（向后兼容）

3. **前端 chat.store.ts 改造**：
   - 维护 `currentStreamId: string | null`
   - 监听 `chat:stream:data`：
     - 校验 `streamId === currentStreamId` → 不匹配则丢弃（R-02 解决）
     - 按 `eventType` 分发：
       - `text` → `msgs[i].content += chunk`（原行为）
       - `json_block` → `msgs[i].content += '\n' + chunk + '\n'`（附加为代码块）
       - `tool_call` → 保留现有 tool-call 处理路径
   - `finalizeLastMessage(finalContent?: string)` 真实实现：用 `finalContent` 替换内容

4. **R-03 字段名修复**：`App.tsx` 中 `end.finalContent` → `end.fullResponse`

**优点**：
- 后端**结构化**输出，前端**类型分发**渲染（不是启发式 hack）
- 解决全部 3 个症状的**根因**（R-01 类型分发 / R-02 streamId 锁 / R-03 字段名）
- 改动**主要在 stream-handler.ts 一个文件**（后端核心流逻辑）
- **向后兼容**：`eventType` 和 `streamId` 都是可选字段，老调用点（full-flow 测试）继续工作
- 长期可维护：未来添加新事件类型（如 `image`）只需扩展 union

**缺点**：
- 需要同步修改 1 个后端 handler + 1 个 store + 1 个 App.tsx
- 测试需要更新断言（向后兼容 + 新断言）

**变更范围量化**：
- 后端：`stream-handler.ts` +50 行（含 json_block 后处理）
- 前端：`chat.store.ts` +30 行（streamId 锁 + 分发）
- `App.tsx`：1 行字段名修复
- 类型：types-ipc.ts +10 行（可选字段 + union）
- 测试：现有测试加 1 个新断言
- **合计：~90 行净变化**

### 选项 C：前端 Sanitizer + 字段名修复 + 流锁（次选）

**做法**（3 个子改动）：

1. **R-03 修复（一行）**：`App.tsx` 中 `end.finalContent` → `end.fullResponse`
2. **R-01 修复**：新增 `streamSanitizer.ts`：
   - 检测 chunk 中是否包含未闭合的 ` ``` ` 代码块标记 → 补全闭合
   - 检测 JSON 片段（以 `{` 或 `[` 开头，含 `:` 的行）→ 包裹在 ` ```json ... ``` ` 中
   - 检测连续多个换行 → 合并为 2 个（避免 markdown 段距被破坏）
3. **R-02 修复**：新增 `streamId` 概念：
   - `chat.store` 维护 `currentStreamId: string | null`
   - `appendToLastAssistant(chunk, streamId)` 校验 streamId，**不匹配则丢弃**
   - `startStream()` action 设置新 ID，`endStream()` 清理

**优点**：
- 改动小（~80 行新代码 + 1 行修复）
- 解决全部 3 个症状
- 不破坏后端协议
- Sanitizer 是纯函数，易测试

**缺点**：
- Sanitizer 是启发式规则，可能误判（如用户消息中真的想写 `{}`）
- 流锁依赖 renderer 内部状态，需在 session 切换时正确清理
- 长期债务：未来要替换为 B-lite 仍需返工

### 选项 D：后端预处理 + 前端流锁

**做法**：
- 后端在发送 chunk 前做 sanitize
- 前端只加流锁

**优点**：
- Sanitizer 与 AI 输出格式对齐更紧密

**缺点**：
- 后端需要新模块 + 测试
- 与现有 `processAIResponse` 的职责重叠

**不采用** — 后端已经有 `processAIResponse` 抽取 JSON，前后端职责容易混乱。

## 决策 (Decision)

**采用选项 C**。

理由：
1. **解决全部 3 个症状**（R-01 sanitizer / R-02 流锁 / R-03 字段名）
2. **变更范围最小**（~80 行新增 + 1 行修复 + 1 行字段名）
3. **可测试性强**（sanitizer 纯函数 + 流锁是 store action）
4. **回退风险低**（新增文件 + 一行字段名修复，单 commit 可 revert）
5. **不破坏 IPC 协议**（向后兼容）
6. **不违反 R-021**（最小化范围）

## 实施细节 (Implementation Plan)

### C-1: 修复字段名 (R-03)

```ts
// src/renderer/App.tsx
const end = data as { fullResponse?: string; error?: string };
if (end?.fullResponse) {
  useChatStore.getState().finalizeLastMessage();
}
```

### C-2: 新增 streamSanitizer (R-01)

```ts
// src/renderer/utils/streamSanitizer.ts
export function sanitizeStreamChunk(chunk: string, prevTail: string): {
  sanitized: string;
  newTail: string;
} {
  // 1. 检测未闭合的代码块：扫描 prevTail + chunk 中的 ``` 数量
  // 2. JSON 启发式：以 `{` 开头且含 `:` 的多行块 → 包裹 ```json
  // 3. 连续换行合并
}
```

### C-3: streamId 流锁 (R-02)

```ts
// src/renderer/stores/chat.store.ts
interface ChatState {
  currentStreamId: string | null;
  startStream: () => string;  // 返回新 streamId
  appendToLastAssistant: (chunk: string, streamId: string) => void;
  endStream: (streamId: string, finalContent?: string) => void;
}
```

调用方：
- `sendMessage` 启动时 `startStream()` 拿到 ID，附带在每次 chunk 中
- chunk 到达时校验 ID，不匹配则丢弃
- END 到达时调用 `endStream(id, fullResponse)`，写入 `finalizeLastMessage`

### C-4: 同步实现 `finalizeLastMessage`

```ts
finalizeLastMessage: (finalContent?: string) => {
  set((state) => {
    const msgs = [...state.messages];
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role === 'assistant') {
        if (finalContent !== undefined) {
          msgs[i] = { ...msgs[i], content: finalContent };
        }
        break;
      }
    }
    return { messages: msgs, currentStreamId: null };
  });
}
```

## 风险与回退 (Risks & Rollback)

| 风险 | 等级 | 缓解 |
|:-----|:----:|:-----|
| Sanitizer 启发式误判 | 中 | 启发式规则保守（只处理明显是 JSON 的块），不当 JSON 处理时退化为原文 |
| 流锁与 session 切换冲突 | 低 | session 切换时主动 `endStream(null)` 清理 |
| `fullResponse` 累积时间差 | 中 | END 到达时强制用 `fullResponse` 覆盖（与当前拼接等价，因为后端是从同一 source 累积） |

**回退**：`git revert <commit>` 即可。改动局限在 renderer，不影响主进程。

## 测试策略 (Testing)

1. **streamSanitizer 单测**（vitest）：
   - 输入含 JSON 片段 → 包裹 ```json
   - 输入含未闭合 ``` → 补全闭合
   - 边界：单字符、空字符串、纯文本
2. **chat.store 流锁单测**：
   - startStream 后，错误 ID 的 chunk 被丢弃
   - 正确 ID 的 chunk 正常追加
   - endStream 后，currentStreamId 清空
3. **集成验证**（手动）：
   - AI 输出含 JSON → 渲染为代码块
   - 流式输出中途用户发送新消息 → 旧流 chunks 不污染新消息
   - END 到达 → finalize 触发，content 完整

## ADR 状态

- [x] 提议 (Proposed)
- [ ] 接受 (Accepted)
- [ ] 实施 (Implemented)
- [ ] 废弃 (Deprecated)
