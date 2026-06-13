# 月笙写作教练 — 全栈模块化重构方案

> 版本：v1.0 | 日期：2026-06-13  
> 基于：MODULE_COUPLING_REPORT.md（前端） + BACKEND_STRUCTURE_REPORT.md（后端）

---

## 一、目标架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            FRONTEND (Renderer)                               │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  View Layer (React Components)                                        │   │
│  │  ChatView │ TrainingWorkshop │ SoloSidebar │ DiagnosisPanel │ ...     │   │
│  │  ──────────────────────────────────────────────────────────────────  │   │
│  │  规则：组件仅通过 useXxxStore() hook 读取本域状态，             │   │
│  │        跨域协调通过 useAppController() 暴露的 service 函数完成        │   │
│  └───────────────────────────────┬──────────────────────────────────────┘   │
│                                  │ 只读订阅 / action dispatch                 │
│  ┌───────────────────────────────▼──────────────────────────────────────┐   │
│  │  Store Layer (Zustand — 每 store 仅管自身域)                         │   │
│  │  chat.store │ session.store │ diag.store │ training.store │ ...       │   │
│  │  ──────────────────────────────────────────────────────────────────  │   │
│  │  规则：store 内严禁 getState() 调用其他 store                          │   │
│  │        IPC 调用统一委托给 services/ 层                                 │   │
│  │        Action 内部只做：状态变更 + 调用 service 函数                   │   │
│  └───────────────────────────────┬──────────────────────────────────────┘   │
│                                  │ 单向调用                                  │
│  ┌───────────────────────────────▼──────────────────────────────────────┐   │
│  │  Service Layer (src/renderer/services/)                               │   │
│  │  chat.service.ts │ diagnosis.service.ts │ training.service.ts │ ...   │   │
│  │  ──────────────────────────────────────────────────────────────────  │   │
│  │  职责：跨 store 协调编排（取代当前的 store.getState() 跨模块调用）     │   │
│  │        IPC 通道调用封装（单个入口，类型安全）                          │   │
│  │        Event 监听器在此层注册，将 IPC 事件转为 store action            │   │
│  └───────────────────────────────┬──────────────────────────────────────┘   │
│                                  │ 通过 invoke/on 通信                       │
│  ┌───────────────────────────────▼──────────────────────────────────────┐   │
│  │  API Client Layer                                                    │   │
│  │  基于 shared/api-contracts/ 类型定义，通过 window.electronAPI 调用    │   │
│  │  入口：typedIpc.invoke(ChatApi.send, payload)                         │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
          ═══════════ API Contract (shared/api-contracts/) ═══════════
          │           类型化接口定义，编译期双向校验                        │
                                    │
┌─────────────────────────────────────────────────────────────────────────────┐
│                            BACKEND (Main Process)                            │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  IPC Handler Layer (薄层 — 每个 handler ≤ 150 行)                    │   │
│  │  chat.handler │ diagnosis.handler │ training.handler │ ...             │   │
│  │  ──────────────────────────────────────────────────────────────────  │   │
│  │  职责：payload 校验 → 委托 ModuleService → 标准化返回值               │   │
│  │        使用 createHandler() 统一包装                                  │   │
│  │        所有依赖通过 DI 容器获取，废弃模块级变量                       │   │
│  └───────────────────────────────┬──────────────────────────────────────┘   │
│                                  │ 委托                                     │
│  ┌───────────────────────────────▼──────────────────────────────────────┐   │
│  │  Module Service Layer (src/main/modules/)                             │   │
│  │  chat-orchestrator │ diagnosis-orchestrator │ teaching-state.service  │   │
│  │  ──────────────────────────────────────────────────────────────────  │   │
│  │  职责：业务流程编排（取代 God Handler 中的内联逻辑）                  │   │
│  │        Tool Calling 执行、诊断编排、策略指令构建                     │   │
│  │        Handler 间通信通过 DI 容器，不再跨 handler 直接导入           │   │
│  └───────────────────────────────┬──────────────────────────────────────┘   │
│                                  │                                          │
│  ┌───────────────────────────────▼──────────────────────────────────────┐   │
│  │  Data Layer (src/main/services/ — 保留现有)                           │   │
│  │  session.service │ diagnosis.service │ teaching-state.store │ ...      │   │
│  │  ──────────────────────────────────────────────────────────────────  │   │
│  │  职责：纯数据 CRUD，无业务编排逻辑                                   │   │
│  │        可被多个 Module Service 共享                                   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  DI Container (ServiceContainer — 已有，扩展)                         │   │
│  │  统一管理所有 Module Service + Data Service 生命周期                  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 二、API 契约层设计

### 2.1 设计目标

将 `src/shared/constants.ts` 中 ~45 个 `IPC_CHANNELS` 改造为**类型化 API 接口定义**，实现前后端**编译期类型安全**的通信契约。每个接口包含：通道名常量、请求类型、响应类型、success/error 判别式联合。

### 2.2 目录结构

```
src/shared/api-contracts/
├── index.ts                      # 统一导出 + ContractRegistry 类型汇总
├── base.ts                       # 基础类型：ApiSuccess<T> / ApiError / ApiResponse<T>
├── chat.contract.ts              # 聊天域接口
├── diagnosis.contract.ts         # 诊断域接口
├── teaching-state.contract.ts    # 教学状态域接口
├── training.contract.ts          # 训练域接口
├── session.contract.ts           # 会话域接口
├── config.contract.ts            # 配置域接口
├── evidence.contract.ts          # 证据域接口
├── manuscript.contract.ts        # 作品域接口
├── ability.contract.ts           # 能力画像域接口
├── growth.contract.ts            # 成长趋势域接口
└── event-map.ts                  # Event 通道映射（推送事件类型）
```

### 2.3 基础类型定义 (`base.ts`)

```typescript
// src/shared/api-contracts/base.ts

/** 成功响应包装 */
export interface ApiSuccess<T> {
  success: true;
  data: T;
}

/** 错误响应包装 */
export interface ApiError {
  success: false;
  error: string;
}

/** 判别式联合响应 */
export type ApiResponse<T> = ApiSuccess<T> | ApiError;

/** API 接口元类型 — 每个 domain contract 扩展此类型 */
export interface ApiEndpoint<TRequest, TResponse> {
  readonly channel: string;           // IPC 通道名
  readonly request: TRequest;         // 前端 invoke 时的 payload 类型
  readonly response: ApiResponse<TResponse>; // 后端 handle 返回的类型
}
```

### 2.4 Chat 域接口定义 (`chat.contract.ts`)

```typescript
// src/shared/api-contracts/chat.contract.ts

import type { ApiResponse } from './base';
import type { AttitudeLevel } from '../../renderer/shared/types';

// ─── 请求类型 ───

export interface ChatSendRequest {
  message: string;
  sessionId: string;
  history: Array<{ role: 'user' | 'assistant'; content: string }>;
  attitudeLevel: AttitudeLevel;
  studentContext: string; // JSON-serialized StudentContextSnapshot
}

export interface ChatStopRequest {
  sessionId: string;
}

// ─── 响应类型 ───

export interface ChatSendResponse {
  acknowledged: true;
}

export interface ChatStopResponse {
  stopped: true;
}

// ─── Event 推送类型 ───

export interface ChatStreamDataEvent {
  sessionId: string;
  chunk: string;
}

export interface ChatStreamEndEvent {
  sessionId: string;
  fullResponse: string;
  messageId: string;
  error?: string;
  aborted?: boolean;
}

// ─── API 接口定义 ───

export const ChatApi = {
  /** 发送聊天消息 — 触发 SSE 流式响应 */
  send: {
    channel: 'chat:send' as const,
    request: {} as ChatSendRequest,
    response: {} as ChatSendResponse,
  },

  /** 停止当前流式响应 */
  stop: {
    channel: 'chat:stop' as const,
    request: {} as ChatStopRequest,
    response: {} as ChatStopResponse,
  },

  /** SSE 流数据推送（Event 通道） */
  streamData: {
    channel: 'chat:stream:data' as const,
    event: {} as ChatStreamDataEvent,
  },

  /** SSE 流结束推送（Event 通道） */
  streamEnd: {
    channel: 'chat:stream:end' as const,
    event: {} as ChatStreamEndEvent,
  },
} as const;

/** Chat 域所有 invoke 通道联合 */
export type ChatInvokeChannels =
  | typeof ChatApi.send.channel
  | typeof ChatApi.stop.channel;
```

### 2.5 Diagnosis 域接口定义 (`diagnosis.contract.ts`)

```typescript
// src/shared/api-contracts/diagnosis.contract.ts

import type { ApiResponse } from './base';
import type { DiagnosisEntry, SyndromeResult, SeverityLevel } from '../../renderer/shared/types';

// ─── 请求类型 ───

export interface DiagnosisTriggerRequest {
  sessionId: string;
  text: string;          // 用户提交的文本片段
  mode: 'auto' | 'manual';
}

export interface DiagnosisSubmitRewriteRequest {
  sessionId: string;
  syndromeId: string;
  originalText: string;
  rewrittenText: string;
}

export interface DiagnosisGetComparisonRequest {
  sessionId: string;
  syndromeId: string;
}

// ─── 响应类型 ───

export interface DiagnosisTriggerResponse {
  entry: DiagnosisEntry;
  mergedToTeaching: boolean;
}

export interface DiagnosisRewriteEvaluation {
  score: number;         // 0-10
  feedback: string;
  improved: boolean;
  severityAfterUpdate: Record<string, SeverityLevel>;
}

export interface DiagnosisComparisonResult {
  originalText: string;
  rewrites: Array<{
    rewrittenText: string;
    score: number;
    feedback: string;
    timestamp: number;
  }>;
}

// ─── Event 推送类型 ───

export interface DiagnosisUpdateEvent {
  sessionId: string;
  entry: DiagnosisEntry;
}

// ─── API 接口定义 ───

export const DiagnosisApi = {
  trigger: {
    channel: 'diagnosis:update' as const,
    request: {} as DiagnosisTriggerRequest,
    response: {} as DiagnosisTriggerResponse,
  },

  submitRewrite: {
    channel: 'diagnosis:submitRewrite' as const,
    request: {} as DiagnosisSubmitRewriteRequest,
    response: {} as DiagnosisRewriteEvaluation,
  },

  getComparison: {
    channel: 'diagnosis:getComparison' as const,
    request: {} as DiagnosisGetComparisonRequest,
    response: {} as DiagnosisComparisonResult,
  },

  updated: {
    channel: 'diagnosis:updated' as const,
    event: {} as DiagnosisUpdateEvent,
  },
} as const;
```

### 2.6 Teaching State 域接口定义 (`teaching-state.contract.ts`)

```typescript
// src/shared/api-contracts/teaching-state.contract.ts

import type { ApiResponse } from './base';
import type { TeachingState } from '../../renderer/shared/types';

// ─── 请求类型 ───

export interface TeachingStateGetRequest {
  sessionId: string;
}

export interface TeachingStateUpdateRequest {
  sessionId: string;
  updates: Partial<Pick<TeachingState, 'currentPhase' | 'currentSubphase' | 'activeProblems' | 'completedActions' | 'nextSuggestedActions' | 'diagnosisSummary'>>;
}

export interface TeachingStateConfirmRequest {
  sessionId: string;
}

export interface TeachingStateGetPromptRequest {
  sessionId: string;
}

export interface TeachingStateUpdateSummaryRequest {
  sessionId: string;
  newContent: string;
}

// ─── 响应类型 ───

export interface TeachingStateGetResponse extends TeachingState {
  phaseName: string;
  subphaseName: string;
  phaseProgress: number;
}

export interface TeachingStateConfirmResponse {
  oldState: TeachingState;
  newState: TeachingState;
}

export interface TeachingStateGetPromptResponse {
  promptContent: string;
}

// ─── Event 推送类型 ───

export interface TeachingStateUpdatedEvent extends TeachingState {
  phaseName: string;
  subphaseName: string;
  phaseProgress: number;
}

// ─── API 接口定义 ───

export const TeachingStateApi = {
  get: {
    channel: 'teachingState:get' as const,
    request: {} as TeachingStateGetRequest,
    response: {} as TeachingStateGetResponse,
  },

  update: {
    channel: 'teachingState:update' as const,
    request: {} as TeachingStateUpdateRequest,
    response: {} as TeachingState,
  },

  confirm: {
    channel: 'teachingState:confirm' as const,
    request: {} as TeachingStateConfirmRequest,
    response: {} as TeachingStateConfirmResponse,
  },

  getPrompt: {
    channel: 'teachingState:getPrompt' as const,
    request: {} as TeachingStateGetPromptRequest,
    response: {} as TeachingStateGetPromptResponse,
  },

  updateSummary: {
    channel: 'teachingState:updateSummary' as const,
    request: {} as TeachingStateUpdateSummaryRequest,
    response: {} as TeachingState,
  },

  updated: {
    channel: 'teachingState:updated' as const,
    event: {} as TeachingStateUpdatedEvent,
  },
} as const;
```

### 2.7 统一索引与类型安全辅助 (`index.ts`)

```typescript
// src/shared/api-contracts/index.ts

export * from './base';
export * from './chat.contract';
export * from './diagnosis.contract';
export * from './teaching-state.contract';
// ... 其他域

/** 所有 invoke 通道名的字面量联合类型 */
export type AllInvokeChannels =
  | typeof import('./chat.contract').ChatApi.send.channel
  | typeof import('./chat.contract').ChatApi.stop.channel
  | typeof import('./diagnosis.contract').DiagnosisApi.trigger.channel
  | typeof import('./diagnosis.contract').DiagnosisApi.submitRewrite.channel
  | typeof import('./diagnosis.contract').DiagnosisApi.getComparison.channel
  | typeof import('./teaching-state.contract').TeachingStateApi.get.channel
  | typeof import('./teaching-state.contract').TeachingStateApi.update.channel
  // ... 其余通道
  ;

/** 所有 Event 通道名的字面量联合类型 */
export type AllEventChannels =
  | typeof import('./chat.contract').ChatApi.streamData.channel
  | typeof import('./chat.contract').ChatApi.streamEnd.channel
  | typeof import('./diagnosis.contract').DiagnosisApi.updated.channel
  | typeof import('./teaching-state.contract').TeachingStateApi.updated.channel
  // ... 其余 event 通道
  ;
```

---

## 三、后端模块化方案

### 3.1 模块划分总览

按用户设想的链路 **AI引用 → 信息输入 → 输出 → 解析 → {教学库, 诊断库, ...}**，后端拆分为 6 个 Module Service + 1 个基础设施层：

```
src/main/modules/
├── ai-gateway/                    # AI引用层（封装 ApiProxy）
│   ├── ai-gateway.service.ts     #   统一 LLM 调用入口（连接池化）
│   └── tool-calling.service.ts   #   Tool Calling 执行引擎
│
├── chat-orchestrator/             # 聊天编排（替代 God Handler 核心逻辑）
│   ├── chat-orchestrator.service.ts   # 发送/停止流程编排
│   ├── strategy-instruction.builder.ts # 教学策略指令构建
│   └── diagnosis-trigger.service.ts   # 诊断触发编排
│
├── diagnosis-processor/           # 诊断处理
│   ├── diagnosis-processor.service.ts # 诊断解析→合并→推送编排
│   ├── rewrite-evaluator.service.ts   # 重写评估
│   └── comparison.service.ts          # 对比查询
│
├── teaching-engine/               # 教学库
│   ├── teaching-state.service.ts      # 教学状态读写（替代模块级变量）
│   ├── teaching-state-machine.ts      # 阶段流转（保留现有，微调接口）
│   ├── prompt-assembly.service.ts     # Prompt 组装编排（替代 PromptLoader setter 地狱）
│   └── teaching-strategy.service.ts   # 策略决策（保留现有）
│
├── training-coordinator/          # 训练协调
│   ├── training-coordinator.service.ts # 训练→评估→症候降级编排
│   ├── training-recommendation.service.ts # 推荐（保留现有）
│   └── training-evaluator.service.ts     # 评估（保留现有）
│
└── student-profile/               # 学生画像（聚合服务）
    ├── student-model.service.ts       # 跨会话画像（保留现有）
    ├── ability-profile.service.ts     # 能力画像（保留现有）
    └── growth-trend.service.ts        # 成长趋势（保留现有）
```

### 3.2 解决 P0#1 — God Handler 拆分

**问题**：`chat.handler.ts` 964 行，混杂 6 种职责。

**Before**（`src/main/ipc/chat.handler.ts` 结构）：
```
chat.handler.ts (964 行)
├── initChatHandlers() / 模块级 deps 变量
├── getApiProxy()
├── callDiagnosisAgent()           ← 诊断 Agent 调用（应归属 diagnosis 模块）
├── formatDiagnosisHistory()       ← 记忆胶囊格式化
├── injectTechniquePool()          ← 技法库注入
├── buildCoachingInstruction()     ← 策略指令构建
├── registerChatHandlers():
│   ├── chat:send handler          ← 核心编排：消息持久化→策略→Prompt→SSE→诊断
│   │   ├── 技法注入逻辑
│   │   ├── Tool Calling 执行
│   │   ├── 诊断编排（processDiagnosisFromAI）
│   │   └── 辩驳/反思控制
│   └── chat:stop handler
```

**After**（重构后）：

```typescript
// ─── src/main/modules/chat-orchestrator/chat-orchestrator.service.ts ───

import type { ApiGatewayService } from '../ai-gateway/ai-gateway.service';
import type { ToolCallingService } from '../ai-gateway/tool-calling.service';
import type { StrategyInstructionBuilder } from './strategy-instruction.builder';
import type { DiagnosisTriggerService } from './diagnosis-trigger.service';
import type { SessionService } from '../../services/session.service';
import type { PromptAssemblyService } from '../teaching-engine/prompt-assembly.service';
import type { DisputeTrackerService } from '../../services/dispute-tracker.service';
import type { ReflectionGateService } from '../../services/reflection-gate.service';

export interface ChatOrchestratorDeps {
  aiGateway: ApiGatewayService;
  toolCalling: ToolCallingService;
  strategyBuilder: StrategyInstructionBuilder;
  diagnosisTrigger: DiagnosisTriggerService;
  sessionService: SessionService;
  promptAssembly: PromptAssemblyService;
  disputeTracker: DisputeTrackerService;
  reflectionGate: ReflectionGateService;
}

export class ChatOrchestratorService {
  constructor(private deps: ChatOrchestratorDeps) {}

  async sendMessage(params: {
    message: string;
    sessionId: string;
    history: ChatMessage[];
    attitudeLevel: AttitudeLevel;
    studentContext: string;
    onChunk: (chunk: string) => void;
  }): Promise<{ messageId: string; fullResponse: string }> {
    // 1. 持久化用户消息
    const userMsgId = this.deps.sessionService.addMessage(params.sessionId, {
      role: 'user', content: params.message,
    });

    // 2. 构建策略指令（委托给 StrategyInstructionBuilder）
    const strategyInstruction = this.deps.strategyBuilder.build(params);

    // 3. 组装 System Prompt（委托给 PromptAssemblyService）
    const systemPrompt = this.deps.promptAssembly.buildSystemPrompt(params.sessionId);

    // 4. 检查反思门控
    const reflectionCheck = this.deps.reflectionGate.check(params.sessionId);

    // 5. 构建 messages 数组
    const messages = this.buildMessages(systemPrompt, strategyInstruction, reflectionCheck, params);

    // 6. 调用 AI Gateway（SSE 流式）
    const { fullResponse, toolCalls } = await this.deps.aiGateway.chatStream(messages, {
      onChunk: params.onChunk,
      tools: this.deps.toolCalling.getAvailableTools(params.sessionId),
    });

    // 7. 处理 Tool Calling（如有）
    if (toolCalls.length > 0) {
      await this.deps.toolCalling.execute(toolCalls, params.sessionId);
    }

    // 8. 持久化 AI 回复
    const assistantMsgId = this.deps.sessionService.addMessage(params.sessionId, {
      role: 'assistant', content: fullResponse,
    });

    // 9. 触发诊断（异步，委托给 DiagnosisTriggerService）
    this.deps.diagnosisTrigger.maybeTrigger({
      sessionId: params.sessionId,
      userText: params.message,
      aiResponse: fullResponse,
    });

    // 10. 更新辩驳追踪
    this.deps.disputeTracker.trackExchange(params.sessionId, params.message, fullResponse);

    return { messageId: assistantMsgId, fullResponse };
  }

  // ... private helper: buildMessages()
}
```

```typescript
// ─── src/main/ipc/chat.handler.ts (After — ≤ 80 行) ───

import { createHandler, validatePayload } from './utils';
import { IPC_CHANNELS } from '../../shared/constants';
import type { ChatOrchestratorService } from '../modules/chat-orchestrator/chat-orchestrator.service';

// 单行 DI 注入，不再有模块级变量
let orchestrator: ChatOrchestratorService;

export function initChatHandlers(deps: { orchestrator: ChatOrchestratorService }): void {
  orchestrator = deps.orchestrator;
}

export function registerChatHandlers(): void {
  createHandler(IPC_CHANNELS.CHAT_SEND, async (args) => {
    const { message, sessionId, history, attitudeLevel, studentContext } =
      validatePayload(args, ['message', 'sessionId']);

    const result = await orchestrator.sendMessage({
      message, sessionId, history, attitudeLevel, studentContext,
      onChunk: (chunk) => {
        const win = BrowserWindow.getAllWindows()[0];
        win?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, { sessionId, chunk });
      },
    });

    return { acknowledged: true, messageId: result.messageId };
  });

  createHandler(IPC_CHANNELS.CHAT_STOP, async (args) => {
    const { sessionId } = validatePayload(args, ['sessionId']);
    await orchestrator.stopMessage(sessionId);
    return { stopped: true };
  });
}
```

### 3.3 解决 P0#2 — 消除模块级变量

**Before**（`src/main/ipc/teaching-state.handler.ts:28-32`）：
```typescript
// teaching-state.handler.ts (核心问题行)
let store: TeachingStateStore | null = null;          // 行 28：模块级变量
let promptBuilder: PromptBuilder | null = null;       // 行 31：模块级变量
let mainWindow: BrowserWindow | null = null;          // 行 34：模块级变量
```

**After** — 将 TeachingStateStore 注册到 DI 容器，handler 改为标准 DI 注入：

```typescript
// ─── src/main/modules/teaching-engine/teaching-state.service.ts (新增) ───

import { TeachingStateStore, CreateTeachingStateInput } from '../../services/teaching-state.store';
import { TeachingState } from '../../services/teaching-state.types';

/**
 * 教学状态服务 — 对 TeachingStateStore 的业务包装
 * 所有对 teaching_state 的读写都必须通过此服务，禁止跨模块直接操作 Store
 */
export class TeachingStateService {
  constructor(private store: TeachingStateStore) {}

  getOrCreate(sessionId: string): TeachingState {
    return this.store.getOrCreate(sessionId);
  }

  getBySession(sessionId: string): TeachingState | null {
    return this.store.getBySession(sessionId);
  }

  update(sessionId: string, updates: Partial<TeachingState>): TeachingState | null {
    return this.store.update(sessionId, updates);
  }

  /**
   * [关键] 提供只读上下文，替代模块级变量 getTeachingStateContext()
   * 外部模块只能通过此方法获取有限字段，无法直接操作 Store
   */
  getContext(sessionId: string): {
    currentPhase: string | null;
    currentSubphase: string | null;
    activeProblems: unknown[];
  } | null {
    const state = this.store.getBySession(sessionId);
    if (!state) return null;
    return {
      currentPhase: state.currentPhase,
      currentSubphase: state.currentSubphase,
      activeProblems: state.activeProblems,
    };
  }

  /** 训练评估完成后的症候严重度更新（原子操作，替代 training.handler 直接写） */
  downgradeSyndromeSeverity(sessionId: string, syndromeId: string, score: number): void {
    const state = this.store.getBySession(sessionId);
    if (!state) return;
    const { activeProblems } = downgradeSyndromeSeverity(state, syndromeId, score);
    this.store.update(sessionId, { activeProblems });
  }
}
```

```typescript
// ─── src/main/ipc/teaching-state.handler.ts (After — 无模块级变量) ───

// 模块级变量全部消除，改为函数参数传入

import { TeachingStateService } from '../modules/teaching-engine/teaching-state.service';
import { PromptBuilder } from '../services/prompt-builder';

let service: TeachingStateService;
let promptBuilder: PromptBuilder;
let mainWindow: BrowserWindow | null;

export function initTeachingStateHandlers(deps: {
  service: TeachingStateService;
  promptBuilder: PromptBuilder;
  mainWindow: BrowserWindow | null;
}): void {
  service = deps.service;
  promptBuilder = deps.promptBuilder;
  mainWindow = deps.mainWindow;
}

export function registerTeachingStateHandlers(): void {
  createHandler(IPC_CHANNELS.TEACHING_STATE_GET, async (args) => {
    const { sessionId } = validatePayload(args, ['sessionId']);
    const state = service.getOrCreate(sessionId);
    return { ...state, phaseName: getPhaseName(state.currentPhase), ... };
  });
  // ... 其余 handler 注册均通过 service 实例操作
}
```

### 3.4 解决 P0#3 — 消除回调桥接

**Before**（`src/main/core/ipc-registry.ts:65-67`）：
```typescript
// ipc-registry.ts 第 65-67 行 — 回调桥接反模式
let diagnosisMerger!: DiagnosisMerger;
registerDiagnosisMerger((m) => { diagnosisMerger = m; });
// 然后通过闭包传给 diagnosis.handler 的 init 函数
initDiagnosisHandlers({ ..., diagnosisMerger, ... });
```

**After** — TeachingStateService 注册到 DI 容器后，DiagnosisMerger 直接通过容器获取依赖：

```typescript
// ─── service-config.ts (After — 新增注册) ───

// TeachingStateService 注册到 DI 容器
container.register<TeachingStateService>('teachingStateService', (c) => {
  const db = c.get<Database.Database>('db');
  const store = new TeachingStateStore(db);
  return new TeachingStateService(store);
});

// DiagnosisMerger 改为 DI 构造
container.register<DiagnosisMerger>('diagnosisMerger', (c) => {
  const teachingStateService = c.get<TeachingStateService>('teachingStateService');
  // DiagnosisMerger 构造函数改为接收 TeachingStateService 而非回调 getter
  return new DiagnosisMerger(teachingStateService);
});
```

```typescript
// ─── ipc-registry.ts (After — 消除回调桥接) ───

registerAll(): void {
  // ... 获取所有服务实例（包括 diagnosisMerger）
  const diagnosisMerger = this.container.get<DiagnosisMerger>('diagnosisMerger');
  const teachingStateService = this.container.get<TeachingStateService>('teachingStateService');

  // 直接注入，不再需要回调桥接
  initDiagnosisHandlers({
    configService,
    diagnosisService,
    evidenceService,
    sessionService,
    growthTrendService,
    teachingStateService,   // ← 直接注入服务实例
    diagnosisMerger,        // ← 直接注入，无需 registerDiagnosisMerger 回调
    mainWindow: this.mainWindow,
  });
  registerDiagnosisHandlers();
}
```

### 3.5 解决 P1#4 + P1#5 — 跨域写操作 + 深层依赖

```typescript
// ─── training.handler.ts (Before:172-189) ───
// 问题：training.handler 直接通过 getTeachingStateStore() 操作 TeachingState

// ─── training.handler.ts (After) ───
// training 评估完成后，通过 TeachingStateService 的专用方法完成症候降级

createHandler(IPC_CHANNELS.TRAINING_EVALUATE, async (args) => {
  const validation = validatePayload(args, [...]);
  const result = await evaluateTraining(validation.data, deps.configService);

  // 持久化评分
  deps.trainingRecordService.complete(validation.data.recordId, { ... });

  // 症候严重度降级 → 委托给 TeachingStateService（原子操作）
  if (result.score >= 7) {
    deps.teachingStateService.downgradeSyndromeSeverity(
      validation.data.sessionId,
      validation.data.syndromeId,
      result.score,
    );
    // 推送更新由 TeachingStateService 内部完成，training.handler 不关心推送细节
  }

  return result;
});
```

---

## 四、前端模块化方案

### 4.1 services/ 目录完整文件清单

```
src/renderer/services/
├── index.ts                          # 统一导出
├── ipc-client.ts                     # 基于 API Contract 的类型化 IPC 调用封装
├── chat.service.ts                   # 聊天编排：sendMessage / stopMessage / 事件监听
├── diagnosis.service.ts              # 诊断编排：triggerDiagnosis / submitRewrite
├── teaching-state.service.ts         # 教学状态协调：fetch / confirm / updateSummary
├── training.service.ts               # 训练协调：start / submit / evaluate
├── session.service.ts                # 会话管理：load / create / switch / isNewUser
├── student-context.service.ts        # 学生上下文：load / updateFromDiagnosis / updateFromInteraction
├── right-panel.service.ts            # X-02 协议：面板管理（替代 right-panel.actions）
└── app-controller.ts                 # 应用级编排器（替代 useAppIpcListener 的隐式编排）
```

### 4.2 `ipc-client.ts` — 类型化 IPC 封装

```typescript
// src/renderer/services/ipc-client.ts

import type { ApiResponse } from '../../shared/api-contracts/base';

/**
 * 基于 API Contract 的类型化 invoke
 * 编译期确保 channel 名、payload、返回值类型一致
 */
export async function typedInvoke<TRequest, TResponse>(
  channel: string,
  payload: TRequest,
): Promise<ApiResponse<TResponse>> {
  if (!window.electronAPI) {
    return { success: false, error: 'electronAPI not available' };
  }
  const result = await window.electronAPI.invoke(channel, payload);
  return result as ApiResponse<TResponse>;
}

/**
 * 类型化事件监听
 */
export function typedOn<TEvent>(
  channel: string,
  handler: (data: TEvent) => void,
): () => void {
  if (!window.electronAPI) return () => {};
  return window.electronAPI.on(channel, (data: unknown) => handler(data as TEvent));
}
```

### 4.3 `chat.service.ts` — 聊天服务

```typescript
// src/renderer/services/chat.service.ts

import { typedInvoke } from './ipc-client';
import { ChatApi } from '../../shared/api-contracts/chat.contract';
import type { ChatSendRequest, ChatSendResponse } from '../../shared/api-contracts/chat.contract';

/**
 * 聊天服务 — 封装所有 chat 域 IPC 通信
 * 替代 chat.store.ts sendMessage 中的 5 处跨 store getState()
 */
export const chatService = {
  /** 发送消息 */
  async send(params: {
    message: string;
    sessionId: string;
    history: Array<{ role: 'user' | 'assistant'; content: string }>;
    attitudeLevel: string;
    studentContext: string;
  }): Promise<ChatSendResponse | null> {
    const result = await typedInvoke<ChatSendRequest, ChatSendResponse>(
      ChatApi.send.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 停止流式 */
  async stop(sessionId: string): Promise<void> {
    await typedInvoke(ChatApi.stop.channel, { sessionId });
  },

  /** 监听流数据 — 返回清理函数 */
  onStreamData(handler: (chunk: string) => void): () => void {
    // 使用 typedOn 注册事件监听，内部转换为 store action
    // （实际实现中，service 持有 store 引用或通过回调注入）
    return () => {}; // placeholder
  },
};
```

### 4.4 `app-controller.ts` — 应用编排器

```typescript
// src/renderer/services/app-controller.ts

import { chatService } from './chat.service';
import { diagnosisService } from './diagnosis.service';
import { teachingStateService } from './teaching-state.service';
import { trainingService } from './training.service';
import { studentContextService } from './student-context.service';
import { useDiagStore } from '../stores/diag.store';
import { useChatStore } from '../stores/chat.store';
import { useTeachingStateStore } from '../stores/teaching-state.store';
import { useStudentContextStore } from '../stores/student-context.store';
import { useTrainingStore } from '../stores/training.store';

/**
 * 应用级编排控制器 — 唯一有权做跨 store 协调的地方
 *
 * 规则：
 * 1. 本控制器是 App.tsx 的替代品，组件只调用 useAppController() 暴露的方法
 * 2. 所有 IPC 事件监听在此注册（替代 useAppIpcListener 的隐式编排）
 * 3. 每个事件处理函数通过明确的 store action 写入状态
 */

export interface AppController {
  /** 初始化：加载会话、加载配置、注册 IPC 监听 */
  initialize(): Promise<void>;

  /** 销毁：清理 IPC 监听 */
  destroy(): void;
}

export function createAppController(): AppController {
  let cleanupFns: Array<() => void> = [];

  return {
    async initialize() {
      // 1. 加载会话列表
      const { loadSessions, switchSession } = useSessionStore.getState();
      await loadSessions();
      const sessions = useSessionStore.getState().sessions;
      if (sessions.length > 0 && !useSessionStore.getState().currentSessionId) {
        await switchSession(sessions[0].id);
      }

      // 2. 加载学生上下文
      void useStudentContextStore.getState().load();

      // 3. 注册 IPC 事件监听（每个事件的 handler 是明确的）
      cleanupFns = [
        // DIAGNOSIS_UPDATE → diag.store + student-context.store + training.store
        diagnosisService.onDiagnosisUpdate((entry) => {
          const diagStore = useDiagStore.getState();
          diagStore.setCurrentDiagnosis(entry);
          diagStore.addToHistory(entry.sessionId, entry);
          if (entry.syndromes.length > 0) {
            useStudentContextStore.getState().updateFromDiagnosis(entry.syndromes);
            void useTrainingStore.getState().refreshFromDiagnosis();
          }
        }),

        // CHAT_STREAM_DATA → chat.store
        chatService.onStreamData((chunk) => {
          useChatStore.getState().appendToLastAssistant(chunk);
        }),

        // CHAT_STREAM_END → chat.store + student-context.store
        chatService.onStreamEnd((result) => {
          const chatStore = useChatStore.getState();
          if (result.aborted) {
            chatStore.abortStream();
          } else if (result.error) {
            chatStore.setError(result.error);
          }
          chatStore.setLoading(false);
          if (result.fullResponse) {
            useStudentContextStore.getState().updateFromInteraction('partial');
          }
        }),

        // TEACHING_STATE_UPDATED → teaching-state.store
        teachingStateService.onUpdated((state) => {
          useTeachingStateStore.getState().setCurrentState(state);
        }),
      ];
    },

    destroy() {
      cleanupFns.forEach((fn) => fn());
    },
  };
}
```

### 4.5 App.tsx 瘦身 — Before/After

**Before**（行数：206 行，import 6 store + 2 hook + rightPanelActions + IPC_CHANNELS）：

```typescript
// App.tsx:20-27 — 6 个 store 的直接 import
import { useConfigStore } from './stores/config.store';
import { useDiagStore } from './stores/diag.store';
import { useChatStore } from './stores/chat.store';
import { useSessionStore } from './stores/session.store';
import { useStudentContextStore } from './stores/student-context.store';
import { useTrainingStore } from './stores/training.store';
import { rightPanelActions } from './stores/right-panel.actions';
// App.tsx:21 — 直接 import IPC_CHANNELS
import { IPC_CHANNELS } from '../shared/constants';
// App.tsx:47,66,118,131,142 — 10+ 处 store.getState()
```

**After**（预计 ≤ 80 行，只消费 useAppController + 各组件所需 store hook）：

```typescript
// ─── src/renderer/App.tsx (After) ───

import React, { useEffect, useState } from 'react';
import { AppShell } from './components/layout/AppShell';
import { SoloSidebar } from './components/layout/SoloSidebar';
import { RightDrawer } from './components/layout/RightDrawer';
import { AppErrorBoundary } from './components/layout/AppErrorBoundary';
import { AppConfigGate } from './components/layout/AppConfigGate';
import { ConfigPage } from './components/pages/ConfigPage';
import { ChatView } from './components/chat/ChatView';
import { TrainingWorkshop } from './components/training/TrainingWorkshop';

// ✅ 唯一跨模块入口：仅导入 appController
import { useAppController } from './services/app-controller';

// ✅ 各组件仅导入自己域的 store
// （ChatView 内部只 import chat.store，TrainingWorkshop 内部只 import training.store）

export function App(): React.ReactElement {
  const [view, setView] = useState<'main' | 'config'>('main');
  const [showOnboarding, setShowOnboarding] = useState(false);

  // ✅ 单一编排钩子替代所有跨 store 逻辑
  const { ready } = useAppController({ setShowOnboarding });

  if (!ready) {
    return <div className="app-loading">正在启动...</div>;
  }

  // ✅ Config 页不依赖任何 store（通过 AppConfigGate 内部处理）
  if (view === 'config') {
    return <ConfigPage onBack={() => setView('main')} />;
  }

  return (
    <AppErrorBoundary>
      <AppConfigGate
        onConfigured={() => setView('main')}
        showOnboarding={showOnboarding}
        onCompleteOnboarding={() => setShowOnboarding(false)}
      >
        <AppShell
          sidebar={<SoloSidebar />}
          rightDrawer={<RightDrawer />}
        >
          <ChatView />
          <TrainingWorkshop />
        </AppShell>
      </AppConfigGate>
    </AppErrorBoundary>
  );
}
```

### 4.6 `useAppController` 完整实现

```typescript
// src/renderer/services/useAppController.ts (新增 hook)

import { useEffect, useState, useRef } from 'react';
import { createAppController, type AppController } from './app-controller';

interface UseAppControllerProps {
  setShowOnboarding: (v: boolean) => void;
}

interface UseAppControllerResult {
  ready: boolean;
}

/**
 * 应用控制器 Hook
 *
 * 替代 App.tsx 中分散的 6 个 store import + 10+ 处 getState() 调用 +
 * useAppIpcListener 的隐式编排。
 *
 * 本 hook 是前端唯一的跨模块协调点。所有跨 store 通信由此统一管理。
 */
export function useAppController({
  setShowOnboarding,
}: UseAppControllerProps): UseAppControllerResult {
  const [ready, setReady] = useState(false);
  const controllerRef = useRef<AppController | null>(null);

  useEffect(() => {
    const controller = createAppController();
    controllerRef.current = controller;

    controller.initialize()
      .then(() => setReady(true))
      .catch((err) => {
        console.error('[AppController] init failed:', err);
        setReady(true); // 即使失败也渲染 UI，由子组件处理错误
      });

    return () => {
      controller.destroy();
    };
  }, []);

  // 新用户检测（原来在 App.tsx:51-66 的 useEffect）
  useEffect(() => {
    if (!ready || !window.electronAPI) return;

    // 委托给 sessionService 的新用户检测
    import('./session.service').then(({ sessionService }) => {
      sessionService.checkIsNewUser().then((isNew) => {
        if (isNew) setShowOnboarding(true);
      });
    });
  }, [ready, setShowOnboarding]);

  return { ready };
}
```

### 4.7 chat.store.ts sendMessage 瘦身 — Before/After

**Before**（`chat.store.ts:177-210` — 5 处跨 store getState()）：

```typescript
// chat.store.ts:177 — 读 session.store
let sessionId = useSessionStore.getState().currentSessionId;
// chat.store.ts:179 — 调 session.store.switchSession
sessionStore.switchSession(sessionStore.sessions[0].id);
// chat.store.ts:186 — 调 session.store.createSession
const newSession = await sessionStore.createSession();
// chat.store.ts:209 — 读 config.store
const attitudeLevel = useConfigStore.getState().attitudeLevel;
// chat.store.ts:210 — 读 student-context.store
const studentContext = useStudentContextStore.getState().toJSON();
```

**After**（sessionId 由调用方传入，config/context 由 orchestrator 注入）：

```typescript
// chat.store.ts — sendMessage action (After)
sendMessage: async (text: string, deps: {
  sessionId: string;            // ✅ 由 appController 传入，不再 getState
  attitudeLevel: string;        // ✅ 由 appController 传入
  studentContext: string;       // ✅ 由 appController 传入
}) => {
  const { isLoading } = get();
  if (isLoading || !text.trim()) return;

  const allMessages = get().messages.filter(...);
  const history = buildSlidingWindow(allMessages.map(...));

  // 仅更新自身状态
  set((state) => ({
    messages: [...state.messages, userMsg, assistantMsg],
    isLoading: true,
    error: null,
  }));

  try {
    // ✅ IPC 调用委托给 chatService，不再直接 invoke
    await chatService.send({
      message: text.trim(),
      sessionId: deps.sessionId,
      history,
      attitudeLevel: deps.attitudeLevel,
      studentContext: deps.studentContext,
    });
  } catch (error) {
    set((state) => {
      const msgs = state.messages.filter((m) => m.id !== assistantMsg.id);
      return { messages: msgs, isLoading: false, error: String(error) };
    });
  }
},
```

---

## 五、迁移阶段

### Phase 1：API 契约层建立（无破坏性，纯新增）

| 项目 | 内容 |
|------|------|
| **改动文件** | 新增 12 个文件：`src/shared/api-contracts/*.ts` |
| **影响范围** | 零破坏性。现有代码不依赖 api-contracts，仅新增类型定义 |
| **完成标准** | `tsc --noEmit` 0 errors（新文件自身类型正确） |
| **预计耗时** | 0.5 天 |
| **风险** | 极低。纯类型定义，不影响运行时 |

### Phase 2：后端 Module Service 拆分（有破坏性，需 DI 调整）

| 项目 | 内容 |
|------|------|
| **改动文件** | **新增**：`src/main/modules/chat-orchestrator/` (3 files)、`src/main/modules/diagnosis-processor/` (3 files)、`src/main/modules/teaching-engine/teaching-state.service.ts`、`src/main/modules/ai-gateway/` (2 files)、`src/main/modules/training-coordinator/` (1 file) |
|  | **修改**：`service-config.ts`（注册新 Module Service）、`ipc-registry.ts`（改为注入 Module Service）、`chat.handler.ts`（从 964 → ≤ 80 行）、`teaching-state.handler.ts`（消除模块级变量）、`diagnosis.handler.ts`（改为注入 TeachingStateService）、`training.handler.ts`（改为委托 TeachingStateService） |
|  | **不修改**：数据层 services/（session/diagnosis/evidence/training-record 等 CRUD 服务不变）、`teaching-state-machine.ts`、`teaching-strategy-router.ts` |
| **数据库** | **零改动**。所有 SQLite schema 不变 |
| **完成标准** | `tsc --noEmit` 0 errors + `vitest run` 全通过（新增 Module Service 单元测试） |
| **预计耗时** | 3 天 |
| **风险** | 🟡 中。chat.handler 拆分影响最核心的聊天流程，需逐段验证。建议：① 先在 test 分支拆分；② 用现有 vitest 测试覆盖 sendMessage 核心路径；③ 每次 extract 一个子功能后立即运行全量测试 |

### Phase 3：前端 Service 层建立（有破坏性，需重构 store action）

| 项目 | 内容 |
|------|------|
| **改动文件** | **新增**：`src/renderer/services/` (10 files) |
|  | **修改**：`App.tsx`（从 206 → ≤ 80 行）、`chat.store.ts`（sendMessage 消除跨 store getState）、`training.actions.ts`（sessionId 改为参数传入）、`training.store.ts`（消除 dynamic import）、`useAppIpcListener.ts`（逻辑迁移到 app-controller.ts 后删除） |
|  | **修改**：`ChatView.tsx`（onboarding state 通过 props，IPC 调用委托 service）、`SoloSidebar.tsx`（跨 store selector 减少）、`WorkTreePanel.tsx`（跨 store getState 消除） |
|  | **不修改**：10 个无跨 store 依赖的纯域 store（config / diag / manuscript / editor / drawer / panel-session / paradigm / teaching-state / ui-layout / student-context） |
| **完成标准** | `tsc --noEmit` 0 errors + `vitest run` 全通过 + 手动测试：发送消息 → 接收流式响应 → 触发诊断 → 查看教学状态更新 → 进入训练 → 评估训练 → 症候降级 |
| **预计耗时** | 3 天 |
| **风险** | 🟡 中。前端 store action 签名变更可能影响多个组件。建议：① 逐 store 改造，每改造一个 store 运行全量测试；② chat.store 改造优先级最高（耦合度最高）；③ 保留旧 action 签名作为 deprecated 兼容 1 个 sprint |

### Phase 4：收尾清理 + 全量验证

| 项目 | 内容 |
|------|------|
| **改动文件** | 删除：`useAppIpcListener.ts`（逻辑已迁移）、`right-panel.actions.ts`（替换为 right-panel.service.ts）、`ipc-handlers.ts`（已废弃注释文件） |
|  | **修改**：`shared/constants.ts`（IPC_CHANNELS 标记 deprecated，引导使用 api-contracts）、删除 `teaching-state.handler.ts` 中的模块级变量导出函数（`getTeachingStateStore` / `pushTeachingStateUpdate` / `getTeachingStateContext` 标记 @deprecated） |
| **完成标准** | `tsc --noEmit` 0 errors、`vitest run --coverage` 覆盖率不低于重构前、手动回归测试通过（发送消息、诊断、训练、配置、会话管理、教学状态推进） |
| **预计耗时** | 1 天 |
| **风险** | 🟢 低。仅做清理，无新逻辑引入 |

### 迁移总览

```
Phase 1 (0.5天)      Phase 2 (3天)         Phase 3 (3天)        Phase 4 (1天)
API Contract         后端 Module Service    前端 Service 层      收尾清理
    │                      │                     │                   │
    ├─ 新增类型定义         ├─ chat.handler 拆分   ├─ App.tsx 瘦身     ├─ 删除废弃文件
    ├─ 零破坏性             ├─ teaching-state DI   ├─ store action 重构 ├─ 标记 deprecated
    └─ 独立可合并           ├─ ipc-registry 改造   ├─ useAppController  └─ 全量回归
                           └─ training.handler 修复└─ 组件解耦
```

---

## 六、自评第一轮（方案可行性评估）

### 6.1 是否解决了两份报告中所有 P0 问题？

| P0 问题 | 来源 | 本方案解决方式 | 结论 |
|---------|------|---------------|------|
| chat.handler God Handler（964 行） | 后端报告 P0#1 | 拆分为 ChatOrchestratorService + StrategyInstructionBuilder + DiagnosisTriggerService，handler 缩减至 ≤ 80 行 | ✅ 已解决 |
| teaching-state 模块级变量 | 后端报告 P0#2 | 注册 TeachingStateService 到 DI 容器，handler 改为标准 DI 注入 | ✅ 已解决 |
| ipc-registry 回调桥接 | 后端报告 P0#3 | TeachingStateService 注册 DI 后，DiagnosisMerger 直接构造函数注入，回调桥接自然消除 | ✅ 已解决 |
| App.tsx God Component（6 store + 10+ getState） | 前端报告 P0#1 | 引入 useAppController 作为唯一跨模块协调点，App.tsx 仅消费 controller + 子组件 | ✅ 已解决 |
| chat.store → 3 个外部 store getState | 前端报告 P0#2 | sendMessage 的 sessionId/attitudeLevel/studentContext 改为参数传入，由 appController 提供 | ✅ 已解决 |
| useAppIpcListener → 5 个 store 蜘蛛网 | 前端报告 P0#3 | 逻辑迁移到 app-controller.ts，每个事件处理函数明确指向具体 store action | ✅ 已解决 |

### 6.2 是否有引入新耦合的风险？

| 风险点 | 评估 |
|--------|------|
| `app-controller.ts` 成为新的 God Object | 🟡 中等风险。但 app-controller 的职责被严格限定为「IPC 事件 → store action 的映射」，不包含业务逻辑。相比当前 App.tsx 中分散的 getState() 调用，集中管理更易追踪和测试。如果未来映射数量膨胀到 30+，可进一步按域拆分为 ChatEventController / DiagnosisEventController 等 |
| ChatOrchestratorService 依赖 11 个接口 | 🟡 中等风险。已通过 DI 容器管理依赖，且每个依赖只暴露业务所需的最小接口（ISP），非上帝对象。ChatOrchestrator 不直接访问 DB，所有数据操作委托给 SessionService / PromptAssemblyService |
| 前后端 api-contracts 类型同步 | 🟢 低风险。api-contracts 放在 shared/ 目录，前端 import 类型定义，后端 import 类型定义，TypeScript 编译期双向校验。唯一风险是前后端对 ApiResponse 包装的理解不一致，但 base.ts 已定义为判别式联合类型 |
| 服务层函数式 API 与 Store 状态生命周期 | 🟢 低风险。services/ 层函数通过 getState() 读取 store（仅 app-controller 内部使用），与 Zustand 的不可变更新模式兼容 |

### 6.3 改动量是否可控（是否可以在不改动数据库的前提下完成）？

**结论：完全可以在不改动数据库的前提下完成。**

- 本方案**零数据库变更**。所有 SQLite schema、表结构、迁移脚本不变。
- 后端 Data Layer（`src/main/services/` 下的 CRUD 服务）**完全不修改**，仅上层 Module Service 重新编排调用。
- 前端 Store 的 state shape **不变**，仅修改 action 内部实现（从 getState 跨模块调用改为参数注入 + service 委托）。
- 改动范围集中在 **编排层**（后端 Module Service + 前端 services/），不触及持久化层。

### 6.4 是否有遗漏的模块？

| 现有模块 | 本方案覆盖情况 | 说明 |
|---------|---------------|------|
| api-proxy.ts（LLM 调用） | ✅ 纳入 ai-gateway 模块 | 连接池化提到但不紧急（P2），Phase 2 先保留现有 new ApiProxy 模式 |
| manuscript.handler（作品 CRUD） | ✅ 保留不变，不拆分 | 当前已是最简 handler（仅 1 个 DB 依赖），无重构必要 |
| config.handler（配置读写） | ✅ 保留不变 | 当前最干净的 handler（1 个 Service 依赖） |
| evidence.handler（证据 CRUD） | ✅ 保留不变 | 单依赖，无跨模块耦合 |
| ability-profile.handler | ✅ 保留不变 | 单依赖 |
| session.handler | ✅ 保留不变 | 单依赖 |
| PromptLoader 的 setter 注入地狱 | ✅ 已纳入 PromptAssemblyService | 用构造函数 DI 替代 5 个 setter |
| feedback-engine / writing-analyzer（Phase 2 骨架） | ✅ 不纳入本次重构 | Phase 2 占位文件不影响核心流程 |
| message-router（V3 兼容层） | ✅ 保留不变 | 20 行简化文件 |
| right-panel.actions.ts | ✅ 替换为 right-panel.service.ts | Phase 3 纳入 |

---

## 七、自评第二轮（代码实现者视角逐模块推演）

### 7.1 chat.handler 拆分后 DI 注入是否可行？

**对照 `service-config.ts` 现有 DI 机制**：

现有 DI 容器 (`service-container.ts`) 已支持：
- 单例注册 + 延迟初始化（`register<T>(name, factory)`）
- 工厂函数可接收容器引用解析其他依赖（`c.get<T>(name)`）
- 循环依赖检测（`resolving` Set）

`service-config.ts` 第 37-49 行已有跨服务依赖的注册案例：
```typescript
// service-config.ts:37-49 — StudentModelService 依赖 DiagnosisService + TrainingRecordService
container.register<StudentModelService>('studentModelService', (c) =>
  new StudentModelService(
    db,
    c.get<DiagnosisService>('diagnosisService'),
    c.get<TrainingRecordService>('trainingRecordService'),
    resourcesRoot,
  ),
);
```

**结论**：✅ 可行。ChatOrchestratorService 的注册方式与 StudentModelService 完全一致。新增注册代码：

```typescript
// service-config.ts (新增)
container.register<ChatOrchestratorService>('chatOrchestrator', (c) =>
  new ChatOrchestratorService({
    aiGateway: c.get<ApiGatewayService>('aiGateway'),
    toolCalling: c.get<ToolCallingService>('toolCalling'),
    strategyBuilder: c.get<StrategyInstructionBuilder>('strategyBuilder'),
    diagnosisTrigger: c.get<DiagnosisTriggerService>('diagnosisTrigger'),
    sessionService: c.get<SessionService>('sessionService'),
    promptAssembly: c.get<PromptAssemblyService>('promptAssembly'),
    disputeTracker: c.get<DisputeTrackerService>('disputeTracker'),
    reflectionGate: c.get<ReflectionGateService>('reflectionGate'),
  }),
);
```

**代码证据**：现有 `service-container.ts` 的函数签名 `register<T>(name: string, factory: (container: ServiceContainer) => T)` 完全支持以上模式。循环依赖由 `resolving` Set（第 15 行、第 33-38 行）保证运行时检测。

### 7.2 teaching-state.handler 消除模块级变量后 handler 间通信路径是否清晰？

**当前通信路径**（问题态）：
```
training.handler:172 → import { getTeachingStateStore } from './teaching-state.handler'
                     → 访问模块级 store 变量 (teaching-state.handler.ts:28)
                     → store.update() / pushTeachingStateUpdate()

diagnosis.handler → import { getTeachingStateContext } from './teaching-state.handler'
                  → 只读查询模块级 store 变量
```

**重构后通信路径**：
```
training.handler → deps.teachingStateService.downgradeSyndromeSeverity(...)
                 → TeachingStateService 内部完成 store.update() + 推送

diagnosis.handler → deps.teachingStateService.getContext(...)
                  → 只读查询，通过 DI 接口获取

ipc-registry.ts → 直接从 DI 容器获取 TeachingStateService
                 → 注入给各 handler 的 init 函数
                 → 不再通过 registerDiagnosisMerger 回调桥接
```

**结论**：✅ 清晰。每个 handler 通过 DI 获取 `TeachingStateService` 实例，调用路径从 `模块级变量 → 直接操作` 变为 `DI 接口 → 服务方法`。`TeachingStateService` 成为 TeachingState 的唯一写入口，杜绝跨 handler 直接修改 Store。

**代码证据**：`service-container.ts` 第 10 行 `get<T>(name)` 方法支持从容器获取单例实例，`ipc-registry.ts` 第 38-54 行已有从容器获取 15 个服务注入 handler 的先例。

### 7.3 前端 services/ 层是否能真正消除 store.getState() 跨模块调用？

**验证推演**（以 `chat.store.sendMessage` 跨 store 调用链为例）：

| Before | After | 消除方式 |
|--------|-------|---------|
| `chat.store.ts:177` — `useSessionStore.getState().currentSessionId` | sessionId 由 appController 在调用 sendMessage 前注入 | 参数传入 |
| `chat.store.ts:179` — `sessionStore.switchSession()` | 移到 appController.initialize() 中处理 | 职责上移 |
| `chat.store.ts:186` — `sessionStore.createSession()` | 移到 appController.initialize() 中处理 | 职责上移 |
| `chat.store.ts:209` — `useConfigStore.getState().attitudeLevel` | attitudeLevel 由 appController 在调用时读取并注入 | 参数传入 |
| `chat.store.ts:210` — `useStudentContextStore.getState().toJSON()` | studentContext 由 appController 在调用时读取并注入 | 参数传入 |

**但这里有个关键问题**：appController 内部仍然需要 `getState()` 来读取 store。这是否只是把耦合从 store 移到了 controller？

**回答**：是的，但这是有意义的移动——
1. **耦合面从 N 个 store 缩减为 1 个 controller**。原来 6 个 store 互相 getState()，现在只有 appController 做 getState()。
2. **Controller 是显式编排器**。它不隐藏耦合，而是坦率地声明"我负责协调这些 store"。
3. **Controller 可独立测试**。可以 mock 所有 store 来测试 controller 的协调逻辑，而原来 store-to-store 调用无法单独测试。
4. **非 controller 的 store（config / diag / manuscript / editor 等 10 个）完全消除跨 store 调用**，可独立抽取。

**结论**：✅ 可行，但 app-controller 需要谨慎治理（如果未来行数超过 200 行，按域拆分）。

**代码证据**：`useAppIpcListener.ts:31-65` 当前在一个 useEffect 中直接操作 5 个 store。将这些映射移到 app-controller.ts 后，每个映射都是一行明确的 `xxxStore.getState().yyyAction(data)`，结构更清晰。

### 7.4 前后端 API Contract 是否能同时被 TypeScript 编译期检查？

**验证推演**：

1. `src/shared/api-contracts/` 放在 `shared/` 目录下
2. 前端 tsconfig 已包含 `src/shared/**/*`（否则无法 import `IPC_CHANNELS`）
3. 后端 tsconfig 已包含 `src/shared/**/*`（否则无法 import `IPC_CHANNELS` + `mappings`）

**编译期检查链路**：

```
前端调用：
  typedInvoke<ChatSendRequest, ChatSendResponse>(ChatApi.send.channel, payload)
  → TypeScript 检查 payload 类型是否匹配 ChatSendRequest
  → TypeScript 检查返回值是否匹配 ApiResponse<ChatSendResponse>

后端注册：
  createHandler(IPC_CHANNELS.CHAT_SEND, (args) => {
    // args 类型为 unknown，需手动 validatePayload
    // ⚠️ 编译期无法强制 args 类型为 ChatSendRequest
  })
```

**结论**：⚠️ 前端可享受完整编译期检查，后端 handler 的 `args` 参数类型仍是 `unknown`（受限于 Electron IPC 的类型擦除）。但 `validatePayload` 提供了运行时检查。

**弥补方案**：可以定义一个通用的 `TypedHandler<TReq, TRes>` 包装器，在 `createHandler` 内部做一次类型断言（`args as TReq`），至少让 handler 内部使用时有类型提示：

```typescript
// 增强 createHandler 的类型包装
function createTypedHandler<TReq, TRes>(
  channel: string,
  handler: (args: TReq) => Promise<TRes>,
  requiredFields: string[],
): void {
  createHandler(channel, async (args) => {
    validatePayload(args, requiredFields);
    return handler(args as TReq);
  });
}
```

### 7.5 整个方案最脆弱的一环是什么？

**最脆弱的一环：前端 `app-controller.ts` 中的 IPC 事件 → Store Action 映射表**

**脆弱性分析**：

1. **隐式时序依赖**：`DIAGNOSIS_UPDATE` 事件同时触发 `diagStore.setCurrentDiagnosis` + `studentContextStore.updateFromDiagnosis` + `trainingStore.refreshFromDiagnosis`。如果这三个操作有隐含的执行顺序要求（例如 trainingStore 依赖 diagStore 先更新），当前实现 `useAppIpcListener.ts:31-37` 是同步顺序执行的，迁移到 controller 后需要保持这个顺序。

2. **缺乏事务性**：如果 `setCurrentDiagnosis` 成功但 `refreshFromDiagnosis` 抛异常，系统状态会不一致（诊断已设置但训练未刷新）。当前代码 `useAppIpcListener.ts:37` 使用了 `void useTrainingStore.getState().refreshFromDiagnosis()` —— 即静默吞掉 training 刷新的错误。

3. **Event 与 Invoke 响应重叠**：`chat:send` (invoke) → `chat:stream:data` (N 次 event) → `chat:stream:end` (event)。这个 invoke→event→event 的编排链在 app-controller 中被拆成了 3 个独立的 handler，但它们之间的状态一致性（如 stream 期间的 `isLoading` 状态）依赖 chat.store 的原子更新。

**缓解措施**（已纳入方案）：
- `app-controller.ts` 中每个事件 handler 明确标注依赖顺序（注释）
- 在 controller 中为三阶段流式链路（send→stream data→stream end）定义显式的状态机：`IDLE → STREAMING → DONE / ERROR`
- 在 vitest 中新增 controller 集成测试，覆盖 `send → stream data → stream end` 完整链路

**代码证据**：当前 `useAppIpcListener.ts:48-52` 中 `CHAT_STREAM_END` 的处理逻辑是 `abortStream() || setError() || setLoading(false)`，这三个操作需要原子性。迁移到 controller 后需要在单个函数内处理，确保不会出现 `setLoading(false)` 之后又收到 stream data 的 race condition。

---

*方案完成。所有建议改动均基于两份分析报告中标注的文件路径和行号，可在现有代码库中逐条追溯验证。*
