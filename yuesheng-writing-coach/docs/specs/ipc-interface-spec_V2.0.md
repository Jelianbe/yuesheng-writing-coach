# IPC 接口规范 V2.0

**版本**: V2.0  
**创建日期**: 2026-06-04  
**替代**: ipc-interface-spec_V1.0.md（14 通道旧版）  
**关联**: constants.js（IPC_CHANNELS 常量定义）、preload/index.ts（白名单）

---

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
│                  │    │  = true          │    │  EvidenceHandler     │
│                  │    │                  │    │  AuthorProfileV2Hdl  │
│                  │    │                  │    │  AbilityProfileHdl   │
│                  │    │                  │    │  IntentConsistencyHdl│
│                  │    │                  │    │  SessionHandler      │
└─────────────────┘    └──────────────────┘    └──────────────────────┘
```

- **invoke/handle**: 请求-响应模式，渲染进程主动调用，主进程返回结果
- **send/on**: 事件推送模式，主进程主动推送，渲染进程监听

---

## 2. IPC 通道总表

全部 34 个 IPC 通道，定义于 [constants.js](../../src/renderer/shared/constants.js)。

### 2.1 Invoke 通道（29 个）

#### 2.1.1 配置管理（3 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 1 | `CONFIG_GET` | `config:get` | `{ key: keyof ApiConfig }` | `ApiConfig[keyof ApiConfig]` | config.handler.ts | ✅ |
| 2 | `CONFIG_SET` | `config:set` | `{ key: keyof ApiConfig; value: ApiConfig[keyof ApiConfig] }` | `void` | config.handler.ts | ✅ |
| 3 | `CONFIG_TEST_CONNECTION` | `config:testConnection` | `{ apiKey: string; baseUrl: string }` | `ConnectionTestResult` | config.handler.ts | ✅ |

#### 2.1.2 聊天系统（1 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 4 | `CHAT_SEND` | `chat:send` | `{ message: string; sessionId: string; history?: {role,content}[]; attitudeLevel?: AttitudeLevel }` | `{ success: boolean; messageId?: string; error?: string }` | chat.handler.ts | ✅ |

#### 2.1.3 会话管理（5 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 5 | `SESSION_LIST` | `session:list` | 无 | `SessionInfo[]` | session.handler.ts | ✅ |
| 6 | `SESSION_CREATE` | `session:create` | 无 | `SessionInfo` | session.handler.ts | ✅ |
| 7 | `SESSION_DELETE` | `session:delete` | `{ sessionId: string }` | `void` | session.handler.ts | ✅ |
| 8 | `SESSION_RENAME` | `session:rename` | `{ sessionId: string; title: string }` | `void` | session.handler.ts | ✅ |
| 9 | `SESSION_GET_MESSAGES` | `session:getMessages` | `{ sessionId: string }` | `Message[]` | session.handler.ts | ✅ |

#### 2.1.4 诊断系统（3 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 10 | `DIAGNOSIS_QUERY` | `diagnosis:query` | `{ sessionId: string }` | `ActiveProblem[] \| null` | diagnosis.handler.ts | ✅ |
| 11 | `DIAGNOSIS_SUBMIT_REWRITE` | `diagnosis:submitRewrite` | `{ sessionId, messageId, syndromeId, originalText, rewrittenText, syndromeName?, syndromeDesc? }` | `{ success: boolean; evaluation?: RewriteEvaluation; error?: string }` | diagnosis.handler.ts | ✅ |
| 12 | `DIAGNOSIS_GET_COMPARISON` | `diagnosis:getComparison` | `{ sessionId: string }` | `{ hasHistory: boolean; comparison?: string }` | diagnosis.handler.ts | ✅ |

#### 2.1.5 教学状态机（5 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 13 | `TEACHING_STATE_GET` | `teachingState:get` | `{ sessionId: string }` | `TeachingState + { phaseName, subphaseName, phaseProgress }` | teaching-state.handler.ts | ✅ |
| 14 | `TEACHING_STATE_UPDATE` | `teachingState:update` | `{ sessionId: string; updates: Partial<TeachingState> }` | `TeachingState \| null` | teaching-state.handler.ts | ✅ |
| 15 | `TEACHING_STATE_CONFIRM` | `teachingState:confirm` | `{ sessionId: string }` | `{ oldState: TeachingState; newState: TeachingState } \| null` | teaching-state.handler.ts | ✅ |
| 16 | `TEACHING_STATE_GET_PROMPT` | `teachingState:getPrompt` | `{ sessionId: string }` | `string` | teaching-state.handler.ts | ✅ |
| 17 | `TEACHING_STATE_UPDATE_SUMMARY` | `teachingState:updateSummary` | `{ sessionId: string; newContent: string }` | `TeachingState \| null` | teaching-state.handler.ts | ✅ |

#### 2.1.6 能力画像（1 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 18 | `ABILITY_GET_PROFILE` | `ability:getProfile` | `{ sessionId: string }` | `AbilityProfile \| null` | ability-profile.handler.ts | ✅ |

#### 2.1.7 证据管理（4 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 19 | `EVIDENCE_GET_BY_DISEASE` | `evidence:getByDisease` | `{ diseaseId: string; novelId?: string; minLevel?: number }` | `EvidenceRecord[]` | evidence.handler.ts | ✅ |
| 20 | `EVIDENCE_GET_BY_ABILITY` | `evidence:getByAbility` | `{ abilityId: string; authorId?: string; fromDate?: string; toDate?: string }` | `EvidenceRecord[]` | evidence.handler.ts | ✅ |
| 21 | `EVIDENCE_GET_CHAIN` | `evidence:getChain` | `{ diagnosisId: string }` | `EvidenceChain \| null` | evidence.handler.ts | ✅ |
| 22 | `EVIDENCE_CREATE` | `evidence:create` | `{ evidence: Omit<EvidenceRecord, 'evidenceId'|'createdAt'> }` | `{ success: boolean; evidenceId?: string; error?: string }` | evidence.handler.ts | ✅ |

#### 2.1.8 意图-执行一致性（2 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 23 | `INTENT_CONSISTENCY_GET` | `intentConsistency:get` | `{ sessionId: string }` | `{ authorIntent, consistencyHistory, diagnosisRound } \| null` | diagnosis.handler.ts | ✅ |
| 24 | `INTENT_CONSISTENCY_CALCULATE` | `intentConsistency:calculate` | `{ sessionId: string; intentText: string; executionText: string }` | `IntentConsistencyResult` | diagnosis.handler.ts | ✅ |

#### 2.1.9 作者画像 V2（5 通道）

| # | 通道常量 | 通道名 | 请求参数 | 响应类型 | Handler 文件 | Preload |
|---|---------|--------|---------|---------|-------------|:-------:|
| 25 | `AUTHOR_PROFILE_GET` | `authorProfile:get` | `{ sessionId: string }` | `AuthorProfileV2 \| null` | author-profile-v2.handler.ts | ✅ |
| 26 | `AUTHOR_PROFILE_GET_ABILITY` | `authorProfile:getAbility` | `{ sessionId: string; abilityId: string }` | `AbilityScore \| null` | author-profile-v2.handler.ts | ✅ |
| 27 | `AUTHOR_PROFILE_GET_TRAJECTORY` | `authorProfile:getTrajectory` | `{ sessionId: string }` | `TrajectoryPoint[]` | author-profile-v2.handler.ts | ✅ |
| 28 | `AUTHOR_PROFILE_GET_CHAIN` | `authorProfile:getChain` | `{ sessionId: string }` | `EvidenceChain \| null` | author-profile-v2.handler.ts | ✅ |
| 29 | `AUTHOR_PROFILE_GET_VISUALIZATION` | `authorProfile:getVisualization` | `{ sessionId: string }` | `VisualizationData` | author-profile-v2.handler.ts | ✅ |

### 2.2 Event 通道（5 个，主进程 → 渲染进程推送）

| # | 通道常量 | 通道名 | 推送方 | 推送数据类型 | 监听方 | Preload |
|---|---------|--------|--------|-------------|--------|:-------:|
| 30 | `DIAGNOSIS_UPDATE` | `diagnosis:update` | diagnosis.handler.ts | `DiagnosisEntry` | App.tsx | ✅ |
| 31 | `TEACHING_STATE_UPDATED` | `teachingState:updated` | teaching-state.handler.ts | `TeachingState + { phaseName, subphaseName, phaseProgress }` | TeachingProgressPanel | ✅ |
| 32 | `CHAT_STREAM_DATA` | `chat:stream:data` | chat.handler.ts | `{ sessionId: string; chunk: string }` | App.tsx | ✅ |
| 33 | `CHAT_STREAM_END` | `chat:stream:end` | chat.handler.ts | `{ sessionId: string; fullResponse: string; messageId: string; error?: string }` | App.tsx | ✅ |

---

## 3. Preload 白名单

文件: [preload/index.ts](../../src/preload/index.ts)

### invoke 白名单（29 个）

```typescript
const allowedChannels = [
  // 配置管理
  'config:get',
  'config:set',
  'config:testConnection',
  // 诊断系统
  'diagnosis:query',
  'diagnosis:submitRewrite',
  'diagnosis:getComparison',
  // 教学状态机
  'teachingState:get',
  'teachingState:update',
  'teachingState:confirm',
  'teachingState:getPrompt',
  'teachingState:updateSummary',
  // 能力画像
  'ability:getProfile',
  // 聊天系统
  'chat:send',
  // 会话管理
  'session:list',
  'session:create',
  'session:delete',
  'session:rename',
  'session:getMessages',
  // 证据管理
  'evidence:getByDisease',
  'evidence:getByAbility',
  'evidence:getChain',
  'evidence:create',
  // 作者画像 V2
  'authorProfile:get',
  'authorProfile:getAbility',
  'authorProfile:getTrajectory',
  'authorProfile:getChain',
  'authorProfile:getVisualization',
  // 意图-执行一致性
  'intentConsistency:get',
  'intentConsistency:calculate',
];
```

### event 白名单（4 个）

```typescript
const allowedEvents = [
  'diagnosis:update',
  'teachingState:updated',
  'chat:stream:data',
  'chat:stream:end',
];
```

---

## 4. 前端接入状态

### 4.1 ✅ 已完整接入前端

| 模块 | 通道 | 前端组件 | 状态 |
|------|------|---------|------|
| 配置管理 | `config:get/set/testConnection` | ApiConfig.tsx | ✅ |
| 聊天系统 | `chat:send` + 2 event | App.tsx + MessageList | ✅ |
| 会话管理 | `session:list/create/delete/rename/getMessages` | AppSidebar.tsx + App.tsx | ✅ |
| 教学状态 | `teachingState:get/update/confirm/getPrompt` + event | TeachingProgress.tsx | ✅ |
| 诊断推送 | `diagnosis:update` event | App.tsx + DiagnosisCard | ✅ |

### 4.2 🟡 后端已就绪，前端待接入

| 模块 | 通道 | 说明 | 接入任务 |
|------|------|------|---------|
| 诊断改写 | `diagnosis:submitRewrite` | Handler ✅ + Preload ✅ | M-2 修改原文入口 |
| 诊断对比 | `diagnosis:getComparison` | Handler ✅ + Preload ✅ | M-4 一句话成长记录 |
| 作者画像 | `authorProfile:get` + `getVisualization` | Handler ✅ + Preload ✅ | V1.1 能力画像文字版 |
| 意图一致性 | `intentConsistency:get/calculate` | Handler ✅ + Preload ✅ | V1.1-9 集成 |

### 4.3 🔴 后端已就绪，前端完全未接入

| 模块 | 通道 | 说明 | 计划阶段 |
|------|------|------|---------|
| 能力画像 | `ability:getProfile` | Handler ✅ | V2 雷达图 |
| 证据管理 | 4 个通道 | Handler ✅ | 系统内部使用，不直接暴露前端 |
| 作者画像 | `getAbility/getTrajectory/getChain` | Handler ✅ | V2 |

---

## 5. 新增 IPC 通道流程

如需新增一个 IPC 通道，按以下顺序操作：

1. **constants.js 常量** — 在 [constants.js](../../src/renderer/shared/constants.js) 的 `IPC_CHANNELS` 中添加常量
2. **类型映射** — 在 `shared/types.ts` 的 `IPCRequestMap` / `IPCResponseMap` / `IPCEventMap` 中添加类型
3. **Preload 白名单** — 在 [preload/index.ts](../../src/preload/index.ts) 的 `allowedChannels` 或 `allowedEvents` 中添加
4. **Handler 注册** — 在对应的 handler 文件中使用 `IPC_CHANNELS.XXX` 注册
5. **文档更新** — 更新本规范文档的通道总表

---

## 6. 版本记录

| 版本 | 日期 | 变更说明 |
|------|------|---------|
| V1.0 | 2026-06-01 | 初始规范，14 通道 |
| V2.0 | 2026-06-04 | 扩展到 34 通道，按模块分类，新增前端接入状态验证 |
