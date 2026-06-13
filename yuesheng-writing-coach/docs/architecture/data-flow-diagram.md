# 月笙写作教练 — 数据流向概览 V3（修正版）

> 更新日期：2026-06-13 | 基于代码实际状态验证 | 替代 V2

---

## 图 1：七层架构数据流向总览

```
┌──────────────────────────────────────────────────────────────────────┐
│ [Layer 1] 渲染进程 (Renderer)                                        │
│ ┌──────────────────────┐ ┌──────────────────────┐ ┌───────────────┐  │
│ │ UI 组件层             │ │ Zustand 状态管理      │ │ IPC 服务封装   │  │
│ │ ChatView/MessageInput │ │ chat.store            │ │ chat.service  │  │
│ │ TrainingWorkshop      │ │ training.store        │ │ trn.service   │  │
│ │ DiagnosisCard         │ │ diag.store            │ │ diag.service  │  │
│ │ ManuscriptPanel       │ │ manuscript.store      │ │ ms.service    │  │
│ │ ConfigPage/AppSidebar │ │ config.store          │ │ cfg.service   │  │
│ │ EvidencePanel         │ │ evidence.store        │ │ evd.service   │  │
│ │ AbilityDashboard      │ │ ability.store         │ │ abl.service   │  │
│ └──────────────────────┘ └──────────────────────┘ └───────────────┘  │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ ipcRenderer.invoke / .on
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [Layer 1.5] preload 安全桥接 (contextBridge)                         │
│  白名单 API: invoke(41 channels) + on(5 channels)                     │
└───────────────────────────────┬──────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [Layer 2] IPC 通信通道 (ALLOWED_INVOKE 41 + ALLOWED_EVENT 5)         │
│                                                                      │
│  ┌─ 聊天 ──────────────────────────────────────────────────┐         │
│  │ chat:send  chat:stop  chat:stream:data*  chat:stream:end*│         │
│  │ chat:tool:executing*  onboarding:analyze                 │         │
│  └─────────────────────────────────────────────────────────┘         │
│  ┌─ 会话 ──────────────────────────────────────────────────┐         │
│  │ session:list  create  delete  rename  getMessages        │         │
│  │ getMessagesPaged  listWithMeta  updateTitle              │         │
│  │ searchMessages  isNewUser                                │         │
│  └─────────────────────────────────────────────────────────┘         │
│  ┌─ 诊断 ────────────────────────┐  ┌─ 成长趋势 ───────────┐        │
│  │ diagnosis:query  submitRewrite│  │ growth:getTrends       │       │
│  │ diagnosis:getComparison       │  │ growth:getGlobalTrends │       │
│  │ diagnosis:update*             │  └────────────────────────┘       │
│  └───────────────────────────────┘                                   │
│  ┌─ 教学状态 ──────────────────────────────────────────────┐         │
│  │ teachingState:get  update  confirm  getPrompt            │         │
│  │ updateSummary  teachingState:updated*                    │         │
│  └─────────────────────────────────────────────────────────┘         │
│  ┌─ 训练 ──────────────────────────────────────────────────┐         │
│  │ training:recommend  assign  complete  skip  history      │         │
│  │ training:submit  evaluate  deriveBehavior               │         │
│  └─────────────────────────────────────────────────────────┘         │
│  ┌─ 证据 ─────────────────────────────────────────────────┐         │
│  │ evidence:getByDisease  getByAbility  getChain           │         │
│  │ evidence:create  getBySyndrome                          │         │
│  └─────────────────────────────────────────────────────────┘         │
│  ┌─ 能力画像 ───────────┐  ┌─ 作品管理 ─────────────────────┐        │
│  │ ability:getProfile    │  │ manuscript:list get create    │        │
│  └───────────────────────┘  │   update delete               │        │
│                              │ chapter:list get create      │        │
│  ┌─ 配置 ───────────────┐   │   delete updateContent       │        │
│  │ config:get  set       │   └──────────────────────────────┘        │
│  │ config:testConnection │                                            │
│  └───────────────────────┘                                            │
│  * = 事件通道（ALLOWED_EVENT_CHANNELS，非 invoke）                    │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ ipcMain.handle / webContents.send
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [Layer 3] 主进程 Handler (9 个)                                       │
│                                                                      │
│  chat.handler.ts ───────── 薄委托层，全部转发给 ChatOrchestrator     │
│  diagnosis.handler.ts ──── 诊断 CRUD + processDiagnosisFromAI()      │
│  teaching-state.handler.ts  教学状态读写 + 阶段推进 + 前端推送       │
│  training.handler.ts ───── 训练推荐/分配/完成/跳过/评估/行为推导     │
│  evidence.handler.ts       证据查询/创建（仅依赖 EvidenceService）    │
│  ability-profile.handler.ts 能力画像查询                              │
│  session.handler.ts ────── 会话+消息 CRUD（仅依赖 SessionService）   │
│  config.handler.ts ─────── 配置读写+连接测试（仅依赖 ConfigService） │
│  manuscript.handler.ts ─── 作品+章节 CRUD（直接 SQLite）             │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ 服务调用 / DI 注入
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [Layer 4] Core 基础设施                                               │
│  app-initializer    — 启动编排：DB 初始化 → 迁移 → DI → 窗口 → IPC  │
│  service-container  — DI 容器（单例/延迟初始化/循环检测）            │
│  ipc-registry       — Handler 注册编排，从容器取服务注入             │
│  service-config     — 22 个服务注册工厂                              │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ 服务依赖图
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [Layer 5] 业务服务层 (22 个已注册 Service)                            │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ ChatOrchestratorService    编排中心：消息→诊断→教学全流程    │     │
│  │ ApiProxyService            SSE 流式调用（DI 单例）           │     │
│  │ ConfigService              electron-store 配置 CRUD         │     │
│  │ SessionService             会话+消息 SQLite CRUD            │     │
│  │ DiagnosisService           诊断结果 SQLite CRUD             │     │
│  │ EvidenceService            证据 SQLite CRUD                 │     │
│  │ AbilityProfileService      跨会话能力画像聚合              │     │
│  │ GrowthTrendService         跨会话症候趋势+成长摘要          │     │
│  │ TeachingStateService       TeachingState 门面（封装Store）  │     │
│  │ TeachingStateStore         teaching_state 表 CRUD（底层）   │     │
│  │ TeachingStateMachine       教学阶段流转+子阶段推进（底层）  │     │
│  │ TeachingStrategyService    教学模式决策（委托Router）       │     │
│  │ TeachingStrategyRouter     三层决策引擎                     │     │
│  │ StudentModelService        跨会话学生画像                   │     │
│  │ TrainingRecordService      训练记录 SQLite CRUD             │     │
│  │ ProblemPrioritizer         症候三级分类+优先级排序          │     │
│  │ DisputeTrackerService      辩驳检测+态度自动升级            │     │
│  │ ReflectionGateService      反思门控（L2+强制反思）          │     │
│  │ DiagnosisParser            AI回复中诊断标记块JSON解析       │     │
│  │ DiagnosisMerger            诊断→TeachingState合并           │     │
│  │ MemoryCapsuleService       记忆胶囊（诊断摘要+进度封装）    │     │
│  │ PromptLoader               System Prompt 组装主服务         │     │
│  │ PromptBuilder              模板组装+占位符替换              │     │
│  │ DynamicContextService      三段式上下文装载                 │     │
│  │ CodexService               结构化知识注入                   │     │
│  │ StrategyInstructionBuilder 策略指令块构建                   │     │
│  │ MessageRouter              V3兼容层（始终返回true）         │     │
│  │ TrainingRecommender        症候→挑战模板匹配                │     │
│  │ TrainingEvaluator          LLM 训练评分                     │     │
│  │ BehaviorDerivation         角色行为推导（LLM）              │     │
│  │ EvidenceGrouping           证据按层级/类型分组              │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  🔶 骨架服务（仅类型定义）                                             │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ StudentClassifier.ts        学员类型识别                     │     │
│  │ FeedbackEngine.ts           实时写作反馈                     │     │
│  │ WritingAnalyzer.ts          写作分析器                      │     │
│  │ RecommendationEngine.ts     综合推荐引擎                     │     │
│  └─────────────────────────────────────────────────────────────┘     │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ CRUD / HTTP
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [Layer 6] 数据存储层                                                  │
│                                                                      │
│  SQLite (better-sqlite3):                                            │
│  sessions / messages / diagnosis_results / teaching_state            │
│  user_training_records / evidence / manuscripts / chapters           │
│                                                                      │
│  electron-store: api-config.json                                     │
│  运行时资源: resources/prompts/  resources/knowledge/  resources/config/│
└───────────────────────────────┬──────────────────────────────────────┘
                                │ HTTP (fetch)
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [Layer 7] 外部系统                                                    │
│  LLM API (DeepSeek 等 OpenAI 兼容端点)                               │
│  ApiProxy.chatStream() / chatStreamWithTools() / evaluateRewrite()   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 图 2：核心消息流 — 用户输入到 AI 回复

```
用户
 │
 ├─[1] 输入消息 + 点击发送
 ▼
UI 组件 (MessageInput)
 │
 ├─[2] chat.store.send()
 ▼
IPC 服务封装 (chat.service)
 │
 ├─[3] ipcRenderer.invoke('chat:send', {message, sessionId, ...})
 ▼
preload 桥接 (contextBridge)
 │
 ├─[4] 白名单校验通过
 ▼
chat.handler.ts (薄委托层)
 │
 ├─[5] validatePayload → orchestrator.sendMessage(payload)
 ▼
ChatOrchestratorService.sendMessage()
 │
 ├─[5a] resolveChapterReference(message)           — 解析 /chapters/{id} 引用
 ├─[5b] SessionService.saveMessage(user message)    — 保存用户消息到 messages 表
 ├─[5c] DisputeTrackerService.checkMessage()        — 辩驳检测
 ├─[5d] DisputeTrackerService.getEffectiveAttitude()— 计算有效态度
 ├─[5e] callDiagnosisAgent(message)                — 🔴 异步 LLM 诊断
 │      ├─ ApiProxy.chatStream(诊断 Prompt)
 │      ├─ injectTechniquePool()                    — 技法库注入到 Prompt
 │      └─ 返回 DiagnosisAnalysis (JSON)
 ├─[5f] DiagnosisService.save(diagnosis)            — 持久化诊断（仅元数据）
 ├─[5g] DiagnosisService.saveAnalysis(analysis, diagId) — 保存完整分析
 ├─[5h] IPC event diagnosis:update → Renderer       — 即时推送
 ├─[5i] prepareTeachingContext()                    — 组装教学上下文
 │      ├─ MemoryCapsuleService.buildCapsule()       — 诊断历史记忆胶囊
 │      ├─ StudentModelService.toPromptText()        — 学生画像文本
 │      ├─ PromptLoader.loadSystemPrompt()           — System Prompt
 │      ├─ ReflectionGateService.shouldTriggerReflection() — 反思判定
 │      ├─ StrategyInstructionBuilder.build()        — 策略指令块
 │      └─ CodexService (知识注入)
 ├─[5j] buildMessageArray()                        — 组装 [system, history..., user]
 ├─[5k] probeToolSupport(modelName)                — 模型 Tool Calling 能力探测
 │
 ├─[6] 流式调用 LLM
 │    ├─ 不支持 tools: ApiProxy.chatStream(messages)
 │    └─ 支持 tools:   ApiProxy.chatStreamWithTools(messages, TOOLS)
 │         └─ 最多 MAX_TOOL_ROUNDS=3 轮 tool call 循环
 │              └─ readChapter 工具 → DB.chapters 查询
 │
 ├─[7] 逐 chunk 推送
 │    └─ IPC event chat:stream:data → Renderer 逐字渲染
 │
 ├─[8] 流结束 → 后处理
 │    ├─ SessionService.saveMessage(assistant response) — 保存 AI 回复
 │    ├─ SessionService.autoGenerateTitle()              — 自动标题
 │    └─ processDiagnosisFromAI(fullResponse, sessionId, messageId)
 │         │
 │         ├─[8a] DiagnosisParser.parseDiagnosisFromAIResponse()
 │         │       └─ 解析 ---DIAGNOSIS_START/END--- 标记块
 │         ├─[8b] DiagnosisService.save(diagnosis)
 │         │       └─ 持久化诊断结果（含所有症候）
 │         ├─[8c] EvidenceService
 │         │       └─ for each syndrome.evidence:
 │         │           EvidenceService.save(record)
 │         │           EvidenceService.linkToDiagnosis(diagId, evId, role)
 │         ├─[8d] DiagnosisMerger.merge(diagnosis)
 │         │       └─ mergeSyndromesIntoState → TeachingStateStore.update()
 │         │       └─ enterReflectionIfTriggered (反思门控)
 │         ├─[8e] IPC event teachingState:updated → Renderer
 │         └─[8f] IPC event diagnosis:update → Renderer (去重判定)
 │
 └─[9] IPC event chat:stream:end → Renderer
```

---

## 图 3：教学策略决策流

```
                    ┌─────────────────────┐
                    │ StudentModelService │  跨会话学生画像
                    │ (能力/风格/成熟度)  │
                    └──────────┬──────────┘
                               │
  ┌────────────────────────────┼────────────────────────────┐
  │                            │                            │
  ▼                            ▼                            ▼
┌─────────────────┐  ┌─────────────────────┐  ┌──────────────────────┐
│ ConfigService    │  │ TeachingStateService│  │ 外部配置 JSON (6个)   │
│ (API Key/attitude)│  │ → TeachingStateStore│  │ education-theory-     │
│                  │  │ → TeachingState     │  │   fragments.json      │
│                  │  │   Machine (阶段)    │  │ learning-path.json    │
│                  │  │ (当前阶段/子阶段/   │  │ technique-selection-  │
│                  │  │  锁定症候)          │  │   matrix.json         │
└────────┬────────┘  └──────────┬──────────┘  │ coaching-templates.json│
         │                      │              │ user-type-map.json     │
         │                      │              │ syndrome-type-map.json │
         │                      │              └───────────┬────────────┘
         │                      │                          │
         ▼                      ▼                          ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ TeachingStrategyRouter (三层决策引擎)                        │
  │                                                             │
  │  Layer 1: selectFocusSyndrome()                             │
  │    ├─ 无活跃症候 → 默认路径                                 │
  │    ├─ 单症候 → 直接聚焦                                     │
  │    └─ 多症候 → 优先级选择（高优症候/最低分/严重度）         │
  │    → FocusDecision                                          │
  │                                                             │
  │  Layer 2: selectTeachingMode()                              │
  │    ├─ 症候→类型映射（expressive/structural/motivation）     │
  │    ├─ 类型→推荐入口→策略（case/reflection/analysis）        │
  │    ├─ userTypeMap → mode（scaffolding/guiding/challenging） │
  │    └─ 态度覆盖（direct→challenging, doubao→降级）           │
  │    → ModeDecision                                           │
  │                                                             │
  │  Layer 3: refineParameters()                                │
  │    ├─ learning-path.json → phaseId + corePatterns           │
  │    ├─ syndromeOverrideMap → 症候专属模式                    │
  │    └─ coaching-templates.json → 匹配模板                    │
  │    → ParameterDecision                                      │
  └─────────────────────────────────────────────────────────────┘
                               │
                               ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ StrategyInstructionBuilder.build(diagnosisAnalysis, attitude)│
  │   依赖: StudentModelService, TeachingStrategyService,        │
  │         ProblemPrioritizer                                  │
  │   → 策略指令文本块                                          │
  └──────────────────────────┬──────────────────────────────────┘
                             │
                             ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ PromptLoader.loadSystemPrompt()                             │
  │   → PromptBuilder → DynamicContextService → CodexService    │
  │   → 完整 System Prompt                                      │
  └──────────────────────────┬──────────────────────────────────┘
                             │
                             ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ ChatOrchestratorService                                     │
  │   → ApiProxy.chatStream(messages) → LLM API                │
  └─────────────────────────────────────────────────────────────┘
```

---

## 图 4：数据持久化映射

```
┌──────────────────────────────────────────────────────────────────┐
│ 服务层                                                           │
│                                                                  │
│  SessionService ──────────────► messages 表 (读写)               │
│                                  sessions 表 (读写)              │
│                                                                  │
│  DiagnosisService ────────────► diagnosis_results 表 (读写)      │
│                                                                  │
│  EvidenceService ─────────────► evidence 表 (读写)               │
│                                 evidence_diagnosis_link 表       │
│                                                                  │
│  TeachingStateStore ──────────► teaching_state 表 (读写)         │
│  (底层, 被 TeachingStateService 封装)                            │
│                                                                  │
│  TrainingRecordService ───────► user_training_records 表 (读写)  │
│                                                                  │
│  Manuscript Handler ──────────► manuscripts 表 + chapters 表     │
│  (直接 SQLite, 不走独立 Service)                                 │
│                                                                  │
│  AbilityProfileService ───────► 聚合查询: diagnosis_results      │
│                                    + user_training_records        │
│                                  (不写表, 纯计算)                │
│                                                                  │
│  GrowthTrendService ──────────► 委托: StudentModelService        │
│                                   → diagnosis_results 聚合查询   │
│                                  (不写表, 纯计算)                │
│                                                                  │
│  StudentModelService ─────────► 聚合查询: diagnosis_results      │
│                                  + user_training_records          │
│                                  (不写独立表, 纯计算)            │
│                                                                  │
│  ChatOrchestratorService ─────► 不直接写 messages 表!            │
│                                  通过 SessionService.saveMessage │
│                                                                  │
│  ConfigService ───────────────► api-config.json (electron-store) │
│                                                                  │
│  PromptLoader ─────────────────► resources/prompts/ (文件读取)   │
│  TeachingStrategyRouter ──────► resources/config/ (JSON 读取)   │
│  CodexService ─────────────────► resources/knowledge/ (读取)     │
└──────────────────────────────────────────────────────────────────┘
```

---

## 完整数据流验证表

### IPC 通道 → Handler → Service → 数据表 可追溯矩阵

| IPC 通道 | Handler 文件 | 注入的 Service | 读/写 | 数据表/存储 |
|---|---|---|---|---|
| `chat:send` | chat.handler → ChatOrchestrator | SessionService, DiagnosisService, PromptLoader, MessageRouter, StudentModelService, TeachingStrategyService, ProblemPrioritizer, DisputeTracker, ReflectionGate, StrategyInstructionBuilder, ApiProxy | W/R | messages, diagnosis_results, teaching_state |
| `chat:stop` | chat.handler → ChatOrchestrator | (AbortController) | — | — |
| `chat:stream:data`* | ChatOrchestrator → mainWindow | — | 事件 | — |
| `chat:stream:end`* | ChatOrchestrator → mainWindow | — | 事件 | — |
| `chat:tool:executing`* | ChatOrchestrator → mainWindow | — | 事件 | — |
| `onboarding:analyze` | chat.handler → ChatOrchestrator | ApiProxy, ConfigService | — | — |
| `session:list` | session.handler | SessionService | R | sessions, messages |
| `session:create` | session.handler | SessionService | W | sessions |
| `session:delete` | session.handler | SessionService | W | sessions, messages |
| `session:rename` | session.handler | SessionService | W | sessions |
| `session:getMessages` | session.handler | SessionService | R | messages |
| `session:getMessagesPaged` | session.handler | SessionService | R | messages |
| `session:listWithMeta` | session.handler | SessionService | R | sessions, messages |
| `session:updateTitle` | session.handler | SessionService | W | sessions |
| `session:searchMessages` | session.handler | SessionService | R | messages |
| `session:isNewUser` | session.handler | SessionService | R | sessions |
| `diagnosis:query` | diagnosis.handler | TeachingStateService | R | teaching_state |
| `diagnosis:submitRewrite` | diagnosis.handler | SessionService, ConfigService, ApiProxy | W/R | messages |
| `diagnosis:getComparison` | diagnosis.handler | DiagnosisService | R | diagnosis_results |
| `diagnosis:update`* | diagnosis.handler → mainWindow | — | 事件 | — |
| `growth:getTrends` | diagnosis.handler | GrowthTrendService → StudentModelService | R | diagnosis_results |
| `growth:getGlobalTrends` | diagnosis.handler | GrowthTrendService → StudentModelService | R | diagnosis_results (全局) |
| `teachingState:get` | teaching-state.handler | TeachingStateStore | R | teaching_state |
| `teachingState:update` | teaching-state.handler | TeachingStateStore | W | teaching_state |
| `teachingState:confirm` | teaching-state.handler | TeachingStateStore, TeachingStateMachine | W/R | teaching_state |
| `teachingState:getPrompt` | teaching-state.handler | TeachingStateStore, PromptBuilder | R | teaching_state |
| `teachingState:updateSummary` | teaching-state.handler | TeachingStateStore, PromptBuilder | W/R | teaching_state |
| `teachingState:updated`* | teaching-state.handler → mainWindow | — | 事件 | — |
| `ability:getProfile` | ability-profile.handler | AbilityProfileService | R | diagnosis_results + training_records (聚合) |
| `evidence:getByDisease` | evidence.handler | EvidenceService | R | evidence |
| `evidence:getByAbility` | evidence.handler | EvidenceService | R | evidence |
| `evidence:getChain` | evidence.handler | EvidenceService | R | evidence + evidence_diagnosis_link |
| `evidence:create` | evidence.handler | EvidenceService | W | evidence |
| `evidence:getBySyndrome` | evidence.handler | EvidenceService | R | evidence |
| `training:recommend` | training.handler | StudentModelService, generateRecommendations | R | diagnosis_results |
| `training:assign` | training.handler | TrainingRecordService, getChallengeTemplate | W | user_training_records |
| `training:complete` | training.handler | TrainingRecordService | W | user_training_records |
| `training:skip` | training.handler | TrainingRecordService | W | user_training_records |
| `training:history` | training.handler | TrainingRecordService | R | user_training_records |
| `training:submit` | training.handler | evaluateTraining, ConfigService | — | LLM API |
| `training:evaluate` | training.handler | evaluateTraining, TrainingRecordService, TeachingStateService, downgradeSyndromeSeverity | W | user_training_records, teaching_state |
| `training:deriveBehavior` | training.handler | deriveBehavior, ConfigService | — | LLM API |
| `config:get` | config.handler | ConfigService | R | api-config.json |
| `config:set` | config.handler | ConfigService | W | api-config.json |
| `config:testConnection` | config.handler | ConfigService | — | LLM API |
| `manuscript:list` | manuscript.handler | DB (直接) | R | manuscripts |
| `manuscript:get` | manuscript.handler | DB (直接) | R | manuscripts |
| `manuscript:create` | manuscript.handler | DB (直接) | W | manuscripts |
| `manuscript:update` | manuscript.handler | DB (直接) | W | manuscripts |
| `manuscript:delete` | manuscript.handler | DB (直接) | W | manuscripts |
| `chapter:list` | manuscript.handler | DB (直接) | R | chapters |
| `chapter:get` | manuscript.handler | DB (直接) | R | chapters |
| `chapter:create` | manuscript.handler | DB (直接) | W | chapters |
| `chapter:delete` | manuscript.handler | DB (直接) | W | chapters |
| `chapter:updateContent` | manuscript.handler | DB (直接) | W | chapters |

> `*` = 事件通道（webContents.send，非 ipcMain.handle）
> 总计: 28 个 invoke 通道 + 5 个 event 通道 = 33 个有效 IPC 通道
