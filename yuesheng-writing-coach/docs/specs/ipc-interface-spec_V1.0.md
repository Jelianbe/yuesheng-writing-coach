# IPC 接口规范 V1.0

## 1. 架构总览

月笙写作教练采用三层 IPC 通信架构：

```
渲染进程 (Renderer)           Preload 层                   主进程 (Main)
┌─────────────────┐    ┌──────────────────┐    ┌──────────────────────┐
│  React + Zustand │    │  contextBridge   │    │  ipcMain.handle()    │
│                  │    │  白名单过滤      │    │                      │
│  electronAPI     │◄──►│  allowedChannels │◄──►│  ChatHandler         │
│  .invoke()       │    │  allowedEvents   │    │  ConfigHandler       │
│  .on()           │    │                  │    │  DiagnosisHandler    │
│                  │    │  contextIsolation │    │  TeachingStateHandler│
│                  │    │  = true          │    │                      │
└─────────────────┘    └──────────────────┘    └──────────────────────┘
```

- **invoke/handle**: 请求-响应模式，渲染进程主动调用，主进程返回结果
- **send/on**: 事件推送模式，主进程主动推送，渲染进程监听

---

## 2. IPC 通道总表

全部 14 个 IPC 通道，定义于 [IPC_CHANNELS](../../src/renderer/shared/types.ts)。

### 2.1 Invoke 通道（请求-响应）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | 状态 |
|---|---------|--------|---------|---------|-------------|:----:|
| 1 | `CONFIG_GET` | `config:get` | `{ key: keyof ApiConfig }` | `ApiConfig[keyof ApiConfig]` | config.handler.ts | ✅ |
| 2 | `CONFIG_SET` | `config:set` | `{ key: keyof ApiConfig; value: ApiConfig[keyof ApiConfig] }` | `void` | config.handler.ts | ✅ |
| 3 | `CONFIG_TEST_CONNECTION` | `config:testConnection` | `{ apiKey: string; baseUrl: string }` | `ConnectionTestResult` | config.handler.ts | ✅ |
| 4 | `DIAGNOSIS_QUERY` | `diagnosis:query` | `{ sessionId: string }` | `ActiveProblem[] \| null` | diagnosis.handler.ts | ✅ |
| 5 | `TEACHING_STATE_GET` | `teachingState:get` | `{ sessionId: string }` | `TeachingState & { phaseName, subphaseName, phaseProgress }` | teaching-state.handler.ts | ✅ |
| 6 | `TEACHING_STATE_UPDATE` | `teachingState:update` | `{ sessionId: string; updates: Partial\<TeachingState\> }` | `TeachingState \| null` | teaching-state.handler.ts | ✅ |
| 7 | `TEACHING_STATE_CONFIRM` | `teachingState:confirm` | `{ sessionId: string }` | `{ oldState: TeachingState; newState: TeachingState } \| null` | teaching-state.handler.ts | ✅ |
| 8 | `TEACHING_STATE_GET_PROMPT` | `teachingState:getPrompt` | `{ sessionId: string }` | `string` | teaching-state.handler.ts | ✅ |
| 9 | `TEACHING_STATE_UPDATE_SUMMARY` | `teachingState:updateSummary` | `{ sessionId: string; newContent: string }` | `TeachingState \| null` | teaching-state.handler.ts | ✅ |
| 10 | `CHAT_SEND` | `chat:send` | `{ message, sessionId, history?, attitudeLevel? }` | `{ success, messageId?, error? }` | chat.handler.ts | ✅ |

### 2.2 Event 通道（推送）

| # | 通道常量 | 通道名 | 推送方 | 推送数据类型 | 监听方 | 状态 |
|---|---------|--------|--------|-------------|--------|:----:|
| 11 | `DIAGNOSIS_UPDATE` | `diagnosis:update` | diagnosis.handler.ts | `DiagnosisEntry` | App.tsx | ✅ |
| 12 | `TEACHING_STATE_UPDATED` | `teachingState:updated` | teaching-state.handler.ts | `TeachingState & { phaseName, subphaseName, phaseProgress }` | TeachingProgressPanel | ✅ |
| 13 | `CHAT_STREAM_DATA` | `chat:stream:data` | chat.handler.ts | `{ sessionId, chunk }` | App.tsx | ✅ |
| 14 | `CHAT_STREAM_END` | `chat:stream:end` | chat.handler.ts | `{ sessionId, fullResponse, messageId, error? }` | App.tsx | ✅ |

---

## 3. Preload 白名单

文件: [preload/index.ts](../../src/preload/index.ts)

所有 IPC 通道必须同时在 preload 白名单和 `IPC_CHANNELS` 常量中注册，否则渲染进程无法调用。

### invoke 白名单

```typescript
const allowedChannels = [
  'config:get',
  'config:set',
  'config:testConnection',
  'diagnosis:query',
  'teachingState:get',
  'teachingState:update',
  'teachingState:confirm',
  'teachingState:getPrompt',
  'teachingState:updateSummary',
  'chat:send',
];
```

### event 白名单

```typescript
const allowedEvents = [
  'diagnosis:update',
  'teachingState:updated',
  'chat:stream:data',
  'chat:stream:end',
];
```

---

## 4. 类型映射

所有 IPC 通道的请求/响应类型定义于 [IPCRequestMap](../../src/renderer/shared/types.ts)、[IPCResponseMap](../../src/renderer/shared/types.ts) 和 [IPCEventMap](../../src/renderer/shared/types.ts)。

### 使用方式

渲染进程调用 IPC 时，通过 `IPC_CHANNELS` 常量引用通道名：

```typescript
import { IPC_CHANNELS } from '../shared/types';

// invoke 调用
const result = await electronAPI.invoke(IPC_CHANNELS.CHAT_SEND, {
  message: '用户输入',
  sessionId: 'session-001',
  attitudeLevel: 'yuesheng',
});

// 事件监听
const cleanup = electronAPI.on(IPC_CHANNELS.CHAT_STREAM_DATA, (data) => {
  // data 类型由 IPCEventMap 约束
});
```

主进程注册 handler 时同样使用常量：

```typescript
import { IPC_CHANNELS } from '../../renderer/shared/types';

ipcMain.handle(IPC_CHANNELS.CHAT_SEND, async (_event, args) => {
  // args 类型由 IPCRequestMap 约束
});
```

---

## 5. 关键数据流

### 5.1 聊天流

```
用户输入 → ChatPage
  → chat.store.sendMessage(text)
    → 读取 configStore.attitudeLevel
    → ipcRenderer.invoke('chat:send', { message, sessionId, history, attitudeLevel })
      → chat.handler.ts
        → loadSystemPrompt(attitude) + history + user message
        → ApiProxy.chatStream(messages)
        → 循环: webContents.send('chat:stream:data', { sessionId, chunk })
          → App.tsx 监听 → chat.store.appendToLastAssistant(chunk)
        → 结束: webContents.send('chat:stream:end', { sessionId, fullResponse, messageId })
          → App.tsx 监听 → chat.store.setLoading(false)
          → (待接入 diagnosis.handler.ts processDiagnosisFromAI)
```

### 5.2 教学状态流

```
用户点击"我懂了" → TeachingProgressPanel
  → electronAPI.invoke('teachingState:confirm', { sessionId })
    → teaching-state.handler.ts
      → confirmPhaseComplete() 计算新状态
      → teachingStore.update() 持久化到 SQLite
      → webContents.send('teachingState:updated', { oldState, newState, ... })
        → TeachingProgressPanel 监听 → setCurrentState(newState)
```

### 5.3 配置流

```
用户修改配置 → ApiConfig
  → config.store.setAttitudeLevel('doubao')
    → ipcRenderer.invoke('config:set', { key: 'attitudeLevel', value: 'doubao' })
      → config.handler.ts → ConfigService.setConfigKey() → electron-store 持久化
    → config.store 状态更新 → UI 自动响应
```

---

## 6. 新增 IPC 通道流程

如需新增一个 IPC 通道，按以下顺序操作：

1. **IPC_CHANNELS 常量** — 在 [shared/types.ts](../../src/renderer/shared/types.ts) 的 `IPC_CHANNELS` 中添加常量
2. **类型映射** — 在 `IPCRequestMap` / `IPCResponseMap` / `IPCEventMap` 中添加类型
3. **Preload 白名单** — 在 [preload/index.ts](../../src/preload/index.ts) 的 `allowedChannels` 或 `allowedEvents` 中添加
4. **Handler 注册** — 在对应的 handler 文件中使用 `IPC_CHANNELS.XXX` 注册
5. **测试** — 覆盖 invoke 参数和响应

---

## 7. 版本记录

| 版本 | 日期 | 变更说明 |
|------|------|---------|
| V1.0 | 2026-06-01 | 初始规范，14 通道全覆盖，IPCRequestMap/IPCResponseMap/IPCEventMap 完整 |
