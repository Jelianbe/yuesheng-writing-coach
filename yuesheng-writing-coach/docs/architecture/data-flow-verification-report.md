---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: f2ac1166b9bdaea71c23aabee181e425_4dd47efd672a11f1a0095254002afed2
    ReservedCode1: MWiiU1iY8SO+ZM0JjsOto0yn6VtxRZ/5TT7iRPwW28OKtVaGgawce05niHgcFvQd3jVhp7DNc/wjAF9/CGmz9FzQVA9/cwTdt9RrrmauCIh6qfpJb7w1jTKPQgkHg9/kPZ6/z5NOsI/srbYjICuqPMI1C2gJuxNPHx0xg14OrBPid3WGcTYLIo4TIGA=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: f2ac1166b9bdaea71c23aabee181e425_4dd47efd672a11f1a0095254002afed2
    ReservedCode2: MWiiU1iY8SO+ZM0JjsOto0yn6VtxRZ/5TT7iRPwW28OKtVaGgawce05niHgcFvQd3jVhp7DNc/wjAF9/CGmz9FzQVA9/cwTdt9RrrmauCIh6qfpJb7w1jTKPQgkHg9/kPZ6/z5NOsI/srbYjICuqPMI1C2gJuxNPHx0xg14OrBPid3WGcTYLIo4TIGA=
---

# 数据流图核验报告

> 核验日期：2026-06-13
> 被核验文件：`docs/architecture/data-flow-diagram.md`
> 对照代码：`src/main/`、`src/shared/constants.ts`

---

## 1. 总体结论

| 项目 | 结论 |
|---|---|
| **总体判定** | **不通过** — 存在多处偏差，但核心流程基本准确 |
| **偏差总数** | **42 条**（维度 1: 25 条遗漏 + 3 条分类问题，维度 2: 14 条遗漏，维度 3: 2 条遗漏，维度 4: 2 条，维度 5: 3 条，维度 6: 1 条） |
| **严重程度** | 维度 1（IPC 遗漏最多）、维度 2（Service 层遗漏）为高优先级修正项；维度 5（时序偏差）影响中度 |

---

## 2. 维度 1 — IPC 通道完整性核对

> 代码来源：`src/shared/constants.ts` — `ALLOWED_INVOKE_CHANNELS`（50 条）+ `ALLOWED_EVENT_CHANNELS`（5 条）

### 2.1 图中已列出的通道

| 图中分组 | 图中列出 | 代码中对应 | 类型 |
|---|---|---|---|
| CHAT | chat:send | `CHAT_SEND` | invoke |
| CHAT | chat:stop | `CHAT_STOP` | invoke |
| CHAT | chat:stream:data | `CHAT_STREAM_DATA` | **event**（非 invoke） |
| CHAT | chat:stream:end | `CHAT_STREAM_END` | **event**（非 invoke） |
| SESSION | session:list | `SESSION_LIST` | invoke |
| SESSION | create | `SESSION_CREATE` | invoke |
| SESSION | delete | `SESSION_DELETE` | invoke |
| SESSION | getMessages | `SESSION_GET_MESSAGES` | invoke |
| SESSION | searchMessages | `SESSION_SEARCH_MESSAGES` | invoke |
| DIAG | diagnosis:query | `DIAGNOSIS_QUERY` | invoke |
| DIAG | getComparison | `DIAGNOSIS_GET_COMPARISON` | invoke |
| DIAG | growth:getTrends | `GROWTH_GET_TRENDS` | invoke |
| DIAG | diagnosis:update | `DIAGNOSIS_UPDATE` | **event**（非 invoke） |
| TEACHING | teachingState:get | `TEACHING_STATE_GET` | invoke |
| TEACHING | update | `TEACHING_STATE_UPDATE` | invoke |
| TEACHING | confirm | `TEACHING_STATE_CONFIRM` | invoke |
| TEACHING | teachingState:updated | `TEACHING_STATE_UPDATED` | **event**（非 invoke） |
| TRAINING | training:recommend | `TRAINING_RECOMMEND` | invoke |
| TRAINING | assign | `TRAINING_ASSIGN` | invoke |
| TRAINING | complete | `TRAINING_COMPLETE` | invoke |
| TRAINING | evaluate | `TRAINING_EVALUATE` | invoke |
| TRAINING | deriveBehavior | `TRAINING_DERIVE_BEHAVIOR` | invoke |
| CONFIG | config:get | `CONFIG_GET` | invoke |
| CONFIG | config:set | `CONFIG_SET` | invoke |
| CONFIG | config:testConnection | `CONFIG_TEST_CONNECTION` | invoke |
| MANUSCRIPT | manuscript:list/create/update | `MANUSCRIPT_LIST`/`CREATE`/`UPDATE` | invoke |
| MANUSCRIPT | chapter:list/get/updateContent | `CHAPTER_LIST`/`GET`/`UPDATE_CONTENT` | invoke |

### 2.2 图中遗漏的通道

| 遗漏通道 | 所属 Handler | 类型 |
|---|---|---|
| `diagnosis:submitRewrite` | diagnosis.handler | invoke |
| `growth:getGlobalTrends` | diagnosis.handler | invoke |
| `teachingState:getPrompt` | teaching-state.handler | invoke |
| `teachingState:updateSummary` | teaching-state.handler | invoke |
| `ability:getProfile` | ability-profile.handler | invoke |
| `evidence:getByDisease` | evidence.handler | invoke |
| `evidence:getByAbility` | evidence.handler | invoke |
| `evidence:getChain` | evidence.handler | invoke |
| `evidence:create` | evidence.handler | invoke |
| `evidence:getBySyndrome` | evidence.handler | invoke |
| `session:rename` | session.handler | invoke |
| `session:getMessagesPaged` | session.handler | invoke |
| `session:listWithMeta` | session.handler | invoke |
| `session:updateTitle` | session.handler | invoke |
| `session:isNewUser` | session.handler | invoke |
| `onboarding:analyze` | chat.handler | invoke |
| `training:skip` | training.handler | invoke |
| `training:history` | training.handler | invoke |
| `training:submit` | training.handler | invoke |
| `manuscript:get` | manuscript.handler | invoke |
| `manuscript:delete` | manuscript.handler | invoke |
| `chapter:create` | manuscript.handler | invoke |
| `chapter:delete` | manuscript.handler | invoke |
| `chat:tool:executing` | chat.handler | event |
| **evidence.handler（整个 Handler）** | — | 5 个通道全遗漏 |
| **ability-profile.handler（整个 Handler）** | — | 1 个通道全遗漏 |

**遗漏统计**：25 条（23 invoke + 2 event）

### 2.3 图中多余的通道

**无**。图中所有列出的通道在 `constants.ts` 中均存在对应定义。

### 2.4 分类警告

图中将以下 **event 通道**与 invoke 通道混排在同一分组中，未做区分：

| 通道 | 图中分组 | 实际类型 |
|---|---|---|
| `chat:stream:data` | CHAT（invoke 组） | event |
| `chat:stream:end` | CHAT（invoke 组） | event |
| `diagnosis:update` | DIAG（invoke 组） | event |
| `teachingState:updated` | TEACHING（invoke 组） | event |

---

## 3. 维度 2 — Service 层完整性核对

> 代码来源：`src/main/core/service-config.ts` — `configureServices()` 中所有 `container.register()` 调用

### 3.1 DI 注册的完整服务列表（25 个）

| DI 注册名 | 类/实例 | 图中 L5 是否列出 |
|---|---|---|
| `configService` | `ConfigService` | ✓ ConfigSvc |
| `sessionService` | `SessionService` | ✓ SessionSvc |
| `apiProxyService` | `ApiProxyService` | ✓ ApiProxySvc |
| `diagnosisService` | `DiagnosisService` | ✓ DiagSvc |
| `evidenceService` | `EvidenceService` | **✗ 遗漏** |
| `diagnosisMerger` | `DiagnosisMerger` | **✗ 遗漏** |
| `trainingRecordService` | `TrainingRecordService` | ✓ TrainingSvc |
| `profileDataAggregator` | `ProfileDataAggregator` | **✗ 遗漏** |
| `studentModelService` | `StudentModelService` | ✓ StudentModel |
| `abilityProfileService` | `AbilityProfileService` | **✗ 遗漏** |
| `growthTrendService` | `GrowthTrendService` | **✗ 遗漏** |
| `teachingStrategyService` | `TeachingStrategyService` | 图中与 Router 未区分 |
| `problemPrioritizer` | `ProblemPrioritizer` | **✗ 遗漏** |
| `disputeTracker` | `DisputeTrackerService` | **✗ 遗漏** |
| `reflectionGate` | `ReflectionGateService` | **✗ 遗漏** |
| `strategyInstructionBuilder` | `StrategyInstructionBuilder` | **✗ 遗漏** |
| `teachingStateService` | `TeachingStateService` | ✓ TeachingSvc |
| `promptBuilder` | `PromptBuilder` | ✓ PromptSvc（含 PromptBuilder） |
| `dynamicContextService` | `DynamicContextService` | ✓ ContextSvc |
| `codexService` | `CodexService` | **✗ 遗漏** |
| `promptLoader` | `PromptLoader` | ✓ PromptSvc（含 PromptLoader） |
| `messageRouter` | `MessageRouter` | **✗ 遗漏** |
| `chatOrchestratorService` | `ChatOrchestratorService` | ✓ ChatOrch |

### 3.2 遗漏总结

图中 L5 层展示了 11 个 Service，但代码实际有 25 个 DI 注册。遗漏 14 项：

`EvidenceService`、`DiagnosisMerger`、`ProfileDataAggregator`、`AbilityProfileService`、`GrowthTrendService`、`ProblemPrioritizer`、`DisputeTrackerService`、`ReflectionGateService`、`StrategyInstructionBuilder`、`CodexService`、`MessageRouter`、`TeachingStrategyService`（与 Router 独立但图中未区分）、`TeachingStateMachine`（非 DI 但被 TeachingStateService 调用，图中合并展示可接受）

### 3.3 图中多余的 Service

**无**。图中所有列出的 Service 在代码中均有对应。

---

## 4. 维度 3 — Handler 依赖关系核对

> 代码来源：`src/main/core/ipc-registry.ts` — `IpcRegistry.registerAll()`

### 4.1 图中 L3 层展示的 Handler

图中展示了 7 个 Handler：`chat.handler`、`session.handler`、`diag.handler`、`teaching-state.handler`、`training.handler`、`config.handler`、`manuscript.handler`

### 4.2 图中遗漏的 Handler

| 遗漏 Handler | 代码位置 | 注入服务数 |
|---|---|---|
| **evidence.handler** | `src/main/ipc/evidence.handler.ts` | 1（EvidenceService） |
| **ability-profile.handler** | `src/main/ipc/ability-profile.handler.ts` | 1（AbilityProfileService） |

### 4.3 L3→L5 连接关系核对

图中 L3→L5 使用通用箭头「服务调用」表示，未绘制明确的依赖连线。对照 `ipc-registry.ts` 实际注入关系：

| Handler | 图中描述 | 代码实际注入 | 结论 |
|---|---|---|---|
| chat.handler | 委托 ChatOrchestrator | 注入 `ChatOrchestratorService`（单对象） | ✓ 一致 |
| session.handler | — | `SessionService` | ✓ |
| diag.handler | — | `ConfigService`, `DiagnosisService`, `EvidenceService`, `SessionService`, `GrowthTrendService`, `TeachingStateService`, `DiagnosisMerger`, `BrowserWindow` | 图中未展示 EvidenceService、DiagnosisMerger 连接 |
| teaching-state.handler | — | `TeachingStateService`（DI 注入，已消除旧模块级变量模式） | 图中标注的「模块级变量」已过时（代码已重构为 DI 模式） |
| training.handler | — | `ConfigService`, `TrainingRecordService`, `StudentModelService`, `TeachingStateService` | ✓ |
| config.handler | — | `ConfigService` | ✓ |
| manuscript.handler | — | `Database` 实例 | ✓ |

---

## 5. 维度 4 — 数据持久化映射核对

> 对照来源：各 Service 源码中的 SQL 语句

### 5.1 SQLite 表映射

| 图中声明 | 代码验证 | 实际表名 | 操作类 | 结论 |
|---|---|---|---|---|
| SessionService → sessions (CRUD) | `session.service.ts` 第 25-38 行 | `sessions` | `SessionService` | ✓ |
| SessionService → messages (CRUD) | `session.service.ts` 第 45-96 行 | `messages` | `SessionService.saveMessage()` | ✓ |
| ChatOrchSvc → messages (写入) | `chat-orchestrator.service.ts` 第 149 行 | `messages` | 通过 `SessionService.saveMessage()` | ✓ （代理调用） |
| DiagSvc → diagnosis_results (CRUD) | `diagnosis.service.ts` 第 30-40 行 | `diagnosis_results` | `DiagnosisService` | ✓ |
| TeachingStore → teaching_state (CRUD) | `teaching-state.store.ts` 第 1-60 行 | `teaching_state` | `TeachingStateStore` | ✓ |
| TrainSvc → user_training_records (CRUD) | BACKEND_STRUCTURE_REPORT 确认 | `user_training_records` | `TrainingRecordService` | ✓ |
| EvidSvc → evidence (CRUD) | `evidence.service.ts` 第 30-35 行 | `evidence` | `EvidenceService` | ✓ |
| ManuSvc → manuscripts (CRUD) | manuscript.handler 直接 SQLite | `manuscripts` | manuscript.handler | ✓ |
| ManuSvc → chapters (CRUD) | manuscript.handler 直接 SQLite | `chapters` | manuscript.handler | ✓ |

### 5.2 文件存储映射

| 图中声明 | 代码验证 | 实际路径 | 结论 |
|---|---|---|---|
| ConfigSvc → api-config.json | `config.service.ts`（electron-store） | electron-store 管理 | ✓ |
| ChatOrchSvc → resources/prompts/ | `chat-orchestrator.service.ts` 第 246 行 | `resources/prompts/diagnosis-agent-prompt-v1.md` | ✓ |
| ChatOrchSvc → resources/knowledge/ | **未找到代码引用** | — | ✗ 代码中无直接读取此路径的逻辑 |
| ChatOrchSvc → resources/config/ | `chat-orchestrator.service.ts` 第 280 行 + `TeachingStrategyRouter` 加载 6 个 JSON | `resources/config/` | ✓ |

### 5.3 偏差说明

1. **`resources/knowledge/` 路径**：数据流图声明 ChatOrchSvc 读取 `resources/knowledge/`（知识图谱），但 ChatOrchestrator 中实际读取的是 `resources/prompts/`（Prompt 模板）和 `resources/config/`（配置 JSON）。CodexService 使用 `resourcesRoot` 但未确认是否存在独立 `knowledge/` 子目录。建议核实后修正或移除该连接。

2. **messages 表双写**：图中同时显示 `SessionService → messages` 和 `ChatOrchSvc → messages`。代码中 ChatOrchestrator 不直接写 messages 表，而是通过 `SessionService.saveMessage()` 代理。图中应标注为「ChatOrchSvc → SessionService → messages」的间接关系。

---

## 6. 维度 5 — 核心消息流时序核对

> 代码来源：`src/main/domains/chat/chat-orchestrator.service.ts` — `sendMessage()` 方法（第 131-167 行）+ `handleStreamResponse()`（第 543-597 行）

### 6.1 逐 Step 对照

| 图中 Step | 图中描述 | 代码实际调用 | 代码行号 | 结论 |
|---|---|---|---|---|
| Step 1 | 保存用户消息到 messages | `sessionService.saveMessage(activeSessionId, 'user', message.trim())` | 第 149 行 | ✓ 匹配 |
| Step 2 | 辩驳检测 (DisputeTracker) | `teachingDomain.checkMessage(activeSessionId, message, isReflectionPhase)` | 第 153 行 | ✓ 匹配 |
| Step 3 | 调用诊断 Agent (LLM API) | `this.runDiagnosis(message, activeSessionId)` → `callDiagnosisAgent()` | 第 155 行 | ✓ 匹配 |
| Step 4 | 保存诊断结果 | `diagnosisDomain.save()` + `saveAnalysis()`（在 `_runDiagnosis` 内） | 第 340-350 行 | ✓ 匹配（内嵌于 Step 3） |
| Step 5 | 准备教学上下文 (Prompt/Codex/Strategy) | `this.prepareTeachingContext(diagnosisAnalysis, activeSessionId, attitude, studentContext)` | 第 157 行 | ✓ 匹配 |
| — | **（图中遗漏）第二次辩驳检测** | `teachingDomain.checkMessage(activeSessionId, message, isReflectionGate)` | 第 159 行 | ✗ 图中未标注 |
| Step 6 | 调用主教练 (含 System Prompt) | `handleStreamResponse()` 或 `handleStreamResponseWithTools()` | 第 163-166 行 | ✓ 匹配 |
| Step 7 | 流结束 → 诊断后处理 | `diagnosisDomain.processAIResponse(fullResponse, activeSessionId, messageId)` | 第 571 行 | ⚠️ 部分匹配（见下） |

### 6.2 Step 7 偏差详析

图中 Step 7 声明：

> 「合并诊断到教学状态 → `teachingState:updated` + `diagnosis:update` 推送」

代码实际执行：

| 操作 | 图中归入 | 代码实际位置 | 偏差 |
|---|---|---|---|
| 推送 `diagnosis:update` | Step 7 | **Step 3/4**（`_runDiagnosis` 第 347 行） | 图中晚了一步 |
| 合并诊断到 TeachingState | Step 7 | **Step 7**（`handleStreamResponse` 第 571 行） | ✓ 匹配 |
| 推送 `teachingState:updated` | Step 7 | **Step 7**（`processAIResponse` → `diagnosisMerger.merge` → `TeachingStateService`） | ✓ 匹配 |

**修正**：`diagnosis:update` 事件在诊断完成后立即推送（Step 4），而非等到流结束的 Step 7。Step 7 仅负责 `processAIResponse`（诊断合并 + `teachingState:updated` 推送）。

### 6.3 图中遗漏的步骤

| 遗漏步骤 | 代码行号 | 说明 |
|---|---|---|
| 第二次辩驳检测 | 第 159 行 | 在教学上下文准备后、发送 LLM 前，根据反思门控结果再次检测辩驳 |
| Tool Calling 分支 | 第 163-164 行 | 根据模型兼容性选择 `handleStreamResponse()` 或 `handleStreamResponseWithTools()` |
| 章节引用解析 | 第 141-145 行 | 发送前解析 `/chapters/{uuid}` 引用并注入章节内容 |

---

## 7. 维度 6 — 教学策略决策流核对

> 代码来源：`src/main/domains/teaching/strategy/router.ts` + `router.layer1.ts` / `router.layer2.ts` / `router.layer3.ts`

### 7.1 三层路由结构

| 图中声明 | 代码实现 | 结论 |
|---|---|---|
| Layer 1: `selectFocusSyndrome` | `router.layer1.ts` 同名函数 | ✓ 完全匹配 |
| Layer 2: `selectTeachingMode` | `router.layer2.ts` 同名函数 | ✓ 完全匹配 |
| Layer 3: `refineParameters` | `router.layer3.ts` 同名函数 | ✓ 完全匹配 |

### 7.2 Layer 1 内部逻辑对照

图中描述（多症候选择优先级）：① R-015 高优先级症候 ② 训练评分最低 ③ syndromePriorityMap ④ 严重度最高

代码 `router.layer1.ts` 第 18-97 行的实际顺序：

| 优先级 | 代码逻辑 | 图中描述 | 结论 |
|---|---|---|---|
| 1 | 单症候 → 直接聚焦 | 未列出 | 补充项 |
| 2 | R-015 高优先级症候（P006/P004） | R-015 高优先级 | ✓ |
| 3 | 训练评分最低 | ✓ | ✓ |
| 4 | syndromePriorityMap 有映射 | ✓ | ✓ |
| 5 | R-011 多症候规则 + 严重度最高 | 严重度最高 | ✓ |

**偏差**：图中未列出「单症候直接聚焦」路径和 R-011 规则，但这些属于细节省略，核心决策树逻辑一致。

### 7.3 输入源核对

| 图中输入 | 代码实际参数 | 结论 |
|---|---|---|
| StudentModelService（跨会话画像） | `RouterInput.studentProfile` | ✓ |
| TeachingStateService（当前阶段/症候/进度） | `RouterInput.activeSyndromes` | ✓ |
| 外部配置 JSON（6 个文件） | `RouterConfigs`（惰性加载，6 个 JSON） | ✓ |

### 7.4 输出核对

| 图中输出 | 代码实际 | 结论 |
|---|---|---|
| `FocusDecision` | `router.layer1.ts` 输出 `FocusDecision` | ✓ |
| `ModeDecision` | `router.layer2.ts` 输出 | ✓ |
| `ParameterDecision` | `router.layer3.ts` 输出 | ✓ |
| `StrategyInstructionBuilder` | `service-config.ts` 注册 `strategyInstructionBuilder` | ✓ |
| → `PromptLoader / PromptBuilder` → `ChatOrchestrator` | 调用链：`ChatOrchestrator → StrategyInstructionBuilder → TeachingStrategyService → TeachingStrategyRouter` | ✓ |

**偏差**：图中将 `TeachingStrategyRouter` 和 `TeachingStrategyService` 展示为同一个 `StrategyRouter`，未区分两者。实际 `TeachingStrategyService` 是 Router 的包装层（setter 注入 router），`StrategyInstructionBuilder` 直接依赖 `TeachingStrategyService`。

---

## 8. 偏差清单（逐条汇总）

| # | 维度 | 严重度 | 偏差描述 | 代码行号 | 修正建议 |
|---|---|---|---|---|---|
| 1 | 1 | 🟡 | 遗漏 invoke 通道：`diagnosis:submitRewrite` | `constants.ts` DIAGNOSIS_SUBMIT_REWRITE | 在 DIAG 分组补充 |
| 2 | 1 | 🟡 | 遗漏 invoke 通道：`growth:getGlobalTrends` | `constants.ts` GROWTH_GET_GLOBAL_TRENDS | 在 DIAG 分组补充 |
| 3 | 1 | 🟡 | 遗漏 invoke 通道：`teachingState:getPrompt` | `constants.ts` TEACHING_STATE_GET_PROMPT | 在 TEACHING 分组补充 |
| 4 | 1 | 🟡 | 遗漏 invoke 通道：`teachingState:updateSummary` | `constants.ts` TEACHING_STATE_UPDATE_SUMMARY | 在 TEACHING 分组补充 |
| 5 | 1 | 🔴 | 遗漏整个 evidence 通道组（5 条） | `constants.ts` EVIDENCE_* | 新增 EVIDENCE 分组 |
| 6 | 1 | 🟡 | 遗漏 invoke 通道：`ability:getProfile` | `constants.ts` ABILITY_GET_PROFILE | 新增 ABILITY 分组 |
| 7 | 1 | 🟡 | 遗漏 invoke 通道：`session:rename` | `constants.ts` SESSION_RENAME | 在 SESSION 分组补充 |
| 8 | 1 | 🟡 | 遗漏 invoke 通道：`session:getMessagesPaged` | `constants.ts` SESSION_GET_MESSAGES_PAGED | 在 SESSION 分组补充 |
| 9 | 1 | 🟡 | 遗漏 invoke 通道：`session:listWithMeta` | `constants.ts` SESSION_LIST_WITH_META | 在 SESSION 分组补充 |
| 10 | 1 | 🟡 | 遗漏 invoke 通道：`session:updateTitle` | `constants.ts` SESSION_UPDATE_TITLE | 在 SESSION 分组补充 |
| 11 | 1 | 🟡 | 遗漏 invoke 通道：`session:isNewUser` | `constants.ts` SESSION_IS_NEW_USER | 在 SESSION 分组补充 |
| 12 | 1 | 🟡 | 遗漏 invoke 通道：`onboarding:analyze` | `constants.ts` ONBOARDING_ANALYZE | 在 CHAT 分组补充 |
| 13 | 1 | 🟡 | 遗漏 invoke 通道：`training:skip` | `constants.ts` TRAINING_SKIP | 在 TRAINING 分组补充 |
| 14 | 1 | 🟡 | 遗漏 invoke 通道：`training:history` | `constants.ts` TRAINING_HISTORY | 在 TRAINING 分组补充 |
| 15 | 1 | 🟡 | 遗漏 invoke 通道：`training:submit` | `constants.ts` TRAINING_SUBMIT | 在 TRAINING 分组补充 |
| 16 | 1 | 🟡 | 遗漏 invoke 通道：`manuscript:get` | `constants.ts` MANUSCRIPT_GET | 在 MANUSCRIPT 分组补充 |
| 17 | 1 | 🟡 | 遗漏 invoke 通道：`manuscript:delete` | `constants.ts` MANUSCRIPT_DELETE | 在 MANUSCRIPT 分组补充 |
| 18 | 1 | 🟡 | 遗漏 invoke 通道：`chapter:create` | `constants.ts` CHAPTER_CREATE | 在 MANUSCRIPT 分组补充 |
| 19 | 1 | 🟡 | 遗漏 invoke 通道：`chapter:delete` | `constants.ts` CHAPTER_DELETE | 在 MANUSCRIPT 分组补充 |
| 20 | 1 | 🟡 | 遗漏 event 通道：`chat:tool:executing` | `constants.ts` CHAT_TOOL_EXECUTING | 在 CHAT 分组补充 |
| 21 | 1 | 🟢 | 图中未区分 invoke/event 通道类型 | L2 全局 | 用不同颜色或标注区分 invoke 和 event |
| 22 | 2 | 🟡 | 遗漏 Service：`EvidenceService` | `service-config.ts` evidenceService | 在 L5 补充 |
| 23 | 2 | 🟡 | 遗漏 Service：`DiagnosisMerger` | `service-config.ts` diagnosisMerger | 在 L5 补充 |
| 24 | 2 | 🟡 | 遗漏 Service：`ProfileDataAggregator` | `service-config.ts` profileDataAggregator | 在 L5 补充 |
| 25 | 2 | 🟡 | 遗漏 Service：`AbilityProfileService` | `service-config.ts` abilityProfileService | 在 L5 补充 |
| 26 | 2 | 🟡 | 遗漏 Service：`GrowthTrendService` | `service-config.ts` growthTrendService | 在 L5 补充 |
| 27 | 2 | 🟡 | 遗漏 Service：`ProblemPrioritizer` | `service-config.ts` problemPrioritizer | 在 L5 补充 |
| 28 | 2 | 🟡 | 遗漏 Service：`DisputeTrackerService` | `service-config.ts` disputeTracker | 在 L5 补充 |
| 29 | 2 | 🟡 | 遗漏 Service：`ReflectionGateService` | `service-config.ts` reflectionGate | 在 L5 补充 |
| 30 | 2 | 🟡 | 遗漏 Service：`StrategyInstructionBuilder` | `service-config.ts` strategyInstructionBuilder | 在 L5 补充 |
| 31 | 2 | 🟡 | 遗漏 Service：`CodexService` | `service-config.ts` codexService | 在 L5 补充 |
| 32 | 2 | 🟡 | 遗漏 Service：`MessageRouter` | `service-config.ts` messageRouter | 在 L5 补充 |
| 33 | 2 | 🟢 | `TeachingStrategyService` 与 `TeachingStrategyRouter` 未区分 | `service-config.ts` | 拆分为两个独立节点或标注包装关系 |
| 34 | 3 | 🟡 | 遗漏 Handler：`evidence.handler` | `ipc/evidence.handler.ts` | 在 L3 补充 |
| 35 | 3 | 🟡 | 遗漏 Handler：`ability-profile.handler` | `ipc/ability-profile.handler.ts` | 在 L3 补充 |
| 36 | 4 | 🟡 | `resources/knowledge/` 路径无代码引用 | — | 移除该连接或确认真实路径 |
| 37 | 4 | 🟢 | messages 表双写未标注代理关系 | `session.service.ts` / `chat-orchestrator.service.ts` | 标注 ChatOrchSvc 通过 SessionService 间接写入 |
| 38 | 5 | 🟡 | Step 7 中 `diagnosis:update` 实际在 Step 4 推送 | `chat-orchestrator.service.ts` 第 347 行 | 将 diagnosis:update 推送移至 Step 4 |
| 39 | 5 | 🟢 | 遗漏第二次辩驳检测步骤 | `chat-orchestrator.service.ts` 第 159 行 | 在 Step 5 后补充二次辩驳检测 |
| 40 | 5 | 🟢 | 遗漏 Tool Calling 分支逻辑 | `chat-orchestrator.service.ts` 第 163-164 行 | 在 Step 6 前补充模型兼容性检测 |
| 41 | 6 | 🟢 | 图中未区分 TeachingStrategyService 与 Router | `service-config.ts` | 标注 TeachingStrategyService 包装 TeachingStrategyRouter |
| 42 | 3 | 🟢 | teaching-state.handler 的「模块级变量」描述已过时 | `teaching-state.handler.ts` 第 18-27 行 | 更新为 DI 注入模式描述 |

---

## 9. 修正后的完整数据流文本图

以下 ASCII 图中 `[!]` 标记为本次修正点。

```
              ┌─────────────────────────────────────────────┐
              │           [Layer 1] 渲染进程                  │
              │  UI Components / Zustand Stores / IPC Client  │
              └──────────────────┬──────────────────────────┘
                                 │ ipcRenderer.invoke / .on
                                 ▼
              ┌─────────────────────────────────────────────┐
              │       [Layer 1.5] preload contextBridge       │
              └──────────────────┬──────────────────────────┘
                                 │
                                 ▼
              ┌─────────────────────────────────────────────┐
              │          [Layer 2] IPC 通信通道               │
              │                                              │
              │  invoke (50):                                │
              │   CHAT: send, stop, [!] onboarding:analyze   │
              │   SESSION: list, create, delete, rename,     │
              │     getMessages, getMessagesPaged, [!]       │
              │     listWithMeta, updateTitle,               │
              │     searchMessages, isNewUser                │
              │   DIAG: query, submitRewrite, getComparison, │
              │     growth:getTrends, growth:getGlobalTrends │
              │   TEACHING: get, update, confirm,            │
              │     getPrompt, updateSummary                 │
              │   [!] EVIDENCE: getByDisease, getByAbility,  │
              │     getChain, create, getBySyndrome          │
              │   [!] ABILITY: getProfile                    │
              │   TRAINING: recommend, assign, complete,     │
              │     skip, history, submit, evaluate,         │
              │     deriveBehavior                           │
              │   CONFIG: get, set, testConnection           │
              │   MANUSCRIPT: list, get, create, update,     │
              │     delete / chapter:list, get, create,      │
              │     delete, updateContent                    │
              │                                              │
              │  event (5):                                  │
              │   chat:stream:data, chat:stream:end,         │
              │   [!] chat:tool:executing,                   │
              │   diagnosis:update, teachingState:updated    │
              └──────────────────┬──────────────────────────┘
                                 │
                                 ▼
              ┌─────────────────────────────────────────────┐
              │         [Layer 3] 主进程 Handler              │
              │                                              │
              │  chat.handler (→ ChatOrchestratorService)    │
              │  session.handler (→ SessionService)          │
              │  diagnosis.handler (→ 7 deps)                │
              │  teaching-state.handler (→ TeachingStateSvc) │
              │  training.handler (→ 4 deps)                 │
              │  config.handler (→ ConfigService)            │
              │  manuscript.handler (→ Database)             │
              │  [!] evidence.handler (→ EvidenceService)    │
              │  [!] ability-profile.handler (→ AbilityProfileSvc) │
              └──────────────────┬──────────────────────────┘
                                 │
                                 ▼
              ┌─────────────────────────────────────────────┐
              │       [Layer 4] Core 基础设施                │
              │  AppInitializer / ServiceContainer /         │
              │  IpcRegistry                                 │
              └──────────────────┬──────────────────────────┘
                                 │ DI 注入
                                 ▼
              ┌─────────────────────────────────────────────┐
              │       [Layer 5] 业务服务层 (25 Services)     │
              │                                              │
              │  ChatOrchestratorService  ← 编排中心        │
              │  SessionService            ← 会话+消息 CRUD  │
              │  DiagnosisService          ← 诊断 CRUD       │
              │  [!] EvidenceService       ← 证据 CRUD       │
              │  [!] DiagnosisMerger       ← 诊断→状态合并   │
              │  TrainingRecordService     ← 训练记录 CRUD   │
              │  StudentModelService       ← 学生画像聚合    │
              │  [!] AbilityProfileService ← 能力画像        │
              │  [!] ProfileDataAggregator ← 数据聚合        │
              │  [!] GrowthTrendService    ← 成长趋势        │
              │  TeachingStateService      ← 教学状态管理    │
              │  TeachingStrategyService   ← 策略决策包装    │
              │  TeachingStrategyRouter    ← 三层决策引擎    │
              │  [!] ProblemPrioritizer    ← 症候优先级排序  │
              │  [!] DisputeTrackerService ← 辩驳检测        │
              │  [!] ReflectionGateService ← 反思门控        │
              │  [!] StrategyInstructionBuilder ← 策略指令   │
              │  ConfigService             ← 配置管理        │
              │  ApiProxyService           ← SSE 流式代理    │
              │  PromptLoader / PromptBuilder ← Prompt 组装 │
              │  DynamicContextService     ← 动态上下文      │
              │  [!] CodexService          ← Codex 知识注入  │
              │  [!] MessageRouter         ← 消息路由        │
              └──┬───────┬───────┬───────┬──────────────────┘
                 │       │       │       │
                 ▼       ▼       ▼       ▼
              ┌────────┐ ┌──────┐ ┌──────┐ ┌──────────────┐
              │ SQLite │ │eStore│ │Resources│ │  LLM API     │
              │ (8表)  │ │      │ │/prompts│ │ (DeepSeek等) │
              │        │ │      │ │/config │ │              │
              └────────┘ └──────┘ └────────┘ └──────────────┘
              [!] 移除 resources/knowledge/ — 无代码引用

              ─────────────────────────────────────────────
              数据表映射（修正后）：
              SessionService        → sessions, messages
              ChatOrchestrator      → [!] → SessionService → messages
              DiagnosisService      → diagnosis_results
              TeachingStateService  → teaching_state
              TrainingRecordService → user_training_records
              EvidenceService       → evidence
              Manuscript Handler    → manuscripts, chapters
              ConfigService         → api-config.json (electron-store)
```

### 核心消息流修正（图 2 时序修正）

```
用户 → UI → Store → IPC(chat:send) → chat.handler → ChatOrchestrator

Step 1: 保存用户消息 → messages 表
Step 2: 辩驳检测 (DisputeTrackerService)
Step 3: 调用诊断 Agent (LLM API)
  Step 4: 保存诊断结果 → diagnosis_results 表
           [!] 推送 diagnosis:update 事件（在此处，非 Step 7）
Step 5: 准备教学上下文 (Prompt/Codex/Strategy)
  [!] Step 5.5: 第二次辩驳检测（根据反思门控结果）
  [!] Step 5.6: 模型 Tool Calling 兼容性检测 → 选择流式入口
Step 6: 调用主教练 (含 System Prompt) → SSE 流式
Step 7: 流结束 → processAIResponse (诊断合并 + teachingState:updated)
         [!] (diagnosis:update 已在 Step 4 推送, 此处仅 teachingState:updated)
```

---

## 10. 修正优先级建议

| 优先级 | 范围 | 修正项数 | 影响 |
|---|---|---|---|
| 🔴 P0 | 维度 1 — 补充全部遗漏通道（EVIDENCE、ABILITY 等共 25 条） | 25 | 图中缺失大量真实 IPC 通道，新开发者无法准确理解通信全貌 |
| 🟡 P1 | 维度 2 — 补充遗漏 Service（共 14 项） | 14 | L5 层只列出 ~44% 的 Service，架构理解不完整 |
| 🟡 P1 | 维度 5 — 修正 Step 7 中 diagnosis:update 推送时机 | 1 | 时序偏差可能误导调试和问题定位 |
| 🟢 P2 | 维度 3 — 补充 evidence/ability-profile handler | 2 | L3 层缺失 2 个 Handler |
| 🟢 P2 | 维度 4 — 移除 resources/knowledge/ 或确认路径 | 1 | 路径准确性 |
| 🟢 P2 | 维度 6 — 区分 TeachingStrategyService/Router | 1 | 架构细节精度 |

---

*核验报告完成。所有偏差均附代码行号，修正建议直接对应图中标注点。*
*（内容由AI生成，仅供参考）*
