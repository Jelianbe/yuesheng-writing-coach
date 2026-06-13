# 月笙写作教练 — 综合数据流向概览

> 创建日期：2026-06-13 | 基于代码实际状态测绘 | 补充 `data-flow-diagram.md` 的六维数据

---

## 目录

1. [请求方向（Renderer → Main）](#1-请求方向renderer--main)
2. [响应方向（Main → Renderer）](#2-响应方向main--renderer)
3. [事件推送方向（Main → Renderer）](#3-事件推送方向main--renderer)
4. [持久化映射（完整版）](#4-持久化映射完整版)
5. [跨模块依赖图](#5-跨模块依赖图)
6. [错误流](#6-错误流)
7. [与 data-flow-diagram.md 的差距清单](#7-与-data-flow-diagrammd-的差距清单)
8. [两套 IPC 调用方式并存情况](#8-两套-ipc-调用方式并存情况)

---

## 1. 请求方向（Renderer → Main）

### 1.1 架构分层

```
UI 组件 (React)
    │  useXxxStore() hooks
    ▼
Zustand Stores (src/renderer/stores/, 14 个)
    │  call 类型化 Service 或 直接 getInvoke()
    ▼
Services (src/renderer/services/, 9 个)
    │  typedInvoke<TReq, TRes>(channel, payload)
    ▼
ipc-client.ts
    │  window.electronAPI.invoke / on
    ▼
preload 桥接 (contextBridge)
    │  白名单校验
    ▼
主进程 IPC Handlers (src/main/ipc/, 9 个)
```

### 1.2 Store → Service 依赖矩阵

| Store | 文件 | 依赖 Service | 调用方式 |
|-------|------|-------------|---------|
| **chat.store** | `stores/chat.store.ts` | `chatService.send()` | 类型化 Service |
| **diag.store** | `stores/diag.store.ts` | 无 | 直接 `getInvoke()` |
| **session.store** | `stores/session.store.ts` | 无 | 直接 `getInvoke()` |
| **training.store** | `stores/training.store.ts` | 部分（actions 中直接 IPC） | 直接 `getInvoke()` |
| **teaching-state.store** | `stores/teaching-state.store.ts` | 无 | 纯状态（无 IPC） |
| **config.store** | `stores/config.store.ts` | 无 | 直接 `getInvoke()` |
| **chapter.store** | `stores/chapter.store.ts` | 无 | 直接 `getInvoke()` |
| **manuscript.store** | `stores/manuscript.store.ts` | 无 | 直接 `getInvoke()` |
| **drawer.store** | `stores/drawer.store.ts` | 无 | 纯 UI 状态 |
| **panel-session.store** | `stores/panel-session.store.ts` | 无 | 纯 UI 状态 |
| **paradigm.store** | `stores/paradigm.store.ts` | 无 | 纯 UI 状态 |
| **ui-layout.store** | `stores/ui-layout.store.ts` | 无 | 纯 UI 状态 |
| **editor.store** | `stores/editor.store.ts` | 无 | localStorage |
| **student-context.store** | `stores/student-context.store.ts` | 无 | localStorage / 直接 IPC |

### 1.3 API Contract 文件清单

`src/shared/api-contracts/` 有 12 个 contract 文件 + 1 个事件映射：

| Contract 文件 | 域 | Invoke 通道数 | Event 通道数 | 对应 Service |
|--------------|-----|--------------|-------------|-------------|
| `chat.contract.ts` | 聊天 | 2 | 3 | `chat.service.ts` |
| `diagnosis.contract.ts` | 诊断 | 4 | 1 | `diagnosis.service.ts` |
| `session.contract.ts` | 会话 | 10 | 0 | `session.service.ts` |
| `training.contract.ts` | 训练 | 8 | 0 | `training.service.ts` |
| `teaching-state.contract.ts` | 教学状态 | 5 | 1 | `teaching-state.service.ts` |
| `config.contract.ts` | 配置 | 3 | 0 | 无 |
| `evidence.contract.ts` | 证据 | 5 | 0 | 无 |
| `manuscript.contract.ts` | 作品管理 | 10 | 0 | 无 |
| `ability.contract.ts` | 能力画像 | 1 | 0 | 无 |
| `growth.contract.ts` | 成长 | 2 | 0 | 无 |
| `onboarding.contract.ts` | 新用户引导 | 1 | 0 | 无 |
| `event-map.ts` | 事件映射 | — | 8 | — |
| `base.ts` | 基础类型 | — | — | — |

### 1.4 缺失的文档化信息

- **50 个 invoke 通道的 payload 字段清单**：已定义在 `src/shared/api-contracts/*.contract.ts` 中，但 `data-flow-diagram.md` 的验证矩阵只列了类型名
- **`studentContext:load/save/toJSON`** 三个通道无 contract 文件，使用 `unknown` 类型
- **`training.actions.ts`** 绕过 `trainingService` 直接 `getInvoke(IPC_CHANNELS.TRAINING_ASSIGN)`，缺少类型安全

---

## 2. 响应方向（Main → Renderer）

### 2.1 统一错误响应格式

所有 invoke 通道通过 `createHandler` 统一包裹：

```typescript
// 成功
{ success: true, data: T }

// 失败
{ success: false, error: 'ERROR_CODE' }
// 注：create-handler.ts 中 error 字段实际就是 Error.message 字符串
```

### 2.2 响应类型检查

| 状态 | 通道数 | 说明 |
|------|--------|------|
| ✅ 类型安全 | 45/50 invoke | 有 `ApiResponse<T>` 包裹 |
| ⚠️ `unknown` | 5 个 Service 方法 | `diagnosis.service.submitRewrite()` / `getComparison()`、`teaching-state.service.update()` / `updateSummary()`、`studentContext:*` 三个通道 |

### 2.3 响应流程

```
Handler 业务逻辑
    │  return result
    ▼
createHandler 包裹
    │  { success: true, data: result }
    │  或 { success: false, error: error.message }
    ▼
Window.electronAPI.invoke 返回
    │
    ▼
typedInvoke<TReq, TRes> 解包
    │  if (result.success) return result as ApiResponse<TRes>
    │  else 上游处理错误
    ▼
Store / Service
    │  if (!res.success) throw new Error(res.error)
    │  else return res.data
```

---

## 3. 事件推送方向（Main → Renderer）

### 3.1 事件全景

| 事件通道 | 发送方 | 触发时机 | 数据形状一致性 |
|---------|--------|---------|--------------|
| `chat:stream:data` | `ChatOrchestratorService.handleStreamResponse()` | 每个 SSE chunk | ✅ 单一来源 |
| `chat:stream:end` | `ChatOrchestratorService` | 流结束 / 中断 / 异常 | ✅ 单一来源 |
| `chat:tool:executing` | `ChatOrchestratorService` | Tool call 触发 | ✅ 单一来源 |
| `diagnosis:update` | **双源**: ChatOrchestrator.\_runDiagnosis (Pipe1) + diagnosis.handler.processDiagnosisFromAI (Pipe2) | 诊断写出后 + 流结束后 | ⚠️ dedup 保证单次推送 |
| `teachingState:updated` | **3 源**: teaching-state.handler / DiagnosisMerger / TeachingStateService.downgradeSeverity | 阶段确认 / 诊断合并 / 训练降级 | 🔴 3 种不同形状 |

### 3.2 `diagnosis:update` 双源去重机制 (RP-02)

```
Pipe 1: ChatOrchestratorService._runDiagnosis()
  → markDiagnosisPushed(sessionId)   ← 记录已推送
  → webContents.send(DIAGNOSIS_UPDATE)

Pipe 2: processDiagnosisFromAI()
  → wasDiagnosisPushed(sessionId) ? 跳过 : 推送
  → webContents.send(DIAGNOSIS_UPDATE)  ← 仅当 Pipe 1 未推送
```

- 去重使用模块级 `Set<string>`
- ⚠️ 无自动清理机制，长时间运行内存累积

### 3.3 `teachingState:updated` 数据形状不一致

| 源 | 文件位置 | 数据内容 | 问题 |
|----|---------|---------|------|
| teaching-state.handler `TEACHING_STATE_CONFIRM` | `teaching-state.handler.ts:104` | `{ oldState, newState }` 对比对象 | 与其他源输出完全不同 |
| teaching-state.service `downgradeSeverity` | `teaching-state.service.ts:154` | 含派生字段 `phaseName`/`subphaseName`/`phaseProgress` | 第三形状 |
| diagnosis.handler `processDiagnosisFromAI` | `diagnosis.handler.ts:201` | `updatedState` 原始对象 | 无派生字段 |

> 🔴 **建议统一**：定义 `TeachingStateUpdatedEvent` 接口，所有 3 处源统一使用同样的数据格式。

---

## 4. 持久化映射（完整版）

### 4.1 SQLite 8 表

| 表名 | 写入方 | 读取方 | 操作类型 |
|------|--------|--------|---------|
| `sessions` | `SessionService` | `SessionService` | CRUD |
| `messages` | `SessionService` / `ChatOrchestratorService(代理)` | `SessionService` | CRUD |
| `diagnosis_results` | `DiagnosisService` | `DiagnosisService` / `StudentModelService`(聚合) / `GrowthTrendService`(聚合) / `AbilityProfileService`(聚合) | CRUD + 聚合查询 |
| `teaching_state` | `TeachingStateStore` (通过 `TeachingStateService` 代理) | `TeachingStateStore` / `TeachingStateService` | CRUD |
| `user_training_records` | `TrainingRecordService` | `TrainingRecordService` / `StudentModelService`(聚合) / `AbilityProfileService`(聚合) | CRUD |
| `evidence` | `EvidenceService` | `EvidenceService` | CRUD |
| `evidence_diagnosis_link` | `EvidenceService` | `EvidenceService` | 关联表 |
| `manuscripts` | manuscript.handler (直接 SQLite) | manuscript.handler | CRUD |
| `chapters` | manuscript.handler (直接 SQLite) | manuscript.handler | CRUD |

### 4.2 文件存储

| 存储 | 写入方 | 读取方 | 说明 |
|------|--------|--------|------|
| `api-config.json` (electron-store) | `ConfigService` | `ConfigService` | 配置持久化 |
| `resources/prompts/` | — | `PromptLoader` | Prompt 模板只读 |
| `resources/config/` (6 个 JSON) | — | `TeachingStrategyRouter` | 教学策略配置只读 |

### 4.3 跨模块写入路径（代码存在但图中缺失）

```
training.handler
  → deps.teachingStateService.downgradeSeverity()
    → store.update(sessionId, { activeProblems })
      → teaching_state 表                        ← 训练降级写入 teaching_state

ChatOrchestrator
  → deps.diagnosisDomain.processAIResponse()
    → DiagnosisMerger.merge(diagnosis)
      → TeachingStateService.update()
        → store.update()
          → teaching_state 表                    ← 诊断合并写入 teaching_state
```

### 4.4 纯计算（不写表）

| 服务 | 数据源 | 用途 |
|------|--------|------|
| `StudentModelService` | `diagnosis_results` + `user_training_records` | 跨会话学生画像 |
| `AbilityProfileService` | `diagnosis_results` + `user_training_records` | 能力画像聚合 |
| `GrowthTrendService` | 委托 `StudentModelService` | 成长趋势摘要 |

---

## 5. 跨模块依赖图

### 5.1 Handler → 服务依赖

```
Handler 层                        Domain/Service 层
───────                          ────────────────
chat.handler (71 行) ──────────→ ChatOrchestratorService
                                  │
diagnosis.handler ──────────────→ TeachingStateService
                  ──────────────→ GrowthTrendService
                  ──────────────→ DiagnosisService / EvidenceService
                  ──────────────→ DiagnosisMerger
                  ──────────────→ SessionService / ConfigService

teaching-state.handler ─────────→ TeachingStateService
                  ──────────────→ PromptBuilder

training.handler ───────────────→ TeachingStateService
                  ──────────────→ TrainingRecordService
                  ──────────────→ StudentModelService

evidence.handler ───────────────→ EvidenceService

ability-profile.handler ────────→ AbilityProfileService

config.handler ─────────────────→ ConfigService

session.handler ────────────────→ SessionService

manuscript.handler ─────────────→ Database (直接)
```

### 5.2 DI 容器依赖图谱

```
ChatOrchestratorService
  ├─ ConfigService
  ├─ SessionService
  ├─ MessageRouter
  ├─ IDiagnosisDomain (DiagnosisService + EvidenceService + DiagnosisMerger)
  ├─ IPromptDomain (PromptLoader + MemoryCapsuleService)
  ├─ IStudentDomain (StudentModelService)
  ├─ ITeachingDomain (DisputeTracker + ReflectionGate + StrategyInstructionBuilder)
  └─ db (Database)

TeachingStateService (独立, 被 3 个 Handler 注入)
  ├─ initStore(db)
  ├─ setPromptBuilder(PromptBuilder)
  └─ setMainWindow(BrowserWindow)

DiagnosisMerger
  └─ 依赖 TeachingStateService (DI 注入)
```

### 5.3 循环依赖风险评估

| 路径 | 风险等级 | 说明 |
|------|---------|------|
| `ChatOrchestratorService → IDiagnosisDomain → DiagnosisMerger → TeachingStateService` | 🟢 低 | DI 单例延迟初始化，无构造函数注入循环 |
| `diagnosis.handler → TeachingStateService + DiagnosisMerger` | 🟢 低 | 双向引用但通过 DI 容器解耦 |

---

## 6. 错误流

### 6.1 统一错误处理架构

```
┌──────────────┐     typedInvoke      ┌──────────────────┐     ipcMain.handle   ┌──────────────────┐
│  Store/Service │ ──────────────────→ │  createHandler   │ ──────────────────→ │  Handler 业务逻辑  │
│               │                     │  try {            │                     │                  │
│               │                     │    data=handler() │                     │  const result =   │
│               │                     │    return         │                     │    service.method()│
│               │                     │    {success,data} │                     │  return result    │
│               │ ←────────────────── │  } catch(e) {     │ ←───────────────── │  throw Error      │
│  {success:false│                     │    return         │                     │                  │
│   error: msg} │                     │    {success:false │                     └──────────────────┘
│               │                     │     error: msg}   │
└──────────────┘                     └──────────────────┘
```

### 6.2 跨域写入的错误处理一致性

| 写入点 | 异常处理 | 是否阻断主流程 |
|--------|---------|--------------|
| `training.handler` → `downgradeSeverity()` | `try-catch` + `console.warn` | ❌ 不阻断 |
| `diagnosis.handler` → `processAIResponse()` IPC 推送 | `try-catch` + `console.warn` | ❌ 不阻断 |
| `chat-orchestrator` → `processAIResponse()` | `try-catch` + `console.error` | ❌ 不阻断 |
| `DiagnosisMerger.merge()` | 无 try-catch | ✅ 异常向上传播 |
| `TeachingStateService.downgradeSeverity()` | `try-catch` + `console.warn` | ❌ 不阻断 |
| `createHandler` 统一包裹 | 自动 catch | ✅ 异常转为 `{success:false}` |

---

## 7. 与 data-flow-diagram.md 的差距清单

| # | 差距项 | 图中状态 | 实际状态 | 严重度 |
|---|--------|---------|---------|--------|
| 1 | `teachingState:updated` 数据形状不一致 | 未标注 | 3 种不同输出形状（对比对象 / 含派生字段 / 原始对象） | 🔴 高 |
| 2 | `training.actions.ts` 绕过类型化 Service | 未标注 | 直接 `getInvoke(IPC_CHANNELS.TRAINING_ASSIGN)` | 🟡 中 |
| 3 | `config.store` 未使用 `ConfigApi` contract | 未标注 | `config.contract.ts` 已定义但 store 未使用 | 🟢 低 |
| 4 | 5 个 `unknown` 返回类型的 Service 方法 | 未标注 | `submitRewrite` / `getComparison` / `update` / `updateSummary` / `studentContext:*` | 🟡 中 |
| 5 | `diagnosis-dedup` 无清理机制 | 未标注 | `Set<string>` `_diagnosisPushedInChat` 持续增长 | 🟢 低 |
| 6 | `DiagnosisParser` 列在 DI 服务区 | 在 L5 中与 DI 服务混排 | `DiagnosisParser` 是纯函数，不通过 DI 注册 | 🟢 低 |

---

## 8. 两套 IPC 调用方式并存情况

### 方式 A：类型化 Service + Contract（推荐）

```
chat.store → chatService.send() → typedInvoke(ChatApi.send.channel)
```

适用范围：`chat.service.ts`、`diagnosis.service.ts`、`session.service.ts`、`training.service.ts`、`teaching-state.service.ts`

优势：编译时类型安全，Channel 名由 `XxxApi.xxx.channel` 集中定义

### 方式 B：直接 `getInvoke()`（旧模式）

```
diag.store → getInvoke()(IPC_CHANNELS.EVIDENCE_GET_BY_SYNDROME, ...)
session.store → getInvoke()(IPC_CHANNELS.SESSION_LIST, ...)
config.store → getInvoke()(IPC_CHANNELS.CONFIG_GET, ...)
chapter.store → getInvoke()(IPC_CHANNELS.CHAPTER_LIST, ...)
manuscript.store → getInvoke()(IPC_CHANNELS.MANUSCRIPT_LIST, ...)
training.actions.ts → getInvoke()(IPC_CHANNELS.TRAINING_ASSIGN, ...)
```

劣势：Channel 名是字符串，请求/响应类型安全依赖手动 `as` 断言

### 改善建议

1. 将 `config.store`、`chapter.store`、`manuscript.store`、`diag.store`、`session.store` 迁移到类型化 Service
2. 为 `studentContext:*` 创建 API Contract
3. 补全 5 个 `unknown` 返回类型

---

*本文档是对 `data-flow-diagram.md` 的六维补充，不替代原有架构图。*
*测绘日期：2026-06-13 | 基于 `src/main/`、`src/renderer/`、`src/shared/` 代码实际状态*
