# 月笙写作教练 — 项目架构参考文档

> 本文档为项目架构的综合参考，涵盖目录结构、IPC 通道、Store、组件树、API Contract、事件、数据库及领域层交互关系。
> 适用于日常开发中的快速检索和架构理解。

**版本**: 1.0.0  
**最后更新**: 2026-06-25  
**技术栈**: Electron + React 18 + TypeScript (strict) + Zustand + SQLite (better-sqlite3) + Vite

---

## 目录

1. [项目目录结构](#1-项目目录结构)
2. [IPC 通道清单（按域分组，70+）](#2-ipc-通道清单按域分组70)
3. [API Contract 清单（20 个文件）](#3-api-contract-清单20-个文件)
4. [Store 清单（19 个）](#4-store-清单19-个)
5. [组件树](#5-组件树)
6. [IPC 事件清单](#6-ipc-事件清单)
7. [数据库表结构概述](#7-数据库表结构概述)
8. [领域层交互关系图](#8-领域层交互关系图)

---

## 1. 项目目录结构

```
yuesheng-writing-coach/
│
├── src/
│   ├── main/                          # Electron 主进程
│   │   ├── index.ts                   # 主进程入口
│   │   ├── api-proxy.ts               # API 代理模块
│   │   ├──
│   │   ├── core/                      # 核心服务层
│   │   │   ├── window-manager.ts      # 窗口管理（1280x800，单窗口）
│   │   │   ├── app-initializer.ts     # 应用初始化（DB/Migration/服务容器/IPC）
│   │   │   ├── service-config.ts      # DI 注册配置
│   │   │   ├── service-container.ts   # 轻量服务容器
│   │   │   └── ipc-registry.ts        # IPC handler 注册中心（15 组）
│   │   │
│   │   ├── domains/                   # 5 个业务域
│   │   │   ├── 01-diagnosis/          # 诊断域
│   │   │   │   ├── diagnosis.service.ts
│   │   │   │   ├── diagnosis-parser.ts
│   │   │   │   ├── diagnosis-processor.ts
│   │   │   │   ├── diagnosis-merger.ts
│   │   │   │   ├── diagnosis-merger-utils.ts
│   │   │   │   ├── distillation/      # 提炼模块（规则蒸馏加载器）
│   │   │   │   ├── evidence/          # 证据管理
│   │   │   │   └── orchestrator/      # 诊断编排器 + 规则引擎
│   │   │   │
│   │   │   ├── 02-prescription/       # 处方域
│   │   │   │   ├── student/           # 学生模型（画像/分类/聚合/持久化）
│   │   │   │   ├── ability-atlas/     # 能力图谱
│   │   │   │   ├── strategy/          # 教学策略路由（三层路由）
│   │   │   │   ├── development-path/  # 发展路径
│   │   │   │   ├── decision/          # 教学决策记录
│   │   │   │   ├── problem-prioritizer.service.ts
│   │   │   │   └── technique-pool.service.ts
│   │   │   │
│   │   │   ├── 03-teaching/           # 教学域
│   │   │   │   ├── chat/             # 聊天编排（意图路由/消息路由/流处理/上下文）
│   │   │   │   ├── prompt/           # Prompt 工程（构建器/加载器/技能分发/截断/记忆胶囊）
│   │   │   │   ├── state/            # 教学状态机（5 阶段/精通门控/流转/锁定）
│   │   │   │   ├── teaching-state.service.ts
│   │   │   │   ├── teaching-note.service.ts
│   │   │   │   ├── reflection-gate.service.ts
│   │   │   │   ├── transition-prompt-loader.ts
│   │   │   │   ├── dispute-tracker.service.ts
│   │   │   │   └── strategy-instruction-builder.ts
│   │   │   │
│   │   │   ├── 04-validation/         # 验证/训练域
│   │   │   │   └── training/
│   │   │   │       ├── training-flow.service.ts
│   │   │   │       ├── training-recommendation.service.ts
│   │   │   │       ├── training-evaluator.service.ts
│   │   │   │       ├── training-record.service.ts
│   │   │   │       ├── behavior-derivation.service.ts
│   │   │   │       └── task-id-mapping/（加载器 + 类型）
│   │   │   │
│   │   │   └── 05-retro/              # 复盘域
│   │   │       ├── retro.service.ts
│   │   │       └── index.ts
│   │   │
│   │   ├── ipc/                       # IPC handler 实现（15 个文件）
│   │   │   ├── config.handler.ts
│   │   │   ├── session.handler.ts
│   │   │   ├── chat.handler.ts
│   │   │   ├── diagnosis.handler.ts
│   │   │   ├── training.handler.ts
│   │   │   ├── evidence.handler.ts
│   │   │   ├── ability-profile.handler.ts
│   │   │   ├── development-path.handler.ts
│   │   │   ├── growth.handler.ts
│   │   │   ├── teaching-note.handler.ts
│   │   │   ├── teaching-state.handler.ts
│   │   │   ├── manuscript.handler.ts
│   │   │   ├── project.handler.ts
│   │   │   ├── retro.handler.ts
│   │   │   ├── window.handler.ts
│   │   │   └── utils/                 # (create-handler, validate-payload, diagnosis-dedup)
│   │   │
│   │   ├── db/                        # SQLite 迁移脚本（.sql 文件）
│   │   │   ├── 013_manuscripts.sql
│   │   │   ├── 018_db_p1a_time_format.sql
│   │   │   ├── 020_db_add_task_type.sql
│   │   │   ├── 021_teaching_progress.sql
│   │   │   ├── 022_projects.sql
│   │   │   ├── 023_data_migration.sql
│   │   │   ├── 024_teaching_decision_log.sql
│   │   │   ├── 025_evidence_offset.sql
│   │   │   └── __tests__/
│   │   │
│   │   ├── services/                  # 主进程服务
│   │   │   ├── feedback-engine.ts
│   │   │   ├── recommendation-engine.ts
│   │   │   ├── writing-analyzer.ts
│   │   │   └── output-validator.ts
│   │   │
│   │   └── shared/                    # 主进程共享模块
│   │       ├── llm/                   # LLM 网关（Gateway/缓存/熔断/限流/适配器）
│   │       └── services/              # (ConfigService, SessionService, LLMGatewayService, etc.)
│   │
│   ├── preload/
│   │   └── index.ts                   # preload 桥接（暴露 electronAPI）
│   │
│   ├── renderer/                      # 渲染进程（Electron React）
│   │   ├── App.tsx                    # 入口（挂载 AppShell + 事件订阅）
│   │   │
│   │   ├── components/
│   │   │   ├── AppShell/              # 三栏布局主体
│   │   │   ├── left/                  # 左栏组件
│   │   │   │   ├── LeftPanel/         # 左栏面板容器
│   │   │   │   ├── SessionList/       # 会话列表
│   │   │   │   └── ProjectList/       # 项目列表
│   │   │   ├── center/                # 中栏组件
│   │   │   │   ├── CenterPanel/       # 4 视图切换容器
│   │   │   │   ├── CenterHeader/      # 中栏标题栏
│   │   │   │   ├── Footer/            # 输入栏（态度灯+模板+锁定+输入+发送）
│   │   │   │   └── ChatMessages/      # 聊天消息列表
│   │   │   ├── right/                 # 右栏组件
│   │   │   │   ├── RightPanel/        # 右栏面板容器
│   │   │   │   ├── ToolTabs/          # L1 工具标签
│   │   │   │   ├── SubTabs/           # L2 子标签
│   │   │   │   ├── ToolGrid/          # 工具网格
│   │   │   │   └── workspaces/        # 7 个工作区
│   │   │   │       ├── CatalogWorkspace/
│   │   │   │       ├── ProgressWorkspace/
│   │   │   │       ├── LearningLogWorkspace/
│   │   │   │       ├── WorksWorkspace/
│   │   │   │       ├── TeachingNoteWorkspace/
│   │   │   │       ├── SettingsWorkspace/
│   │   │   │       └── StageProgressWorkspace/
│   │   │   ├── chat/                  # 聊天组件
│   │   │   │   ├── ChatView.tsx
│   │   │   │   ├── MessageBubble.tsx
│   │   │   │   ├── MessageList.tsx
│   │   │   │   ├── TypingIndicator.tsx
│   │   │   │   ├── OnboardingFlow.tsx
│   │   │   │   ├── WelcomeCard.tsx
│   │   │   │   ├── TrainingBridgeCard.tsx
│   │   │   │   └── ChatSearchBar.tsx
│   │   │   ├── diagnosis/             # 诊断卡片组件
│   │   │   │   ├── DiagnosisCard.tsx
│   │   │   │   ├── EditPanel.tsx
│   │   │   │   ├── EvaluationCard.tsx
│   │   │   │   ├── GrowthCard.tsx
│   │   │   │   ├── BeatCheckChart.tsx
│   │   │   │   ├── SelfCheckList.tsx
│   │   │   │   └── OriginalEvidenceSection.tsx
│   │   │   ├── training/              # 训练流组件
│   │   │   │   ├── TrainingWorkshop.tsx
│   │   │   │   ├── flow/             # 五步训练流
│   │   │   │   ├── ActiveTrainingView.tsx
│   │   │   │   ├── RecommendationsSection.tsx
│   │   │   │   ├── ErrorCardsSection.tsx
│   │   │   │   ├── BehaviorDerivationTool.tsx
│   │   │   │   ├── GoalTrackingPanel.tsx
│   │   │   │   ├── ProgressTimeline.tsx
│   │   │   │   ├── TeachingProgressBar.tsx
│   │   │   │   └── ...
│   │   │   ├── manuscript/            # 作品编辑
│   │   │   │   ├── ManuscriptPanel.tsx
│   │   │   │   ├── EmptyEditorState.tsx
│   │   │   │   ├── FormatConfirmDialog.tsx
│   │   │   │   ├── SettingsPopover.tsx
│   │   │   │   └── ToolbarBtn.tsx
│   │   │   ├── navigation/            # 导航（TabBar）
│   │   │   ├── growth/                # 成长趋势
│   │   │   ├── editor/                # 章节编辑器
│   │   │   ├── layout/                # 布局组件（ResizeHandle/Drawer/Sidebar）
│   │   │   ├── onboarding/            # 引导流程
│   │   │   ├── profile/               # 能力画像
│   │   │   ├── retro/                 # 复盘总结
│   │   │   ├── settings/              # 设置面板
│   │   │   ├── search/                # 搜索面板
│   │   │   ├── tools/                 # 工具面板
│   │   │   ├── validation/            # 验证结果
│   │   │   └── common/                # 通用组件（Card/Button/Badge/EmptyState）
│   │   │
│   │   ├── stores/                    # 19 个 Zustand Store
│   │   ├── bus/                       # panelBus（跨面板通信）
│   │   ├── registry/                  # workspace 注册表
│   │   ├── services/                  # 渲染进程服务
│   │   ├── utils/                     # 工具函数（ipc 封装等）
│   │   └── styles/                    # CSS Modules + 设计令牌
│   │
│   └── shared/                        # 进程间共享
│       ├── constants.ts               # IPC_CHANNELS + ALLOWED 白名单
│       ├── api-contracts/             # 20 个类型化 API 契约
│       ├── types/                     # 共享类型定义
│       ├── error-codes.ts             # 错误码体系
│       ├── diagnosis-translations.ts  # 诊断翻译
│       └── mappings.ts                # 映射常量
│
├── resources/
│   ├── config/                        # 外部配置文件
│   └── prompts/                       # Prompt 模板
│
├── dev-docs/                          # 开发文档
│   ├── architecture/                  # 架构文档（本文档位置）
│   ├── adapters/                      # 适配器规范
│   ├── workflows/                     # 工作流定义
│   ├── README.md                      # 真源索引
│   └── skill-mapping.md               # Skill 导航表
│
├── .trae/rules/                       # TRAE 规则（~26 条）
├── AGENTS.md                          # AI 协作规则入口
└── package.json
```

---

## 2. IPC 通道清单（按域分组，70+）

IPC 通道常量定义在 [src/shared/constants.ts](file:///d:/ai-teacher/yuesheng-writing-coach/src/shared/constants.ts)，以 `domain:action` 格式命名。

### 2.1 Config 域（4 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `config:get` | invoke | 获取配置项 | ConfigApi.get |
| `config:set` | invoke | 设置配置项 | ConfigApi.set |
| `config:testConnection` | invoke | 测试 LLM API 连接 | ConfigApi.testConnection |
| `config:getReadingEntry` | invoke | 获取阅读条目 | ConfigApi.getReadingEntry |

### 2.2 Chat 域（5 通道，含 3 事件）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `chat:send` | invoke | 发送聊天消息 | ChatApi.send |
| `chat:stop` | invoke | 中断流式响应 | ChatApi.stop |
| `chat:stream:data` | event | 流式数据推送 | ChatApi.streamData |
| `chat:stream:end` | event | 流式结束推送 | ChatApi.streamEnd |
| `chat:tool:executing` | event | 工具调用状态推送 | ChatApi.toolExecuting |

### 2.3 Session 域（11 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `session:list` | invoke | 列出所有会话 | SessionApi.list |
| `session:create` | invoke | 创建会话 | SessionApi.create |
| `session:delete` | invoke | 删除会话 | SessionApi.delete |
| `session:rename` | invoke | 重命名会话 | SessionApi.rename |
| `session:getMessages` | invoke | 获取会话消息 | SessionApi.getMessages |
| `session:getMessagesPaged` | invoke | 分页获取消息 | SessionApi.getMessagesPaged |
| `session:listWithMeta` | invoke | 列出会话含元信息 | SessionApi.listWithMeta |
| `session:updateTitle` | invoke | 更新标题 | SessionApi.updateTitle |
| `session:searchMessages` | invoke | 搜索消息 | SessionApi.searchMessages |
| `session:isNewUser` | invoke | 判断是否新用户 | SessionApi.isNewUser |
| `session:cleanupOlderThan` | invoke | 清理旧数据 | SessionApi.cleanupOlderThan |

### 2.4 Diagnosis 域（5 通道，含 1 事件）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `diagnosis:update` | invoke | 更新诊断 | DiagnosisApi.update |
| `diagnosis:updated` | event | 诊断更新推送 | DiagnosisApi.updated |
| `diagnosis:query` | invoke | 查询诊断 | DiagnosisApi.query |
| `diagnosis:submitRewrite` | invoke | 提交改写 | DiagnosisApi.submitRewrite |
| `diagnosis:getComparison` | invoke | 获取改写对比 | DiagnosisApi.getComparison |

### 2.5 TeachingState 域（7 通道，含 2 事件）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `teachingState:get` | invoke | 获取教学状态 | TeachingStateApi.get |
| `teachingState:update` | invoke | 更新教学状态 | TeachingStateApi.update |
| `teachingState:confirm` | invoke | 用户确认 | TeachingStateApi.confirm |
| `teachingState:getPrompt` | invoke | 获取阶段 Prompt | TeachingStateApi.getPrompt |
| `teachingState:updateSummary` | invoke | 更新诊断摘要 | TeachingStateApi.updateSummary |
| `teachingState:updated` | event | 状态更新推送 | TeachingStateApi.updated |
| `teachingState:mastery` | event | 精通门控达成 | TeachingStateApi.mastery |

### 2.6 Evidence 域（5 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `evidence:getByDisease` | invoke | 按症候查询证据 | EvidenceApi.getByDisease |
| `evidence:getByAbility` | invoke | 按能力查询证据 | EvidenceApi.getByAbility |
| `evidence:getChain` | invoke | 获取证据链 | EvidenceApi.getChain |
| `evidence:create` | invoke | 创建证据 | EvidenceApi.create |
| `evidence:getBySyndrome` | invoke | 按综合症查询证据 | EvidenceApi.getBySyndrome |

### 2.7 Training 域（12 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `training:recommend` | invoke | 推荐训练任务 | TrainingApi.recommend |
| `training:assign` | invoke | 分配训练任务 | TrainingApi.assign |
| `training:complete` | invoke | 完成任务 | TrainingApi.complete |
| `training:skip` | invoke | 跳过任务 | TrainingApi.skip |
| `training:history` | invoke | 训练历史 | TrainingApi.history |
| `training:submit` | invoke | 提交练习 | TrainingApi.submit |
| `training:evaluate` | invoke | 评估练习 | TrainingApi.evaluate |
| `training:decideReading` | invoke | 决策是否推荐阅读 | TrainingApi.decideReading |
| `training:deriveBehavior` | invoke | 推导行为模式 | TrainingApi.deriveBehavior |
| `training:catalog` | invoke | 技法目录 | TrainingApi.catalog |
| `training:generateFlow` | invoke | 生成训练流 | TrainingApi.generateFlow |

### 2.8 Manuscript 域（5 通道）+ Chapter 域（5 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `manuscript:list` | invoke | 列出作品 | ManuscriptApi.list |
| `manuscript:get` | invoke | 获取作品详情 | ManuscriptApi.get |
| `manuscript:create` | invoke | 创建作品 | ManuscriptApi.create |
| `manuscript:update` | invoke | 更新作品 | ManuscriptApi.update |
| `manuscript:delete` | invoke | 删除作品 | ManuscriptApi.delete |
| `chapter:list` | invoke | 列出章节 | ChapterApi.list |
| `chapter:get` | invoke | 获取章节 | ChapterApi.get |
| `chapter:create` | invoke | 创建章节 | ChapterApi.create |
| `chapter:delete` | invoke | 删除章节 | ChapterApi.delete |
| `chapter:updateContent` | invoke | 更新章节内容 | ChapterApi.updateContent |

### 2.9 Project 域（5 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `project:list` | invoke | 列出项目 | ProjectApi.list |
| `project:get` | invoke | 获取项目 | ProjectApi.get |
| `project:create` | invoke | 创建项目 | ProjectApi.create |
| `project:update` | invoke | 更新项目 | ProjectApi.update |
| `project:delete` | invoke | 删除项目 | ProjectApi.delete |

### 2.10 Prescription 域（3 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `prescription:getStageProgress` | invoke | 获取阶段进度 | PrescriptionApi.getStageProgress |
| `prescription:getAllStages` | invoke | 获取所有阶段 | PrescriptionApi.getAllStages |
| `prescription:getStageById` | invoke | 按 ID 获取阶段 | PrescriptionApi.getStageById |

### 2.11 Growth 域（2 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `growth:getTrends` | invoke | 获取成长趋势 | GrowthApi.getTrends |
| `growth:getGlobalTrends` | invoke | 获取全局趋势 | GrowthApi.getGlobalTrends |

### 2.12 TeachingNote 域（4 通道）

| 通道 | 方向 | 说明 | API Contract |
|------|------|------|-------------|
| `teachingNote:record` | invoke | 记录教学笔记 | TeachingNoteApi.record |
| `teachingNote:getTree` | invoke | 获取笔记树 | TeachingNoteApi.getTree |
| `teachingNote:delete` | invoke | 删除笔记 | TeachingNoteApi.delete |
| `teachingNote:update` | invoke | 更新笔记 | TeachingNoteApi.update |

### 2.13 其余域

| 通道 | 方向 | 说明 |
|------|------|------|
| `teachingHistory:add` | invoke | 添加教学历史（RWR-P1-9） |
| `ability:getProfile` | invoke | 获取能力画像 |
| `onboarding:analyze` | invoke | 新用户引导分析 |
| `retro:generate` | invoke | 生成复盘总结 |
| `retro:save` | invoke | 保存复盘总结 |
| `teachingDecision:record` | invoke | 记录教学决策（主进程内部） |
| `window:minimize` | on/send | 窗口最小化 |
| `window:maximize` | on/send | 窗口最大化/还原 |
| `window:close` | on/send | 关闭窗口 |

### 2.14 IPC 白名单

**允许 invoke 的通道**（约 62 个）：见 `constants.ts` 的 `ALLOWED_INVOKE_CHANNELS`。

**允许 on() 的事件通道**（6 个）：
- `diagnosis:updated`
- `teachingState:updated`
- `teachingState:mastery`
- `chat:stream:data`
- `chat:stream:end`
- `chat:tool:executing`

---

## 3. API Contract 清单（20 个文件）

所有 Contract 定义在 [src/shared/api-contracts/](file:///d:/ai-teacher/yuesheng-writing-coach/src/shared/api-contracts/) 目录下，基于 `base.ts` 的基础类型构建。

| # | 文件 | 导出 | 端点数 | 事件数 |
|---|------|------|--------|--------|
| 1 | `base.ts` | ApiSuccess, ApiError, ApiResponse, ApiEndpoint, ApiEvent | - | - |
| 2 | `chat.contract.ts` | ChatApi, ChatInvokeChannels, ChatEventChannels | 2 | 3 |
| 3 | `diagnosis.contract.ts` | DiagnosisApi, DiagnosisInvokeChannels, DiagnosisEventChannels | 4 | 1 |
| 4 | `teaching-state.contract.ts` | TeachingStateApi, TeachingStateInvokeChannels | 5 | 2 |
| 5 | `training.contract.ts` | TrainingApi, TrainingInvokeChannels | 11 | 0 |
| 6 | `session.contract.ts` | SessionApi, SessionInvokeChannels | 11 | 0 |
| 7 | `config.contract.ts` | ConfigApi, ConfigInvokeChannels | 4 | 0 |
| 8 | `evidence.contract.ts` | EvidenceApi, EvidenceInvokeChannels | 5 | 0 |
| 9 | `manuscript.contract.ts` | ManuscriptApi, ChapterApi, + InvokeChannels | 10 | 0 |
| 10 | `ability.contract.ts` | AbilityApi, AbilityInvokeChannels | 1 | 0 |
| 11 | `growth.contract.ts` | GrowthApi, GrowthInvokeChannels | 2 | 0 |
| 12 | `teaching-note.contract.ts` | TeachingNoteApi, TeachingNoteInvokeChannels | 4 | 0 |
| 13 | `teaching-history.contract.ts` | TeachingHistoryApi | 1 | 0 |
| 14 | `teaching-decision.contract.ts` | TeachingDecisionApi, + InvokeChannels | 1 | 0 |
| 15 | `onboarding.contract.ts` | OnboardingApi, OnboardingInvokeChannels | 1 | 0 |
| 16 | `project.contract.ts` | ProjectApi, ProjectInvokeChannels | 5 | 0 |
| 17 | `prescription.contract.ts` | PrescriptionApi, PrescriptionInvokeChannels | 3 | 0 |
| 18 | `retro.contract.ts` | RetroApi, RetroInvokeChannels | 2 | 0 |
| 19 | `event-map.ts` | EventChannelMap（类型映射） | - | 6 事件类型 |
| 20 | `index.ts` | 统一重导出 | - | - |

**Contract 设计模式**：每个 Contract 包含请求类型（`XXXRequest`）、响应类型（`XXXResponse`）以及 API 端点常量（`XXXApi`），支持通过 `channel` 常量配合 `invoke()` 进行类型安全的 IPC 调用，替代直接引用字符串通道名。

---

## 4. Store 清单（19 个）

所有 Store 基于 Zustand 实现，位于 [src/renderer/stores/](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/stores/)。

| # | Store 文件 | 导出名称 | 核心状态 | 持久化 | 说明 |
|---|-----------|---------|---------|--------|------|
| 1 | `config.store.ts` | useConfigStore | apiKey, baseUrl, modelName, temperature, attitudeLevel, attitudeLocked, maxTokens, isConfigured, testStatus | - | LLM 配置管理，通过 IPC 与主进程同步 |
| 2 | `chat.store.ts` | useChatStore | messages[], currentSessionId, isLoading, error, streamAborted, onboardingActive, onboardingStep, lastFailedMessage, retryable, currentStreamId | - | 聊天消息管理+流式响应+新用户引导 |
| 3 | `session.store.ts` | useSessionStore | sessions[], currentSessionId | - | 会话列表管理（CRUD+切换） |
| 4 | `teaching-state.store.ts` | useTeachingStateStore | currentState, masteredSyndromeIds[] | - | 教学状态接收和查询 |
| 5 | `diag.store.ts` | useDiagStore | currentDiagnosis, history{}, evidenceMap{} | - | 诊断结果管理 |
| 6 | `training.store.ts` | useTrainingStore | centerMode, errorCards[], recommendations[], activeTraining, history[], submissionResult, evaluationResult, bridgeRecommendation | - | 训练状态（中心模式切换+训练流程） |
| 7 | `ui.store.ts` | useUiStore | leftTab, selectedProjectId, attitude, attitudeLocked, trainingContexts{} | - | V6.2 Shell UI 状态（左栏 tab + 态度） |
| 8 | `ui-layout.store.ts` | useUiLayoutStore | sidebarCollapsed, sidebarWidth, rightPanelWidth | - | 面板布局尺寸管理 |
| 9 | `drawer.store.ts` | useDrawerStore | activePanel, collapsed | - | 右侧抽屉面板开关 |
| 10 | `right-tools.store.ts` | useRightToolsStore | openTools[], activeToolId, subTabs{} | - | 右侧工具标签管理 |
| 11 | `panel-session.store.ts` | usePanelSessionStore | sessions[], activeSessionId, sidebarPhase | - | 右侧面板会话管理 |
| 12 | `right-panel.store.ts` | useRightPanelStore | (右侧栏状态) | - | 右侧栏上层状态 |
| 13 | `chapter.store.ts` | useChapterStore | chapters[], currentChapter, openFiles[], contentCache{} | - | 章节管理与编辑器缓存 |
| 14 | `manuscript.store.ts` | useManuscriptStore | manuscripts[], currentManuscript | - | 作品管理 |
| 15 | `project.store.ts` | useProjectStore | projects[] | - | 项目管理 |
| 16 | `progress.store.ts` | useProgressStore | currentProgress, progressMap{} | **persist** | 教学进度持久化 |
| 17 | `editor.store.ts` | useEditorStore | fontSize, theme, settingsOpen | **persist** | 编辑器偏好设置 |
| 18 | `hint.store.ts` | useHintStore | points, unlockedLevels | - | 提示系统 |
| 19 | `paradigm.store.ts` | useParadigmStore | activeParadigm, activeTab | - | 范式切换 |
| - | `student-context.store.ts` | useStudentContextStore | userType, confidenceLevel, thinkingStyle | **localStorage** | 学生上下文（非 Zustand persist） |

### Store 协作原则

- **drawer.store** 仅管理面板开闭，**panel-session.store** 管理标签会话，**chapter.store** 管理章节编辑器
- 多 Store 操作必须通过 `right-panel.actions.ts` 统一入口（X-01 协议）
- 禁止外部代码直接协调三个 Store

---

## 5. 组件树

```
<App>                                              # App.tsx — 加载配置 + 订阅 IPC 事件
  └── <AppShell>                                   # 三栏布局 + 响应式 + 可拖拽调整宽度
        │
        ├── <LeftPanel>                            # 左栏（可折叠，minWidth=160）
        │     ├── 品牌标识 + 收起按钮
        │     ├── Tab: 对话 / 项目
        │     ├── <SessionList>                    # 会话列表（all/chat/train 过滤）
        │     └── <ProjectList>                    # 项目列表
        │
        ├── [ResizeHandle]                         # 左栏/右栏拖拽调整手柄（rAF 节流）
        │
        ├── <CenterPanel>                          # 中栏主区域（4 视图切换）
        │     ├── <CenterHeader>                   # 中栏标题（会话标题 + 操作按钮）
        │     │
        │     ├── [centerMode=chat]                # ── 聊天视图 ──
        │     │     ├── <ChatView>
        │     │     │     ├── <OnboardingFlow>     # 新用户引导流程
        │     │     │     ├── <WelcomeCard>        # 欢迎卡片
        │     │     │     ├── <MessageList>        # 消息列表
        │     │     │     │     └── <MessageBubble> # 消息气泡（用户/AI/诊断卡片等）
        │     │     │     ├── <TypingIndicator>    # AI 输入指示器
        │     │     │     ├── <DiagnosisCard>      # 诊断结果卡片
        │     │     │     ├── <EditPanel>          # 改写编辑面板
        │     │     │     ├── <EvaluationCard>     # 评估结果卡片
        │     │     │     ├── <TrainingBridgeCard> # 训练桥接卡片
        │     │     │     ├── <GrowthCard>         # 成长卡片
        │     │     │     └── <ErrorBanner>        # 错误提示条
        │     │     └── <Footer>                   # 输入栏
        │     │           ├── 态度灯（3 档：豆包/月笙/sensei）
        │     │           ├── 模板选择器
        │     │           ├── 态度锁定按钮
        │     │           ├── 文本输入框
        │     │           └── 发送按钮
        │     │
        │     ├── [centerMode=training]            # ── 训练工坊 ──
        │     │     └── <TrainingWorkshop>
        │     │           ├── <TrainingHeader>     # 训练标题
        │     │           ├── <ActiveTrainingView> # 当前训练视图
        │     │           ├── <RecommendationsSection> # 推荐列表
        │     │           ├── <ErrorCardsSection>  # 错误卡片
        │     │           ├── <FiveStepFlow>       # 五步训练流
        │     │           │     ├── StepExplain    # 讲解
        │     │           │     ├── StepExample    # 示例
        │     │           │     ├── StepPractice   # 练习
        │     │           │     ├── StepFeedback   # 反馈
        │     │           │     └── StepConfirm    # 确认
        │     │           ├── <TeachingProgressBar> # 教学进度条
        │     │           ├── <ProgressSummary>    # 进度摘要
        │     │           ├── <GoalTrackingPanel>  # 目标追踪
        │     │           ├── <BehaviorDerivationTool> # 行为推导
        │     │           └── <HistorySection>     # 历史记录
        │     │
        │     ├── [centerMode=editor]              # ── 作品编辑器 ──
        │     │     └── <ManuscriptPanel>
        │     │           ├── <ChapterEditor>      # 章节编辑器
        │     │           └── <EmptyEditorState>   # 空状态
        │     │
        │     └── [centerMode=retro]               # ── 复盘总结 ──
        │           └── <RetroSummaryView>
        │
        ├── <RightPanel>                           # 右栏（可折叠，minWidth=260）
        │     ├── <ToolTabs>                       # L1 工具标签栏
        │     ├── <SubTabs>                        # L2 子标签
        │     └── <ActiveWorkspace>                # 当前激活的工作区
        │           ├── [catalog] → <CatalogWorkspace>         # 技法目录
        │           ├── [progress] → <ProgressWorkspace>       # 学习进度
        │           ├── [learning-log] → <LearningLogWorkspace> # 学习日志
        │           ├── [works] → <WorksWorkspace>             # 作品集
        │           ├── [teaching-note] → <TeachingNoteWorkspace> # 教学笔记
        │           ├── [settings] → <SettingsWorkspace>       # 设置
        │           └── [stage-progress] → <StageProgressWorkspace> # 阶段进度
        │
        └── (移动端 768px↓)
              ├── 遮罩层（抽屉打开时）
              ├── 顶部导航栏（Menu + 月笙标题 + Plus）
              └── <TabBar>                         # 底部标签栏（会话/工具）
```

### 诊断卡片组件族

诊断卡片嵌入在 ChatView 的 MessageList 中，包括：

| 组件 | 功能 |
|------|------|
| `<DiagnosisCard>` | 诊断结果展示（症候列表 + 严重程度 + 证据） |
| `<EditPanel>` | 改写编辑面板（用户可修改原文） |
| `<EvaluationCard>` | AI 评估结果展示（评分 + 反馈） |
| `<GrowthCard>` | 成长对比展示（前后对比） |
| `<BeatCheckChart>` | 节拍检测图表 |
| `<SelfCheckList>` | 自查清单 |
| `<OriginalEvidenceSection>` | 原文证据溯源 |

### 训练流组件族

| 组件 | 功能 |
|------|------|
| `<FiveStepFlow>` | 五步训练流容器 |
| `<StepExplain>` | 讲解步骤 |
| `<StepExample>` | 示例步骤 |
| `<StepPractice>` | 练习步骤 |
| `<StepFeedback>` | 反馈步骤 |
| `<StepConfirm>` | 确认步骤 |
| `<FlowStepIndicator>` | 步骤指示器 |

---

## 6. IPC 事件清单

事件通道通过 `window.electronAPI.on(channel, callback)` 在渲染进程订阅。
所有事件通道定义在 `event-map.ts` 的 `EventChannelMap` 中。

### 6.1 事件通道总表

| 事件通道 | 事件负载类型 | 发送方 | 订阅方 | 触发时机 |
|---------|-------------|--------|--------|---------|
| `chat:stream:data` | ChatStreamDataEvent { sessionId, chunk } | 主进程 ChatOrchestrator | 渲染进程 App | AI 回复流式输出时 |
| `chat:stream:end` | ChatStreamEndEvent { sessionId, fullResponse, messageId, error?, aborted? } | 主进程 ChatOrchestrator | 渲染进程 App | 流式输出结束时 |
| `chat:tool:executing` | ChatToolExecutingEvent { sessionId, toolName, status } | 主进程 ChatOrchestrator | 渲染进程 App | AI 工具调用开始/结束/错误时 |
| `diagnosis:updated` | DiagnosisUpdateEvent { sessionId, entry } | 主进程 DiagnosisService | 渲染进程 | 诊断更新时 |
| `teachingState:updated` | TeachingStateUpdatedEvent { sessionId, state } | 主进程 TeachingStateService | 渲染进程 App | 教学状态变更时 |
| `teachingState:mastery` | TeachingStateMasteryEvent { syndromeId, sessionId } | 主进程 MasteryGate | 渲染进程 App | 症候精通门控达成时 |

### 6.2 事件订阅位置

事件订阅在 [App.tsx](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/App.tsx) 的 `useEffect` 中统一完成：

- `teachingState:updated` → `useTeachingStateStore.getState().setCurrentState()`
- `teachingState:mastery` → 追加 `masteredSyndromeIds`
- `chat:tool:executing` → 设置/清除工具执行状态指示器
- `chat:stream:data` → `useChatStore.getState().appendToLastAssistant()`
- `chat:stream:end` → `useChatStore.getState().finalizeLastMessage()`

### 6.3 事件通道映射类型

```typescript
interface EventChannelMap {
  'chat:stream:data': ChatStreamDataEvent;
  'chat:stream:end': ChatStreamEndEvent;
  'chat:tool:executing': ChatToolExecutingEvent;
  'diagnosis:updated': DiagnosisUpdateEvent;
  'teachingState:updated': TeachingStateUpdatedEvent;
  'teachingState:mastery': TeachingStateMasteryEvent;
}
```

---

## 7. 数据库表结构概述

数据库使用 SQLite (better-sqlite3) + Knex 迁移，时间格式统一为 INTEGER unixepoch。

### 7.1 表清单

| 表名 | 说明 | 主要字段 | 迁移版本 |
|------|------|---------|---------|
| `sessions` | 聊天会话 | id, title, preview, manuscript_id, chapter_id, project_id, created_at, updated_at | 018 |
| `messages` | 聊天消息 | id, session_id, role, content, created_at | (未在迁移中列出，假设早期已有) |
| `diagnosis_results` | 诊断结果 | id, session_id, message_id, syndromes(JSON), suggested_actions(JSON), confidence, timestamp, next_focus, created_at, root_cause_analysis, teaching_progress(JSON) | 015, 018, 021 |
| `evidence` | 证据记录 | evidence_id, type, level, novel_id, chapter_id, chapter_range, paragraph_index, sample_range, content_json, related_disease, related_ability, related_observations, extracted_by, created_at, start_offset, end_offset | 018, 025 |
| `teaching_state` | 教学状态 | id, session_id, current_phase, current_subphase, completed_actions(JSON), completed_tasks(JSON), active_problems(JSON), next_suggested_actions(JSON), current_task_id, diagnosis_summary, last_user_confirmation, focus_area, transition_offered, locked_syndromes(JSON), updated_at | 018 |
| `user_training_records` | 训练记录 | id, session_id, task_id, syndrome_id, status, assigned_at, completed_at, user_response, ai_feedback, effectiveness, score, task_type | 018, 020 |
| `manuscripts` | 作品 | id, title, description, genre, status, sort_order, created_at, updated_at, project_id | 013, 023 |
| `chapters` | 章节 | id, manuscript_id, title, content, word_count, sort_order, status, created_at, updated_at | 013 |
| `projects` | 项目 | id, name, description, setting_tree(JSON), setting_tree_type, created_at, updated_at | 022 |
| `student_model` | 学生画像 | id, session_id, attitude_preference, teaching_history(JSON), created_at, updated_at | 021 |
| `teaching_decision_log` | 教学决策日志 | decision_id, session_id, syndrome_id, strategy_chosen, reason, student_state_json, decided_at, outcome, outcome_at, notes, created_at | 024 |

### 7.2 索引概览

| 索引 | 表 | 列 | 用途 |
|------|-----|-----|------|
| `idx_teaching_state_session` | teaching_state | session_id | 按会话查询教学状态 |
| `idx_teaching_state_phase` | teaching_state | current_phase | 按阶段过滤 |
| `idx_teaching_state_focus_area` | teaching_state | focus_area | 按关注领域查询 |
| `idx_diagnosis_session` | diagnosis_results | session_id, timestamp | 会话诊断历史 |
| `idx_diagnosis_message` | diagnosis_results | message_id | 按消息查询诊断 |
| `idx_training_session` | user_training_records | session_id, assigned_at | 会话训练记录 |
| `idx_training_task` | user_training_records | task_id | 按任务查询 |
| `idx_training_status` | user_training_records | session_id, status | 按状态过滤 |
| `idx_evidence_disease` | evidence | related_disease | 按症候查询证据 |
| `idx_evidence_ability` | evidence | related_ability | 按能力查询 |
| `idx_evidence_novel` | evidence | novel_id | 按作品查询 |
| `idx_evidence_chapter_offset` | evidence | chapter_id, start_offset | 按章节+偏移量查询 |
| `idx_chapters_manuscript_id` | chapters | manuscript_id | 按作品查询章节 |
| `idx_chapters_sort_order` | chapters | manuscript_id, sort_order | 章节排序 |
| `idx_projects_updated_at` | projects | updated_at DESC | 项目列表排序 |
| `idx_sessions_project_id` | sessions | project_id | 按项目过滤会话 |
| `idx_manuscripts_project_id` | manuscripts | project_id | 按项目过滤作品 |
| `idx_student_model_session` | student_model | session_id | 按会话查画像 |
| `idx_teaching_decision_session` | teaching_decision_log | session_id, decided_at | 会话决策历史 |
| `idx_teaching_decision_syndrome` | teaching_decision_log | syndrome_id | 按症候统计策略 |

### 7.3 ER 关系简图

```
projects (1) ──── (*) sessions
projects (1) ──── (*) manuscripts
manuscripts (1) ── (*) chapters
sessions (1) ──── (*) messages
sessions (1) ──── (*) diagnosis_results
sessions (1) ──── (*) user_training_records
sessions (1) ──── (1) teaching_state
sessions (1) ──── (*) teaching_decision_log
sessions (1) ──── (1) student_model
```

---

## 8. 领域层交互关系图

### 8.1 五域架构总览

```
┌─────────────────────────────────────────────────────────────────────┐
│                       渲染进程 (Renderer)                           │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌──────────────────┐   │
│  │ 19 Store │  │ 组件树   │  │  panelBus │  │ IPC invoke/on    │   │
│  └────┬────┘  └────┬─────┘  └─────┬─────┘  └────────┬─────────┘   │
│       │             │              │                 │              │
└───────┼─────────────┼──────────────┼─────────────────┼──────────────┘
        │             │              │                 │
        ▼             ▼              ▼                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    preload 桥接 (contextBridge)                     │
│         electronAPI: { invoke, on, send, platform }                │
└─────────────────────────────────────────────────────────────────────┘
        │             │              │                 │
        ▼             ▼              ▼                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       主进程 (Main Process)                         │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    IPC Handler 层 (15 handlers)              │   │
│  │  config │ session │ chat │ diagnosis │ training │ evidence  │   │
│  │  teaching-state │ manuscript │ project │ retro │ ...        │   │
│  └─────────┬────────────────────────┬──────────────────────────┘   │
│            │                        │                               │
│            ▼                        ▼                               │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    服务容器 (ServiceContainer)                │   │
│  │         DI: configService / sessionService / ...             │   │
│  └─────────┬────────────────────────┬──────────────────────────┘   │
│            │                        │                               │
│            ▼                        ▼                               │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                   5 个业务域 (Domains)                       │   │
│  │                                                             │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │  01-diagnosis  诊断域                               │   │   │
│  │  │  ┌─────────────┐  ┌──────────────┐  ┌───────────┐  │   │   │
│  │  │  │ Diagnosis   │  │ Evidence     │  │ Distillation  │  │   │
│  │  │  │ Orchestrator│─▶│ Service      │  │ Loader    │  │   │   │
│  │  │  │ (编排器)     │  │ (证据服务)    │  │ (规则蒸馏) │  │   │   │
│  │  │  └──────┬──────┘  └──────┬───────┘  └───────────┘  │   │   │
│  │  │         │                │                          │   │   │
│  │  │  ┌──────▼────────────────▼──────────────────────┐  │   │   │
│  │  │  │  RuleBasedDiagnosisEngine (规则诊断引擎)      │  │   │   │
│  │  │  └─────────────────────────────────────────────┘  │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  │                                                             │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │  02-prescription  处方域                            │   │   │
│  │  │  ┌─────────────┐  ┌──────────┐  ┌───────────────┐  │   │   │
│  │  │  │ StudentModel│  │ Strategy │  │ AbilityAtlas  │  │   │   │
│  │  │  │ (学生模型)   │  │ (策略路由)│  │ (能力图谱)     │  │   │   │
│  │  │  └──────┬──────┘  └────┬─────┘  └───────┬───────┘  │   │   │
│  │  │         │              │                  │          │   │   │
│  │  │  ┌──────▼──────────────▼──────────────────▼──────┐  │   │   │
│  │  │  │  DevelopmentPath (发展路径,7 阶段)             │  │   │   │
│  │  │  │  TeachingDecision (决策日志,Phase 1 只写不读)   │  │   │   │
│  │  │  └─────────────────────────────────────────────┘  │   │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  │                                                             │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │  03-teaching  教学域 (核心)                          │   │   │
│  │  │                                                      │   │   │
│  │  │  ┌──────────┐    ┌──────────┐    ┌─────────────┐   │   │   │
│  │  │  │ Chat     │    │ Prompt   │    │ Teaching    │   │   │   │
│  │  │  │ Orchest- │───▶│ Builder  │───▶│ State       │   │   │   │
│  │  │  │ rator    │    │ (Prompt  │    │ Machine     │   │   │   │
│  │  │  │          │    │  工程)    │    │ (状态机)     │   │   │   │
│  │  │  └────┬─────┘    └──────────┘    └──────┬──────┘   │   │   │
│  │  │       │                                  │          │   │   │
│  │  │  ┌────▼─────┐                    ┌───────▼───────┐  │   │   │
│  │  │  │ Intent   │                    │ MasteryGate   │  │   │   │
│  │  │  │ Router   │                    │ (精通门控)    │  │   │   │
│  │  │  │ (5 类)   │                    └───────────────┘  │   │   │
│  │  │  └──────────┘                                       │   │   │
│  │  │                                                      │   │   │
│  │  │  ┌──────────┐  ┌───────────┐  ┌─────────────────┐  │   │   │
│  │  │  │ Teaching │  │ Reflection│  │ DisputeTracker  │  │   │   │
│  │  │  │ Note     │  │ Gate      │  │ (争议追踪)      │  │   │   │
│  │  │  │ (笔记)    │  │ (反思门控) │  │                 │  │   │   │
│  │  │  └──────────┘  └───────────┘  └─────────────────┘  │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  │                                                             │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │  04-validation  验证/训练域                          │   │   │
│  │  │  ┌──────────┐  ┌──────────┐  ┌─────────────────┐   │   │   │
│  │  │  │ Training │  │ Training │  │ Behavior        │   │   │   │
│  │  │  │ Recommen-│  │ Evaluator│  │ Derivation      │   │   │   │
│  │  │  │ dation   │  │ (评估器)  │  │ (行为推导)      │   │   │   │
│  │  │  └──────────┘  └──────────┘  └─────────────────┘   │   │   │
│  │  │  ┌──────────┐  ┌────────────────────────────────┐   │   │   │
│  │  │  │ Training │  │ TaskIDMapping (任务 ID 映射)   │   │   │   │
│  │  │  │ Flow     │  └────────────────────────────────┘   │   │   │   │
│  │  │  └──────────┘                                       │   │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  │                                                             │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │  05-retro  复盘域                                   │   │   │
│  │  │  ┌─────────────────┐                               │   │   │
│  │  │  │ RetroService    │                               │   │   │
│  │  │  │ (复盘分析+摘要)  │                               │   │   │
│  │  │  └─────────────────┘                               │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    共享基础设施                              │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │   │
│  │  │ SQLite   │  │ LLM      │  │ Config   │  │ Session  │   │   │
│  │  │ (better- │  │ Gateway  │  │ Service  │  │ Service  │   │   │
│  │  │ sqlite3) │  │ (网关)    │  │ (配置)    │  │ (会话)   │   │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │   │
│  │  ┌──────────┐  ┌──────────┐                               │   │
│  │  │ API Proxy│  │ Output   │                               │   │
│  │  │ (代理)    │  │ Validator│                               │   │
│  │  └──────────┘  └──────────┘                               │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 8.2 教学状态机流转图

```
[用户发送消息] → [意图路由] ─┬─ diagnose → [诊断域] → [更新教学状态]
                              ├─ learn    → [教学域: 讲解/示例] → [Prompt Builder] → [LLM 回复]
                              ├─ train    → [训练域: 分配任务] → [五步训练流]
                              ├─ review   → [复盘域: 生成总结]
                              └─ general  → [教学域: 普通聊天]

[教学状态机 5 阶段]
  P0_INIT ──→ P0_ENGAGE ──→ P1_WORLD ──→ P2_PRACTICE_LOOP ──→ P4_REVIEW
                                   │            ↕                    │
                                   │        (完成 ≥3 次)              │
                                   │                                  │
  P1_WORLD 子阶段: NATURAL_LAW → PROTAGONIST → SOCIAL_STRUCT → FIRST_SCENE → DAILY_DETAIL
  P2_PRACTICE_LOOP 子阶段: IDENTIFY → GUIDE → REFLECTION → TEACHING → ASSIGN → REVIEW
```

### 8.3 诊断-训练反馈回路

```
[用户输入] → [诊断编排器]
              ├── RuleBasedDiagnosisEngine (规则引擎快速诊断)
              ├── LLM 诊断 (协同)
              └── DiagnosisMerger (合并器)
                    │
                    ▼
              [evidence 证据管理] → 存入 evidence 表
                    │
                    ▼
              [处方域 Strategy Router]
                    │
                    ├── layer1: 条件过滤 (教学阶段/已训练症候)
                    ├── layer2: 优先级排序 (严重度/频次)
                    └── layer3: 智能策略 (学生模型匹配)
                          │
                          ▼
              [训练域 TrainingRecommendation]
                    │
                    ▼
              [五步训练流: 讲解→示例→练习→反馈→确认]
                    │
                    ▼
              [训练评估 → 结果回写]
                    │
                    ▼
              [精通门控 MasteryGate] ──→ 症候精通 → teachingState:mastery 事件
```

### 8.4 数据流向图

```
用户输入
  │
  ▼
ChatStore.sendMessage()
  │
  ▼
IPC: chat:send ────────────→ ChatHandler
                                │
                    ChatOrchestrator ──→ IntentRouter
                                            │
                              ┌─────────────┼─────────────┐
                              ▼             ▼             ▼
                        诊断域处理      教学域处理      训练域处理
                              │             │             │
                              ▼             ▼             ▼
                         Diagnosis     Prompt        Training
                         Service       Builder       Recommendation
                              │             │             │
                              ▼             ▼             ▼
                         IPC 推送       LLM Gateway    IPC 推送
                    diagnosis:updated   chat:stream:   training:catalog
                                        data/end       training:assign
                              │             │             │
                              └─────────────┼─────────────┘
                                            ▼
                                   渲染进程 Store 更新
                                            │
                                            ▼
                                   组件重渲染 (React)
```

---

## 附录

### A. 关键常量速查

| 常量 | 值 | 定义位置 |
|------|-----|---------|
| 窗口大小 | 1280 x 800 | window-manager.ts |
| 左栏最小宽度 | 160px | AppShell |
| 左栏最大宽度 | 400px | AppShell |
| 右栏最小宽度 | 260px | AppShell |
| 右栏最大宽度 | 600px | AppShell |
| 消息超时 | 120s | chat.store.ts |
| 滑动窗口预算 | 8000 tokens | chat.store.ts |
| 精通门控阈值 | >= 80% 症候解决 | teaching-state-machine.constants.ts |
| 意图路由置信度 | 0.6 | intent-router.ts |
| 最大诊断历史 | 3 条 | constants.ts |
| 改善判定阈值 | 1 分 | constants.ts |
| 教学档位 | doubao / yuesheng / sensei / direct | prompt 系统 |

### B. IPC Handler 注册映射

每个 handler 在 [ipc-registry.ts](file:///d:/ai-teacher/yuesheng-writing-coach/src/main/core/ipc-registry.ts) 中通过 `initXXXHandlers(services)` + `registerXXXHandlers()` 模式注册，依赖从 `ServiceContainer` 中按名称获取。

| Handler 文件 | 注册模式 | 依赖的服务 |
|-------------|---------|-----------|
| config.handler.ts | init + register | ConfigService |
| session.handler.ts | init + register | SessionService |
| evidence.handler.ts | init + register | EvidenceService |
| ability-profile.handler.ts | init + register | AbilityProfileService |
| training.handler.ts | init + register | ConfigService, TrainingRecordService, StudentModelService, etc. |
| development-path.handler.ts | init + register | StudentModelService |
| growth.handler.ts | init + register | GrowthTrendService |
| teaching-note.handler.ts | init + register | TeachingNoteService |
| diagnosis.handler.ts | init + register | multi-service |
| chat.handler.ts | init + register | ChatOrchestratorService |
| teaching-state.handler.ts | init + register | TeachingStateService |
| manuscript.handler.ts | init + register | DB 实例 |
| project.handler.ts | init + register | DB 实例 |
| retro.handler.ts | register 仅 | RetroService |
| window.handler.ts | init 仅 | - |

### C. 症候/动作常量

**症候 ID**（P 系列写作症候，H/E/I 系列诊断维度标记）：
`P001-WordviewBloat`, `P002-CharacterTool`, `P003-EmotionLabeling`, `P004-InfoDumping`, `P005-PerspectiveDrift`, `P006-PacingStagnation`, `P007-ReadingStructureSingle`, `P008-WorldviewExposition`, `P009-MotivationDeficit`, `P010-OCPlanarization`, `H001-HooklessOpening`, `H002-IdentityMissing`, `E001-EmotionalCurveIssue`, `I001~I006` 意图矛盾系列

**教学动作 ID**：
`A001-NarrowScope`, `A002-ReturnToProtagonist`, `A003-FiveQuestions`, `A004-GroundInReality`, `A005-StageSplit`, `A006-ContrastShow`, `A007-FlipPerspective`, `A008-ReadingAssignment`, `A009-ConfidenceConfirm`, `A010-BoundaryCalibration`, `A011-CrossContextTransfer`, `A012-IntentCalibration`

定义位置：[src/shared/constants.ts](file:///d:/ai-teacher/yuesheng-writing-coach/src/shared/constants.ts) `SyndromeId` / `ActionId`。
