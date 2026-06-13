# 月笙写作教练 — 后端代码结构分析报告

> 生成日期：2026-06-13 | 范围：`src/main/` 下全部 TypeScript 文件

---

## 一、目录树完整结构

```
src/main/
├── index.ts                              # 入口：app.whenReady() → AppInitializer
├── api-proxy.ts                          # OpenAI 兼容 API 封装（SSE 流式 + Tool Calling）
├── core/
│   ├── app-initializer.ts                # 启动编排：DB 初始化 → 迁移 → 配置容器 → 窗口 → IPC
│   ├── service-container.ts              # 轻量 DI 容器（单例 / 延迟初始化 / 循环检测）
│   ├── service-config.ts                 # 服务注册工厂（绑定 18 个服务到容器）
│   └── window-manager.ts                 # BrowserWindow 创建（preload / Vite dev server）
├── ipc/
│   ├── chat.handler.ts                   # [964 行] 聊天核心 handler（发送/停止/流式/Tool Calling）
│   ├── config.handler.ts                 # 配置读写 + API 连接测试
│   ├── diagnosis.handler.ts             # 诊断触发 / 重写评估 / 对比查询
│   ├── evidence.handler.ts              # 证据 CRUD + 按病症/能力/链条查询
│   ├── ability-profile.handler.ts       # 能力画像查询
│   ├── manuscript.handler.ts            # 作品+章节 CRUD（直接操作 SQLite）
│   ├── session.handler.ts               # 会话 CRUD + 消息分页 / 搜索
│   ├── teaching-state.handler.ts        # 教学状态读写 + 推送 + PromptLoader 桥接
│   ├── training.handler.ts              # 训练推荐/分配/完成/跳过/评估/行为推导
│   ├── ipc-handlers.ts                  # 仅 4 行注释（占位，已废弃）
│   ├── ipc-registry.types.ts            # Handler 依赖接口类型定义
│   └── utils/
│       ├── create-handler.ts            # 统一 IPC handler 包装器（try-catch + 标准化返回值）
│       └── validate-payload.ts          # 运行时参数校验（required + types 约束）
└── services/
    ├── ability-profile.service.ts       # 跨会话能力画像计算
    ├── behavior-derivation.service.ts   # F-03 角色行为推导（调用 LLM）
    ├── codex.service.ts                 # PE-002 Codex 结构化知识注入
    ├── config.service.ts                # electron-store 配置管理 + API Key 验证 + 连接测试
    ├── diagnosis.service.ts             # 诊断结果 SQLite CRUD
    ├── diagnosis-merger.ts              # 诊断→教学状态合并 + 反思门控触发
    ├── diagnosis-merger-utils.ts        # 症候合并到 activeProblems 的纯函数
    ├── diagnosis-parser.ts              # AI 回复中 DIAGNOSIS 标记块的 JSON 解析
    ├── dispute-tracker.service.ts       # 辩驳检测 + 计数 + 态度自动升级（doubao→yuesheng→direct）
    ├── dynamic-context.service.ts       # 三段式 Prompt 组装（核心 + 按需 + 上下文）
    ├── evidence.service.ts              # 证据 SQLite CRUD
    ├── evidence-grouping.ts             # 证据按层级/类型分组
    ├── feedback-engine.ts               # Phase 2 占位：实时写作反馈（类型骨架）
    ├── growth-trend.service.ts          # T-013 跨会话症候严重度趋势 + 成长摘要
    ├── memory-capsule.service.ts        # PE-009 记忆胶囊（诊断摘要 + 进度封装）
    ├── message-router.ts                # V3 兼容层：始终返回 true（分类由 AI 完成）
    ├── mock-data-injector.ts            # 开发模式模拟诊断数据注入
    ├── problem-prioritizer.service.ts   # 症候三级分类（致命伤/结构病/皮肤症）+ 优先级排序
    ├── prompt-builder.ts                # System Prompt 构造器（三段式模板组装）
    ├── prompt-loader.ts                 # Prompt 加载主服务（铁三角 + 动态上下文 + Codex）
    ├── recommendation-engine.ts         # Phase 2 占位：综合推荐引擎（类型骨架）
    ├── reflection-gate.service.ts       # 反思门控：L2+ 症候时强制进入反思子阶段
    ├── session.service.ts               # 会话+消息 SQLite CRUD（含分页/搜索/标题更新）
    ├── session.service.test.ts          # SessionService 单元测试
    ├── student-classifier.ts            # Phase 2 占位：学员类型识别（类型骨架）
    ├── student-model.service.ts         # [708 行] 跨会话学生画像（能力等级+认知风格）
    ├── teaching-state.store.ts          # teaching_state 表 CRUD（JSON 序列化/反序列化）
    ├── teaching-state.types.ts          # TeachingState / TeachingStateRow 类型定义
    ├── teaching-state-machine.ts        # [553 行] 教学阶段流转 + 子阶段推进 + 状态验证
    ├── teaching-strategy.service.ts     # 教学模式/语气/格式决策（委托给 Router）
    ├── teaching-strategy-router.ts      # [909 行] 三层决策引擎（聚焦→方式→参数）
    ├── training-evaluator.service.ts    # 训练评估：调用 LLM 评分（1-10）
    ├── training-recommendation.service.ts # 症候→挑战模板匹配 + 技法库查询
    ├── training-record.service.ts       # 训练记录 SQLite CRUD
    ├── transition-prompt-loader.ts      # Phase 切换时的过渡 Prompt 加载
    └── writing-analyzer.ts              # Phase 2 占位：写作分析器（类型骨架）
```

---

## 二、每个 Handler 文件职责与跨文件 Import

### 2.1 chat.handler.ts（964 行 — 最大 handler）
**职责**：聊天消息发送（SSE 流式）和停止。内部实现 Tool Calling 机制（readChapter 工具）、技法库注入、教学策略指令构建、诊断触发编排。

**跨模块 import**：
| 目标模块 | 导入内容 |
|---|---|
| `../../shared/constants` | `IPC_CHANNELS` |
| `../../renderer/shared/types` | `apiSuccess, apiError, DiagnosisAnalysis, ChatMessage` 等 |
| `../api-proxy` | `ApiProxy`（默认导入） |
| `../services/diagnosis-agent` | ⚠️ 不存在（代码注释引用 `DiagnosisAgent`） |
| `../services/config.service` | `ConfigService` |
| `../services/session.service` | `SessionService` |
| `../services/diagnosis.service` | `DiagnosisService` |
| `../services/prompt-loader` | `PromptLoader` |
| `../services/message-router` | `MessageRouter` |
| `../services/student-model.service` | `StudentModelService` |
| `../services/teaching-strategy.service` | `TeachingStrategyService` |
| `../services/problem-prioritizer.service` | `ProblemPrioritizer` |
| `../services/dispute-tracker.service` | `DisputeTrackerService` |
| `../services/reflection-gate.service` | `ReflectionGateService` |
| `./diagnosis.handler` | `processDiagnosisFromAI`（⚠️ 跨 handler 直接导入） |
| `./utils/create-handler` | `createHandler` |
| `./utils/validate-payload` | `validatePayload` |

### 2.2 diagnosis.handler.ts（254 行）
**职责**：诊断触发、重写提交评估、诊断对比查询。通过 `DiagnosisMerger` 将诊断结果合并到 TeachingState。

**跨模块 import**：
| 目标模块 | 导入内容 |
|---|---|
| `../../shared/constants` | `IPC_CHANNELS, SyndromeId, ActionId` |
| `../../renderer/shared/types` | `DiagnosisEntry, apiSuccess, apiError` |
| `../api-proxy` | `ApiProxy` |
| `../services/diagnosis-parser` | `parseDiagnosisTable, reconstructDiagnosisTable` |
| `../services/reflection-gate.service` | `ReflectionGateService, ReflectionGateResult` |
| `../services/config.service` | `ConfigService` |
| `../services/diagnosis.service` | `DiagnosisService` |
| `../services/evidence.service` | `EvidenceService` |
| `../services/session.service` | `SessionService` |
| `../services/growth-trend.service` | `GrowthTrendService` |
| `./teaching-state.handler` | `getTeachingStateContext`（⚠️ 跨 handler，通过回调模式） |
| `./utils/create-handler` | `createHandler` |

### 2.3 teaching-state.handler.ts（282 行）
**职责**：管理 TeachingStateStore，提供教学状态读写、阶段推进确认、前端推送。**不使用依赖注入**，使用模块级变量 `store`/`promptBuilder`/`mainWindow`。

**跨模块 import**：
| 目标模块 | 导入内容 |
|---|---|
| `../../shared/constants` | `IPC_CHANNELS` |
| `../services/teaching-state.store` | `TeachingStateStore, CreateTeachingStateInput` |
| `../services/teaching-state-machine` | `advanceToNextSubphase, advanceToNextPhase, validateSubphase, getSupportedActionsForSubphase` |
| `../services/prompt-builder` | `PromptBuilder` |
| `../services/diagnosis-merger` | `DiagnosisMerger` |

### 2.4 training.handler.ts（211 行）
**职责**：训练推荐/分配/完成/跳过/历史/提交评估/行为推导。**🔴 耦合问题**：直接导入 `teaching-state.handler` 的 `getTeachingStateStore()` 和 `pushTeachingStateUpdate()`。

**跨模块 import**：
| 目标模块 | 导入内容 |
|---|---|
| `../../shared/constants` | `IPC_CHANNELS` |
| `../../shared/mappings` | `SYNDROME_NAMES` |
| `../../renderer/shared/types` | `ActiveProblem` |
| `../services/training-recommendation.service` | `generateRecommendations, getChallengeTemplate` |
| `../services/training-record.service` | `TrainingRecordService` |
| `../services/student-model.service` | `StudentModelService` |
| `../services/training-evaluator.service` | `evaluateTraining` |
| `../services/behavior-derivation.service` | `deriveBehavior, DerivationInput` |
| `../services/teaching-state-machine` | `downgradeSyndromeSeverity` |
| `../services/config.service` | `ConfigService` |
| `./teaching-state.handler` | `getTeachingStateStore, pushTeachingStateUpdate`（⚠️） |
| `./utils/validate-payload` | `validatePayload` |
| `./utils/create-handler` | `createHandler` |

### 2.5 config.handler.ts（79 行）
**职责**：配置读写 + API 连接测试。**耦合最低**，仅依赖 `ConfigService`。

**跨模块 import**：
| 目标模块 | 导入内容 |
|---|---|
| `../../shared/constants` | `IPC_CHANNELS` |
| `./utils/create-handler` | `createHandler` |
| `../services/config.service` | `ConfigService` |

### 2.6 session.handler.ts（160 行）
**职责**：会话 CRUD + 消息查询/分页/搜索/标题更新/新用户检测。**仅依赖 `SessionService`**。

### 2.7 evidence.handler.ts（89 行）
**职责**：证据按病症/能力/症候/诊断链条查询 + 创建。**仅依赖 `EvidenceService`**。

### 2.8 ability-profile.handler.ts（34 行）
**职责**：能力画像查询（委托给 `AbilityProfileService.computeProfile`）。**单依赖**。

### 2.9 manuscript.handler.ts（191 行）
**职责**：作品+章节 CRUD（直接 SQLite，不走独立 Service）。**仅依赖 `Database` 实例**。

---

## 三、每个 Service/Utility 文件职责

| 文件 | 行数 | 职责 |
|---|---|---|
| `config.service.ts` | 277 | electron-store 配置 CRUD、API Key 验证、OpenAI 连接测试（fetch /chat/completions） |
| `session.service.ts` | 109 | 会话表 + 消息表 SQLite CRUD（分页、全文搜索、标题更新） |
| `diagnosis.service.ts` | 110 | 诊断结果持久化（diagnosis_results 表 CRUD） |
| `evidence.service.ts` | 148 | 证据持久化（evidences 表 CRUD + 按多项条件查询） |
| `training-record.service.ts` | ~100 | 训练记录持久化（training_records 表 CRUD） |
| `student-model.service.ts` | 708 | 🔴 跨会话学生画像：proficiency×cognitiveStyle 双维度 + 症候趋势 + Prompt 注入文本 |
| `ability-profile.service.ts` | ~200 | 跨会话能力画像聚合（诊断+训练数据聚合） |
| `growth-trend.service.ts` | 185 | 跨会话症候趋势：mastered/improving/stable/needsAttention |
| `teaching-state.store.ts` | 229 | teaching_state 表 CRUD（JSON 列序列化/反序列化 + 事务） |
| `teaching-state.types.ts` | ~70 | TeachingState / TeachingStateRow 类型定义 |
| `teaching-state-machine.ts` | 553 | 教学阶段流转、子阶段推进、症候严重度降级、反思门控条件判断 |
| `teaching-strategy.service.ts` | 379 | 教学模式/语气/格式决策（委托给 TeachingStrategyRouter，自身保留 legacy 降级） |
| `teaching-strategy-router.ts` | 909 | 🔴 核心决策引擎：三层决策（聚焦症候→教学方式→参数细化），消费 6 个 JSON 配置 |
| `problem-prioritizer.service.ts` | 186 | 症候三级分类（fatal/structural/surface）+ 按 priority 排序 |
| `diagnosis-parser.ts` | 220 | 解析 AI 回复中 `---DIAGNOSIS_START/END---` 标记块的 JSON |
| `diagnosis-merger.ts` | 54 | 诊断结果 → TeachingState 合并 + 反思门控触发 |
| `diagnosis-merger-utils.ts` | ~50 | 纯函数：合并症候到 activeProblems |
| `dynamic-context.service.ts` | 363 | 三段式 Prompt：核心 Prompt + 按需症候手册 + 上下文层 |
| `prompt-builder.ts` | ~100 | System Prompt 模板组装（三段式 + 占位符替换） |
| `prompt-loader.ts` | 357 | Prompt 加载主服务：通过 setter 注入 StateContextGetter、PromptBuilder、StoreGetter、DynamicContextService、CodexService |
| `codex.service.ts` | 220 | PE-002 Codex 结构化知识注入（多源聚合+优先级排序） |
| `dispute-tracker.service.ts` | 258 | 辩驳检测（关键词+反问）+ 计数 + 态度自动升级（只升不降） |
| `reflection-gate.service.ts` | 151 | 反思门控：L2+ 触发判定 + 反思问题生成 |
| `message-router.ts` | 20 | V3 兼容层（始终返回 true，分类由 AI 自己完成） |
| `training-recommendation.service.ts` | 186 | 症候→挑战模板映射 + 技法库查询 |
| `training-evaluator.service.ts` | 113 | 调用 LLM 评分训练结果（依赖 ApiProxy + ConfigService） |
| `behavior-derivation.service.ts` | 105 | F-03 角色行为推导：调用 LLM 推演（依赖 ApiProxy + ConfigService） |
| `memory-capsule.service.ts` | 139 | PE-009 记忆胶囊：诊断摘要 + 进度封装 |
| `evidence-grouping.ts` | ~80 | 证据按层级/类型分组 |
| `transition-prompt-loader.ts` | ~50 | Phase 切换时的过渡 Prompt 加载 |
| `mock-data-injector.ts` | ~30 | 开发模式模拟诊断数据注入 |
| `student-classifier.ts` | 115 | Phase 2 类型骨架（学员类型识别） |
| `feedback-engine.ts` | 144 | Phase 2 类型骨架（实时写作反馈） |
| `writing-analyzer.ts` | 98 | Phase 2 类型骨架（写作分析器） |
| `recommendation-engine.ts` | ~80 | Phase 2 类型骨架（综合推荐引擎） |
| `api-proxy.ts` | ~180 | OpenAI 兼容 API 封装：`chatStream`（SSE）、`chatStreamWithTools`（带 function calling）、`testConnection`、`evaluateRewrite` |

---

## 四、模块间依赖图

```
                    ┌───────────────┐
                    │  index.ts     │
                    └───────┬───────┘
                            │
                    ┌───────▼───────────┐
                    │ AppInitializer    │
                    └───────┬───────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
     ┌────────▼───┐  ┌─────▼──────┐ ┌───▼──────────┐
     │WindowManager│  │ServiceConf │ │ IpcRegistry   │
     └────────────┘  │ ig (DI)    │ │ (注入所有服务) │
                     └─────┬──────┘ └───┬──────────┘
                           │            │
              ┌────────────┼────────────┤
              │            │            │
     ┌────────▼──────┐    │    ┌───────▼──────────┐
     │ 18 个 Service │    │    │  9 个 Handler     │
     │ (service层)   │◄───┘    │  (ipc层)         │
     └────────┬──────┘         └───────┬──────────┘
              │                        │
              │        ⚠️ 跨模块调用   │
              │◄──────────────────────►│
              │  training.handler 直接 │
              │  导入 teaching-state.  │
              │  handler 模块级函数    │
              └────────────────────────┘

关键服务间依赖（通过 DI 容器显式声明）：

SessionService ──► DB
DiagnosisService ──► DB
EvidenceService ──► DB
TrainingRecordService ──► DB
StudentModelService ──► DB, DiagnosisService, TrainingRecordService
AbilityProfileService ──► DB, DiagnosisService, TrainingRecordService
GrowthTrendService ──► StudentModelService
TeachingStrategyRouter ──► 6 个 JSON 配置文件
TeachingStrategyService ──► TeachingStrategyRouter (setter注入)
PromptLoader ──► DynamicContextService, CodexService, PromptBuilder (setter注入)
DiagnosisMerger ──► TeachingStateStore (回调注入)
```

---

## 五、teaching-strategy-router.ts 路由逻辑

文件：`src/main/services/teaching-strategy-router.ts`（909 行）

**三层决策引擎**：

```
RouterInput
    │
    ▼
Layer 1: selectFocusSyndrome()
    ├── 无活跃症候 → 默认路径
    ├── 单症候 → 直接聚焦
    └── 多症候选择（优先级）：
        ① R-015 高优先级症候（P006/P004）
        ② 训练评分最低的症候
        ③ syndromePriorityMap 有映射的
        ④ 严重度最高的
        ├── R-011 多症候聚焦规则
        └── 输出 FocusDecision（含 theoryReference）
    │
    ▼
Layer 2: selectTeachingMode()
    ├── 症候→类型映射（expressive_deficit/structural_disorder/motivation_deficit）
    ├── 类型→推荐入口→策略（case-driven/reflection-driven/analysis-driven）
    ├── userTypeMap → 粗粒度 mode（scaffolding/guiding/challenging）
    ├── 教育学规则细化（R-001~R-010 逐条匹配）
    └── 态度覆盖（direct→challenging, doubao→降级）
    │
    ▼
Layer 3: refineParameters()
    ├── learning-path.json → phaseId + corePatterns
    ├── syndromeOverrideMap → 症候专属模式
    ├── coaching-templates.json → 匹配模板
    └── 输出 ParameterDecision（含 stepSequence, practiceType, toneProfile）
    │
    ▼
RouterOutput { targetSyndrome, teachingMode, parameters, compatibleWithLegacy }
```

**配置来源**（6 个 JSON 文件，通过 `resourcesRoot/config/` 加载）：
- `education-theory-fragments.json` — 教育理论规则（R-001~R-015）
- `learning-path.json` — 学习路径（beginner/intermediate/advanced）
- `technique-selection-matrix.json` — 技法优先级矩阵
- `coaching-templates.json` — 教练模板
- `user-type-map.json` — 用户类型→教学模式映射
- `syndrome-type-map.json` — 症候→类型→推荐入口映射

---

## 六、OpenAI/外部 API 调用方式

所有 LLM 调用通过 `src/main/api-proxy.ts` 的 `ApiProxy` 类统一封装：

| 方法 | 调用方式 | 使用场景 |
|---|---|---|
| `chatStream()` | SSE 流式（`fetch` + `ReadableStream`） | 主聊天消息 |
| `chatStreamWithTools()` | SSE 流式 + function calling | Tool Calling（readChapter 工具） |
| `testConnection()` | 同步 POST（`fetch` `/chat/completions`） | 配置测试 |
| `evaluateRewrite()` | 同步 POST | 改写评估 |

**调用链**：
1. `chat.handler.ts` → `new ApiProxy(config).chatStream(...)` → 前端通过 `chat:stream:data` 通道接收 SSE chunk
2. `chat.handler.ts` → `new ApiProxy(config).chatStreamWithTools(...)` → Tool Calling 执行 → 二次调用
3. `training-evaluator.service.ts` → `new ApiProxy(config).evaluateRewrite(...)` 或独立 fetch
4. `behavior-derivation.service.ts` → `new ApiProxy(config)` + 独立 fetch
5. `config.service.ts` → 直接 `fetch`（非 ApiProxy）测试连接

**特点**：每次调用都新建 `ApiProxy` 实例，传入最新的 `ApiConfig`。没有全局单例或连接池。

---

## 七、IPC 注册方式

### 7.1 核心文件

| 文件 | 职责 |
|---|---|
| `core/ipc-registry.ts` | `IpcRegistry.registerAll()` 从 ServiceContainer 获取 15 个服务实例，注入到 9 个 handler 的 `init*` 函数中 |
| `ipc/utils/create-handler.ts` | 统一 `ipcMain.handle()` 包装器，自动 try-catch + `{success, data, error}` 标准化返回 |
| `ipc/utils/validate-payload.ts` | 运行时参数校验（`required` + `types` 约束） |
| `shared/constants.ts` | 定义 ~45 个 IPC 通道名 + 白名单（`ALLOWED_INVOKE_CHANNELS` 41 个 + `ALLOWED_EVENT_CHANNELS` 5 个） |

### 7.2 注册模式（两种）

**模式 A：DI 注入（大多数 handler）**
```typescript
// ipc-registry.ts
initChatHandlers({ configService, sessionService, ... });  // 注入 deps
registerChatHandlers();  // 注册 ipcMain.handle()
```

**模式 B：模块级变量（teaching-state.handler 特有）**
```typescript
// teaching-state.handler.ts
let store: TeachingStateStore;       // 模块级变量，非 DI
let promptBuilder: PromptBuilder;    // 模块级变量，非 DI
let mainWindow: BrowserWindow | null; // 模块级变量，非 DI

export function initStore(db) { store = new TeachingStateStore(db); }
```

### 7.3 Handler 依赖统计

| Handler | 依赖服务数 | 特殊依赖 |
|---|---|---|
| chat | 10 + db | 最多 |
| diagnosis | 6 + merger + window | diagnosisMerger（回调模式） |
| training | 3 | ⚠️ 直接导入 teaching-state.handler 模块级函数 |
| teaching-state | 0（模块级变量） | ⚠️ 不使用 DI 模式 |
| session | 1 | 最少 |
| config | 1 | 最少 |
| evidence | 1 | — |
| ability-profile | 1 | — |
| manuscript | 1（db 实例） | 直接 SQLite |

---

## 八、当前最大的后端模块耦合问题

### 🔴 P0 — chat.handler.ts：God Handler（问题 #1）

**位置**：`src/main/ipc/chat.handler.ts`（964 行）

**问题**：单个 handler 集成了聊天发送、SSE 流处理、Tool Calling 执行、技法注入、教学策略指令构建、诊断编排、辩驳检测、反思控制等所有逻辑。依赖 13 个外部服务 + 直接导入 `diagnosis.handler.processDiagnosisFromAI`。

**影响**：修改任何子功能（如技法注入逻辑）都需改动 chat.handler。无法独立测试 Tool Calling 或策略指令构建。

### 🔴 P0 — teaching-state.handler 模块级变量反模式（问题 #2）

**位置**：`src/main/ipc/teaching-state.handler.ts`

**问题**：使用模块级变量 `store`/`promptBuilder`/`mainWindow` 代替依赖注入。其他 handler（training.handler、diagnosis.handler）通过导入 `getTeachingStateStore()` 和 `pushTeachingStateUpdate()` 直接访问这些变量。

**实际耦合链**：
```
training.handler → import { getTeachingStateStore } from './teaching-state.handler'
                  → 访问模块级 store 变量
                  → 直接调用 store.update() 修改数据
```

这与前端的 `store.getState()` 问题等价：任何模块都可以导入并直接操作教学状态，绕过了 TeachingStateStore 的封装。

### 🔴 P0 — ipc-registry.ts 回调桥接反模式（问题 #3）

**位置**：`src/main/core/ipc-registry.ts` 第 65-67 行

```typescript
let diagnosisMerger!: DiagnosisMerger;
registerDiagnosisMerger((m) => { diagnosisMerger = m; });
```

**问题**：通过 `registerDiagnosisMerger` 注册回调在运行时延迟绑定 DiagnosisMerger，然后通过闭包传给 diagnosis.handler。这是为了解决 teaching-state.handler 不使用 DI 的连锁问题：因为 TeachingStateStore 在模块级变量中，无法通过 DI 容器正常获取，只能通过回调桥接。

### 🟡 P1 — training.handler 直接修改 TeachingState（问题 #4）

**位置**：`src/main/ipc/training.handler.ts` 第 172-189 行

```typescript
const teachingStateStore = getTeachingStateStore();
const state = teachingStateStore.getBySession(validation.data.sessionId);
if (state) {
  const { activeProblems } = downgradeSyndromeSeverity(state, validation.data.syndromeId, result.score);
  teachingStateStore.update(validation.data.sessionId, { activeProblems });
  pushTeachingStateUpdate(validation.data.sessionId);
}
```

**问题**：training.handler 在训练评估完成后直接修改 TeachingState，这是跨领域写操作。该操作应通过 TeachingStrategyService 或独立的协调服务完成。

### 🟡 P1 — ServiceConfig 深层服务依赖链（问题 #5）

**位置**：`src/main/core/service-config.ts`

**问题**：`StudentModelService` 同时依赖 `DiagnosisService` 和 `TrainingRecordService`；`AbilityProfileService` 同样依赖两者。这两个聚合服务与底层 CRUD 服务紧耦合，难以独立测试。

### 🟢 P2 — PromptLoader 的 Setter 注入地狱（问题 #6）

**位置**：`src/main/core/service-config.ts` 第 78-89 行

```typescript
loader.setStateContextGetter((sessionId) => { ... });
loader.setPromptBuilder(c.get<PromptBuilder>('promptBuilder'));
loader.setStoreGetter(getStoreForPromptLoader);
loader.setDynamicContextService(c.get<DynamicContextService>('dynamicContextService'));
loader.setCodexService(c.get<CodexService>('codexService'));
```

**问题**：PromptLoader 通过 5 个 setter 注入依赖，而非构造函数。增加了"使用前必须正确初始化"的隐性契约。

---

## 九、问题总结与重构建议优先级

| 优先级 | 问题 | 位置 | 建议 |
|---|---|---|---|
| 🔴 P0 | chat.handler God Handler | ipc/chat.handler.ts | 拆分为 ChatOrchestrator + ToolCallingService + StrategyInstructionBuilder |
| 🔴 P0 | teaching-state 模块级变量 | ipc/teaching-state.handler.ts | 将 TeachingStateStore 注册到 DI 容器，handler 改为标准 DI 模式 |
| 🔴 P0 | ipc-registry 回调桥接 | core/ipc-registry.ts | 消除 teaching-state 的模块级变量后可自然消除 |
| 🟡 P1 | training.handler 跨域写 TeachingState | ipc/training.handler.ts | 通过 TeachingStateMachine 或协调服务完成 |
| 🟡 P1 | ServiceConfig 深层依赖链 | core/service-config.ts | StudentModel/AbilityProfile 改为依赖接口而非具体实现 |
| 🟢 P2 | PromptLoader setter 注入地狱 | core/service-config.ts | 改为构造函数注入，创建 PromptLoaderFactory |
| 🟢 P2 | ApiProxy 每次新建无复用 | api-proxy.ts | 考虑连接池或单例模式（非紧急） |

---

*报告完成。所有文件路径相对于 `D:\ai-teacher\yuesheng-writing-coach\src\main\`。*
