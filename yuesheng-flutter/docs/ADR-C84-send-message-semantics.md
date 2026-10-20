# ADR-C84：消息发送逻辑——发送即上屏 + 输入框立即清空

- 状态：已实施（2026-09-08）
- 范围：chat_service / chat_teaching（对话页发送链路）/ session_repository
- 决策人：舰长（用户）指定方向

## 背景

用户反馈两个问题：
1. **发送语义不符合主流 AI 对话**：当前「编辑 → 发送 → 消息存在输入栏中，等待 AI 回复后才执行类似发送逻辑」——体感是消息没发出去。
2. **内容崩溃概率偏高**：AI 回复内容失效、输出失败、发送失败等。

## 根因（已查证）

| # | 现象 | 根因 |
|:--|:--|:--|
| 1 | 消息「存在输入栏中」 | `_handleSend` 的 `setState(() => _inputText = '')` 在 `await sendMessage` **之后**——流式期间输入框一直保留消息（LLM 流式最长 180s） |
| 2 | 消息「等 AI 回复才发送」 | 用户消息**已落库**（`_loadSessionContext` 步骤 1 `addMessage`），但 **UI 列表不上屏**——`onComplete`（AI 回复完成）才 `setMessages(listMessages)` 整表刷新。流式中断/失败时用户消息在 UI **永不出现** → 「消息似乎没发出去」 |
| 3 | 崩溃体感偏高 | error_logs 表 15 条全为 Zone mismatch（调试环境噪声），**生产错误无留痕**；流式中断/解析失败多静默降级，用户只看到「没回复」 |

## 决策

### 1. 用户消息落库即上屏（核心）

- `SessionRepository.getMessage(id)`：按 id 查单条消息（新增）。
- `SendMessageCallbacks.onUserMessagePersisted(Message)`：新回调（可选）。
- `chat_service`：`_LoadedContext`/`_SendContext` 透传 `userMessageId`；`_assembleSendContext` 落库后由 `_sendMessageCore` 查回完整 Message 触发回调（拆出 `_notifyUserMessagePersisted` helper，R-019 50 行内）。
- `chat_teaching`：回调中 `chatStore.addMessage(message)` **立即上屏**。
- **副作用（修复）**：发送失败/流式中断时，用户消息也已上屏——失败标记（setError 的 failedMessageIds）落在可见消息上。

### 2. 发送即清空输入栏

- `_handleSend` 在调用 `sendMessage` **前** `setState(() => _inputText = '')`（移除末尾延迟清空）。

### 3. 不做

- 列表自动滚动到底：既有已知问题（独立处理，不在本 ADR）。
- writing_coach_panel 发送入口：已有独立的内存上屏实现（行为已符合），未报问题不动（R-010）。

## 验证

- 服务层新增 2 用例（#8 落库即触发回调 + Message 正确；#9 LLM 失败时仍触发）。
- 模拟器实测（app-debug.apk）：
  - 发送 `tell_me_about_diagnosis` 后 **LLM 流式进行中**（停止键 + 「正在思考...」）用户消息**已上屏**、输入框**已清空**（截图 s8/s9）。
  - DB 确认 user 消息落库、assistant 消息正常。
- 全量 `+2579 All tests passed`；六道门禁全绿。

## 后续建议（未实施）

- 流式/解析失败留痕：`_handleSendError` 走 `captureError` 落库（当前错误只弹 UI 不落库），使「崩溃概率」可度量。
- 列表自动滚动到底（发送后 scrollTo bottom）。
