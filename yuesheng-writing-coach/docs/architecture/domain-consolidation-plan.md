# 领域收敛重构方案

> 目标：解决 Service 层颗粒度过细、交叉依赖严重、ChatOrchestrator 过重的问题
> 基于当前 DI 容器注册的 22 个服务 + 4 个骨架服务分析
> 更新日期：2026-06-13

---

## 1. 现状诊断

### 1.1 当前依赖图（按 DI 注册顺序）

```
无依赖:          ConfigService, SessionService, DiagnosisService, EvidenceService,
                 TrainingRecordService, ProblemPrioritizer, DisputeTrackerService,
                 ReflectionGateService, PromptBuilder, DynamicContextService,
                 CodexService, MessageRouter, TeachingStrategyService
                 └── (13 个薄服务，各自职责单一，无需收敛)

单依赖:          ApiProxyService → ConfigService
                 GrowthTrendService → StudentModelService
                 DiagnosisMerger → TeachingStateService
                 PromptLoader → PromptBuilder + DynamicContextService + CodexService
                 TeachingStrategyService → TeachingStrategyRouter (setter)
                 └── (5 个，依赖链清晰，无需收敛)

多依赖:          StudentModelService → DiagnosisService + TrainingRecordService
                 AbilityProfileService → DiagnosisService + TrainingRecordService
                 StrategyInstructionBuilder → StudentModelService + TeachingStrategyService + ProblemPrioritizer
                 └── (3 个，存在功能重叠)

聚合依赖:        ChatOrchestratorService → 11 个服务 (PO 类)
                 └── (1 个，核心问题点)

跨模块旁路:      training.handler → 直接导入 teaching-state.handler 的函数
                 diagnostics.handler → 直接导入 diagnosis-parser/merger
                 teaching-state.handler → 模块级变量 (绕过 DI)
```

### 1.2 核心问题

| 问题 | 位置 | 影响 |
|------|------|------|
| **过重编排中心** | ChatOrchestratorService (749 行) | 依赖 11 个服务，跨所有领域边界，改任何一个服务可能影响全局 |
| **重复依赖模式** | StudentModelService + AbilityProfileService | 两者依赖完全一致 (DiagnosisService + TrainingRecordService)，数据来源重复 |
| **DI 旁路** | teaching-state.handler 模块级变量 | PromptLoader 通过 setter 引用，training.handler 直接 import，无法在 DI 层面管理 |
| **隐式依赖** | training.handler → teaching-state.handler | diagnostic.handler 中的 processDiagnosisFromAI 跨域写 teaching_state |
| **颗粒过细** | 22 个服务文件在 services/ 目录平铺 | 查找困难，职责边界模糊 |

---

## 2. 领域划分方案

### 2.1 建议的 6 个领域

```
src/main/
├── core/                    # [基础设施] 不变
│   ├── app-initializer.ts
│   ├── service-container.ts
│   ├── service-config.ts    # → 简化为领域级别的注册
│   ├── ipc-registry.ts
│   └── window-manager.ts
│
├── ipc/                     # [IPC 层] 薄 handler 不变
│
├── domains/
│   ├── chat/                # [领域A] 聊天编排
│   ├── diagnosis/           # [领域B] 诊断与证据
│   ├── teaching/            # [领域C] 教学策略与状态
│   ├── student/             # [领域D] 学生模型与画像
│   ├── training/            # [领域E] 训练工坊
│   └── prompt/              # [领域F] Prompt 工程
│
└── shared/                  # 跨领域共享服务
    ├── services/
    │   ├── config.service.ts      # 配置 (无依赖)
    │   ├── session.service.ts     # 会话 (无领域依赖)
    │   └── api-proxy.service.ts   # API 代理 (仅依赖 ConfigService)
    └── ...
```

### 2.2 各领域边界定义

#### 领域 A：Chat（聊天编排）

```
目标：合并 ChatOrchestrator + MessageRouter → 单一聊天编排引擎
边界：只负责消息的接收、编排、发送和流式响应处理
外部通信：通过 IPC 接收 chat:send，调用其他领域接口
```

| 当前文件 | 归属 | 建议 |
|---------|------|------|
| `chat-orchestrator.service.ts` | A | 主体留在 A，内部向其他领域的调用 → 抽取为领域接口 |
| `message-router.ts` | A | 合并到 ChatOrchestrator（仅 1 个函数） |
| `api-proxy.service.ts` | 共享 | 保留在共享层，被 A 调用 |
| `chat.handler.ts` | — | 保持薄委托层不变 |

**领域 A 对外接口（被其他领域调用）**：
- `sendMessage()` → 内部流程不对外暴露
- IO: 入 = chat:send, 出 = chat:stream:data / chat:stream:end

**领域 A 需要的外部依赖（接口抽象）**：
- `DiagnosisService.save()` → 诊断领域 B
- `TeachingStateService.getState()` → 教学领域 C
- `StudentModelService.toPromptText()` → 学生领域 D
- `PromptLoader.loadSystemPrompt()` → Prompt 领域 F

---

#### 领域 B：Diagnosis（诊断与证据）

```
目标：合并诊断相关的 5 个文件 + 证据服务 → 统一诊断引擎
边界：诊断的创建、解析、合并、持久化
外部通信：IPC diagnosis:* / growth:* / evidence:*
```

| 当前文件 | 归属 | 建议 |
|---------|------|------|
| `diagnosis.service.ts` | B | 合并到领域入口 |
| `diagnosis-parser.ts` | B | 内部工具函数，不暴露 |
| `diagnosis-merger.ts` | B | 内部服务，被 ChatOrch 调用 |
| `diagnosis-merger-utils.ts` | B | 内部工具函数 |
| `evidence.service.ts` | B | 合并到领域入口 |
| `evidence-grouping.ts` | B | 内部工具函数 |
| `diagnosis.handler.ts` | — | 保持薄委托层不变 |

**领域 B 对外接口**：
- `saveDiagnosis(diagnosis, sessionId)` → 持久化 + 自动创建证据
- `getDiagnosis(sessionId, messageId)` → 查询
- `mergeDiagnosisIntoTeaching(diagnosis)` → 调用领域 C 的接口
- IO: 入 = diagnosis:query / getComparison, 出 = diagnosis:update (事件)

**领域 B 需要的外部依赖**：
- `TeachingStateService.mergeProblems()` → 教学领域 C

---

#### 领域 C：Teaching（教学策略与状态）

```
目标：合并教学相关的 10+ 个文件 → 统一教学引擎
边界：教学状态管理 + 策略路由 + 症候锁定 + 反思门控
外部通信：IPC teachingState:*
```

| 当前文件 | 归属 | 建议 |
|---------|------|------|
| `teaching-state.service.ts` | C | 领域门面入口 |
| `teaching-state.store.ts` | C | 内部存储，不暴露 |
| `teaching-state-machine.ts` | C | 桶文件 |
| `teaching-state-machine.constants.ts` | C | 内部常量 |
| `teaching-state-machine.navigation.ts` | C | 内部 |
| `teaching-state-machine.locking.ts` | C | 内部 |
| `teaching-state-machine.reflection.ts` | C | 内部 |
| `teaching-strategy-router.ts` | C | 合并到领域 |
| `teaching-strategy-router.*.ts` | C | 全部合并到路由子目录 |
| `teaching-strategy.service.ts` | C | 领域内部 |
| `problem-prioritizer.service.ts` | C | 领域内部 |
| `strategy-instruction-builder.ts` | C | 领域内部 |
| `dispute-tracker.service.ts` | C | 领域内部 |
| `reflection-gate.service.ts` | C | 领域内部 |
| `transition-prompt-loader.ts` | C | 领域内部 |
| `teaching-state.handler.ts` | — | 薄委托层，但模块级变量问题需修复 |
| `teaching-state.types.ts` | C | 内部类型 |

**领域 C 对外接口**：
- `getState(sessionId)` → 教学状态
- `updateState(sessionId, patch)` → 更新状态
- `confirmPhase(sessionId)` → 阶段推进
- `getStrategyDecision(sessionId, input)` → 策略决策
- IO: 入 = teachingState:get/update/confirm, 出 = teachingState:updated (事件)

**领域 C 需要的外部依赖**：
- `StudentModelService.getProfile()` → 学生领域 D
- 外部配置 JSON → 文件系统

---

#### 领域 D：Student（学生模型与画像）

```
目标：合并 StudentModel + AbilityProfile + GrowthTrend → 统一学生画像引擎
边界：跨会话数据分析，纯计算（只读 diagnosis_results + training_records）
外部通信：IPC ability:getProfile / growth:*
```

| 当前文件 | 归属 | 建议 |
|---------|------|------|
| `student-model-service.ts` | D | 合并为领域入口 |
| `student-model-service.types.ts` | D | 合并 |
| `student-model-service.utils.ts` | D | 合并 |
| `ability-profile.service.ts` | D | 合并 |
| `growth-trend.service.ts` | D | 合并 |
| `student-classifier.ts` | D | 骨架，当前无实现 |

**关键问题**：StudentModelService 和 AbilityProfileService 依赖完全一致（DiagnosisService + TrainingRecordService）。建议：
1. 抽取通用的数据聚合层（`ProfileDataAggregator`）
2. StudentModelService 只负责「学生画像 → Prompt 文本」
3. AbilityProfileService 只负责「能力画像 → UI 展示」
4. GrowthTrendService 完全并入 StudentModelService

**领域 D 对外接口**：
- `toPromptText(sessionId)` → Prompt 注入文本
- `getProfile(sessionId)` → 能力画像
- `getGrowthSummary(sessionId?)` → 成长趋势
- IO: 入 = ability:getProfile / growth:getTrends

**领域 D 需要的外部依赖**：
- `DiagnosisService.getRecentBySession()` → 领域 B
- `TrainingRecordService.getBySession()` → 领域 E

---

#### 领域 E：Training（训练工坊）

```
目标：合并训练相关的服务
边界：训练推荐、分配、记录、评估、行为推导
外部通信：IPC training:*
```

| 当前文件 | 归属 | 建议 |
|---------|------|------|
| `training-record.service.ts` | E | 领域入口 |
| `training-recommendation.service.ts` | E | 内部 |
| `training-evaluator.service.ts` | E | 内部 (调用 LLM) |
| `behavior-derivation.service.ts` | E | 内部 (调用 LLM) |

**领域 E 对外接口**：
- `recommend(sessionId)` → 训练推荐列表
- `assign(recordId)` / `complete(recordId)` / `skip(recordId)`
- `evaluate(trainingId, userResponse)` → 评估结果
- IO: 入 = training:*

**领域 E 需要的外部依赖**：
- `StudentModelService.getActiveSyndromes()` → 领域 D
- `TeachingStateService.updateState()` → 领域 C (训练评估后更新症候严重度)
- `ConfigService.get()` → 共享

**⚠️ 特别注意**：当前 training.handler 直接导入 `downgradeSyndromeSeverity` 和 `pushTeachingStateUpdate`，绕过 DI。重构时必须改为通过领域 C 的接口调用。

---

#### 领域 F：Prompt（Prompt 工程）

```
目标：合并全部 Prompt 组装服务
边界：System Prompt 组装、模板加载、上下文注入、知识注入
外部通信：无直接 IPC，只被 ChatOrchestrator 和 TeachingState 调用
```

| 当前文件 | 归属 | 建议 |
|---------|------|------|
| `prompt-loader.ts` | F | 领域入口 |
| `prompt-builder.ts` | F | 内部 |
| `dynamic-context.service.ts` | F | 内部 |
| `codex.service.ts` | F | 内部 |
| `memory-capsule.service.ts` | F | 内部 |

**领域 F 对外接口**：
- `buildSystemPrompt(sessionId, context)` → 完整 System Prompt
- IO: 无 IPC，仅内部调用

**领域 F 需要的外部依赖**：
- `StudentModelService.toPromptText()` → 领域 D
- `TeachingStateService.getPromptContext()` → 领域 C
- 文件系统读取模板

---

## 3. 领域间通信模式

### 3.1 原则

```
┌──────────────────────────────────────────────────────────────┐
│  领域 A (ChatOrchestrator) 是唯一的外部入口编排者            │
│  └─→ A 依赖 B/C/D/E/F 的接口                                │
│      └─→ 接口在领域边界定义，而非直接引用服务类             │
│          └─→ 领域 B 不对领域 A 暴露内部实现                 │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 当前 vs 目标

```
当前 (网状依赖):
  ChatOrch → 11 个服务直接引用
  training.handler → teaching-state.handler (import 函数)
  StudentModel → DiagnosisService (直接引用)

目标 (星形依赖):
  ChatOrch → 领域接口 (interface, 非 class)
  领域 B → 领域 C 接口
  领域 D → 领域 B + 领域 E 接口
  IPC Handler → 领域接口 (薄调度层)
```

### 3.3 接口定义模式

```typescript
// 领域 B (Diagnosis) 对外接口
export interface IDiagnosisDomain {
  saveDiagnosis(diagnosis: DiagnosisInput, sessionId: string): Promise<DiagnosisResult>;
  getComparison(sessionId: string): Promise<ComparisonResult>;
  getDiagnoses(sessionId: string): Promise<DiagnosisResult[]>;
  getEvidenceForSyndrome(syndromeId: string, sessionId: string): Promise<EvidenceRecord[]>;
}

// 领域 C (Teaching) 对外接口
export interface ITeachingDomain {
  getState(sessionId: string): TeachingState;
  updateState(sessionId: string, patch: Partial<TeachingState>): void;
  confirmPhase(sessionId: string): PhaseConfirmResult;
  mergeProblems(sessionId: string, problems: ActiveProblem[]): MergeResult;
}

// 领域 D (Student) 对外接口
export interface IStudentDomain {
  toPromptText(sessionId: string): string;
  getProfile(sessionId: string): AbilityProfile;
  getGrowthSummary(sessionId?: string): GrowthSummary;
}

// ChatOrch 通过接口而非直接构造依赖
interface ChatOrchDeps {
  diagnosisDomain: IDiagnosisDomain;
  teachingDomain: ITeachingDomain;
  studentDomain: IStudentDomain;
  promptDomain: IPromptDomain;
  trainingDomain: ITrainingDomain;
  configService: ConfigService;  // 共享服务，不需要领域封装
  sessionService: SessionService;
  apiProxyService: ApiProxyService;
}
```

### 3.4 关于事件驱动

**不建议**在当前阶段引入领域间事件总线。原因：
- 事件订阅引入了隐式控制流，调试难度增加
- 当前架构中只有 ChatOrch → 其他领域的单向调用（没有其他领域 → ChatOrch 的回调）
- 唯一需要的「事件」已经是 IPC 事件推送（main → renderer），不涉及领域间
- 保持同步调用 + 接口抽象即可满足解耦需求

**未来如需引入事件**，时机是当出现以下情况之一时：
- 领域 B 的变更需要异步通知领域 C（当前是 ChatOrch 主动调用两方）
- 需要支持多个领域监听同一个事件（当前没有此需求）

---

## 4. 目录结构迁移计划

### 4.1 目标目录结构

```
src/main/
├── core/                          # 不变
├── ipc/                           # 薄 handler，不变
│   ├── chat.handler.ts
│   ├── session.handler.ts
│   ├── diagnosis.handler.ts
│   ├── teaching-state.handler.ts  # 修复模块级变量问题
│   ├── training.handler.ts
│   ├── config.handler.ts
│   ├── evidence.handler.ts
│   ├── ability-profile.handler.ts
│   └── manuscript.handler.ts
│
├── domains/
│   ├── chat/
│   │   ├── index.ts               # 领域入口
│   │   └── chat-orchestrator.service.ts  # 简化版 (仅编排，不承载业务逻辑)
│   │
│   ├── diagnosis/
│   │   ├── index.ts               # 领域入口 + IDiagnosisDomain
│   │   ├── diagnosis.service.ts
│   │   ├── diagnosis-parser.ts
│   │   ├── diagnosis-merger.ts
│   │   ├── diagnosis-merger-utils.ts
│   │   └── evidence/
│   │       ├── evidence.service.ts
│   │       └── evidence-grouping.ts
│   │
│   ├── teaching/
│   │   ├── index.ts               # 领域入口 + ITeachingDomain
│   │   ├── teaching-state.service.ts
│   │   ├── teaching-state/
│   │   │   ├── store.ts
│   │   │   ├── machine.ts         # 桶文件
│   │   │   ├── machine.constants.ts
│   │   │   ├── machine.navigation.ts
│   │   │   ├── machine.locking.ts
│   │   │   └── machine.reflection.ts
│   │   ├── strategy/
│   │   │   ├── router.ts          # 桶文件
│   │   │   ├── router.types.ts
│   │   │   ├── router.constants.ts
│   │   │   ├── router.conditions.ts
│   │   │   ├── router.layer1.ts
│   │   │   ├── router.layer2.ts
│   │   │   ├── router.layer3.ts
│   │   │   └── service.ts
│   │   ├── prioritizer.service.ts
│   │   ├── instruction-builder.ts
│   │   ├── dispute-tracker.service.ts
│   │   ├── reflection-gate.service.ts
│   │   └── transition-prompt-loader.ts
│   │
│   ├── student/
│   │   ├── index.ts               # 领域入口 + IStudentDomain
│   │   ├── aggregator.ts          # 新: ProfileDataAggregator
│   │   ├── student-model.service.ts
│   │   ├── student-model.types.ts
│   │   ├── student-model.utils.ts
│   │   ├── ability-profile.service.ts
│   │   ├── growth-trend.service.ts
│   │   └── student-classifier.ts
│   │
│   ├── training/
│   │   ├── index.ts               # 领域入口 + ITrainingDomain
│   │   ├── training-record.service.ts
│   │   ├── recommendation.service.ts
│   │   ├── evaluator.service.ts
│   │   └── behavior-derivation.service.ts
│   │
│   └── prompt/
│       ├── index.ts               # 领域入口 + IPromptDomain
│       ├── prompt-loader.ts
│       ├── prompt-builder.ts
│       ├── dynamic-context.service.ts
│       ├── codex.service.ts
│       └── memory-capsule.service.ts
│
└── shared/
    ├── services/
    │   ├── config.service.ts
    │   ├── session.service.ts
    │   └── api-proxy.service.ts
    └── constants.ts
```

### 4.2 迁移步骤

#### Phase 1：目录重组（仅移动，不改逻辑）

| 步骤 | 操作 | 验证 |
|------|------|------|
| 1.1 | 创建 `domains/` 目录结构 | — |
| 1.2 | 将 `services/` 下的文件移动到对应的 `domains/*/` 子目录 | — |
| 1.3 | 将 shared 服务保留在 `shared/services/` | — |
| 1.4 | 更新 `service-config.ts` 中的导入路径 | `tsc --noEmit` |
| 1.5 | 更新所有 handler 中的导入路径 | `tsc --noEmit` |
| 1.6 | 更新测试文件中的导入路径 | `vitest run` |

**注意**：Phase 1 是纯文件移动，0 逻辑变更。依赖关系和代码完全不变。

#### Phase 2：接口抽象

| 步骤 | 操作 | 风险 |
|------|------|------|
| 2.1 | 定义 6 个领域接口 (`I*Domain`) | 低 |
| 2.2 | 让每个 `domains/*/index.ts` 实现接口 | 低 |
| 2.3 | `ChatOrchestratorService` 改为通过接口依赖领域 | 中 (引用路径变更) |
| 2.4 | `service-config.ts` 通过接口注入 | 低 |
| 2.5 | 修复 `teaching-state.handler.ts` 模块级变量 | **高** (需仔细) |

#### Phase 3：内部重组

| 步骤 | 操作 | 说明 |
|------|------|------|
| 3.1 | Student 领域：抽取 `ProfileDataAggregator` | 消除 StudentModel + AbilityProfile 重复依赖 |
| 3.2 | Teaching 领域：Router 子目录整合 | — |
| 3.3 | Diagnosis 领域：Evidence 子目录整合 | — |
| 3.4 | 更新 `service-config.ts` 注册逻辑 | 从逐文件注册 → 领域级别注册 |

#### Phase 4：DI 路径修复

| 步骤 | 操作 | 说明 |
|------|------|------|
| 4.1 | `training.handler` 移除对 `teaching-state.handler` 的直接导入 | 改为通过 DI 获取 TeachingDomain |
| 4.2 | `diagnosis.handler` 中的 `processDiagnosisFromAI` 改为通过领域接口调用 | — |
| 4.3 | 验证所有导入路径无旁路 | madge 检查 |

---

## 5. 风险与收益分析

### 5.1 收益

| 维度 | 当前 | 重构后 |
|------|------|--------|
| **services/ 文件数** | 30+ 平铺 | 6 个领域子目录 |
| **ChatOrch 依赖** | 11 个直接服务引用 | 6 个领域接口 + 3 个共享服务 |
| **DI 旁路** | 2 处（teaching handler 模块变量 + training import） | 0 处 |
| **重复依赖** | StudentModel + AbilityProfile 完全一致 | 共享 ProfileDataAggregator |
| **新功能添加** | 需要理解 30+ 文件关系 | 只需理解对应领域 |
| **测试隔离** | 难以 mock 链式依赖 | 领域接口可轻松 mock |

### 5.2 风险

| 风险 | 等级 | 缓解措施 |
|------|------|---------|
| 文件移动引入导入路径错误 | 🟡 中 | Phase 1 逐批移动 + tsc 验证 |
| 模块级变量修复影响 handler 行为 | 🔴 高 | 添加集成测试覆盖关键路径 |
| ChatOrch 重构影响消息流 | 🔴 高 | 保持 ChatOrch 内部逻辑不变，只改外部接口 |
| 领域接口定义不准确导致后续修改 | 🟡 中 | 按当前使用场景最小化接口定义 |
| 团队学习成本 | 🟢 低 | 目录结构变化，不涉及框架变动 |

### 5.3 工作量估算

| Phase | 文件涉及数 | 预估工时 | 验证 |
|-------|-----------|---------|------|
| Phase 1: 目录重组 | ~35 个 | 2-3h | tsc + vitest |
| Phase 2: 接口抽象 | ~10 个 | 3-4h | tsc + vitest |
| Phase 3: 内部重组 | ~8 个 | 2-3h | tsc + vitest |
| Phase 4: DI 路径修复 | ~5 个 | 1-2h | tsc + vitest + 手动测试 |
| **总计** | **~58 个** | **8-12h** | — |

### 5.4 非必须项（明确不做的）

| 事项 | 原因 |
|------|------|
| 引入事件总线/消息队列 | 当前架构不需要异步领域通信 |
| 将 IPC handler 移入领域目录 | handler 本质是调度层，不属于任何领域 |
| 将 SQLite 表按领域拆分 | 单 DB 实例，共享表在当前规模下没有问题 |
| 将 preload 移入 domain | preload 属于安全基础设施，与业务无关 |
| 重构教学状态机的拆分文件 | 已在 FB20260613-002 中完成 |

---

## 6. 验收标准

```
□ Phase 1: 所有文件移动到新目录，tsc --noEmit = 0 error
□ Phase 1: vitest run = 全部通过
□ Phase 1: madge 检查 = 0 circular
□ Phase 2: 6 个领域接口定义完成
□ Phase 2: ChatOrch 通过接口依赖领域，非直接引用服务类
□ Phase 3: Student 领域内部去重完成
□ Phase 4: teaching-state.handler 模块级变量消除
□ Phase 4: training.handler 无 direct import teaching-state
□ Phase 4: 手动测试消息流 + 诊断 + 训练功能正常
```

---

## 附录 A：当前 DEPRECATED 标记文件

以下文件在重构中可以考虑删除（已在 Phase 4 收尾中标记为 deprecated）：

| 文件 | 替代 |
|------|------|
| `shared/constants.ts` 中的 `IPC_CHANNELS` | 已迁移到 `api-contracts/` |
| 无实际功能的骨架文件 | WritingAnalyzer / FeedbackEngine / RecommendationEngine |
