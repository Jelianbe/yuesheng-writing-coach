# 月笙写作教练 — 用户使用逻辑闭环 v1

> 基于项目源代码（2026-06-24）逆向输出的完整用户旅程文档。
> 用于在继续开发前确认所有应消费的接口、窗口、视图及用户操作路径已经完整覆盖。

---

## 1. 用户旅程总图

```
┌──────────────────────────────────────────────────────────────────────┐
│                          用户使用闭环                                    │
│                                                                      │
│  配置接入 ──→ 提交作品 ──→ 诊断分析 ──→ 学习技法 ──→ 训练练习 ──→ 复盘总结  │
│     ↑                                                    │           │
│     └────────────────── 持续迭代 ──────────────────────────┘           │
└──────────────────────────────────────────────────────────────────────┘
```

六个阶段构成一个完整的学习循环。用户可以在任何阶段中断、跳转、回顾。

---

## 2. 窗口与视图总览

### 2.1 窗口

| 窗口 | 数量 | 尺寸 | 说明 |
|:-----|:-----|:------|:------|
| 主窗口 | 1 | 1280×800（min 1024×640） | 唯一窗口，三栏布局 |

### 2.2 三栏布局（桌面端）

```
┌──────────────┬─────────────────────────────────┬──────────────────┐
│  LeftPanel   │         CenterPanel              │   RightPanel      │
│  (左栏)      │         (中栏/主视图)             │   (右栏/工具)      │
├──────────────┼─────────────────────────────────┼──────────────────┤
│ 宽: 220px    │         flex: 1                  │ 宽: 360px         │
│ 可折叠+拖拽  │         (全填充)                 │ 可折叠+拖拽        │
│ (160-400px)  │                                  │ (260-600px)       │
├──────────────┼─────────────────────────────────┼──────────────────┤
│ 会话/项目列表  │  4 种视图模式切换                │  7 种工具 workspace │
│ • 对话 Tab   │  chat / training / editor / retro │ • 技法目录(catalog) │
│ • 项目 Tab   │  默认: chat                      │ • 教学进度(progress)│
│              │                                  │ • 学习日志(growth)  │
│              │                                  │ • 作品(works)      │
│              │                                  │ • 教学笔记(teaching)│
│              │                                  │ • 设置(settings)   │
│              │                                  │ • 发展路径(stage)   │
└──────────────┴─────────────────────────────────┴──────────────────┘
```

### 2.3 移动端布局（≤ 768px）

```
┌────────────────────────────┐
│  顶部栏: [☰] 月笙写作教练 [+] │
├────────────────────────────┤
│                            │
│      单栏主内容区            │
│    (ChatView / 其他视图)     │
│                            │
│                            │
├────────────────────────────┤
│  Footer: [模板] [态度灯] [🔓]│
│          [输入框...] [发送]  │
├────────────────────────────┤
│  TabBar: [会话] [消息] [工具] │
└────────────────────────────┘

← 左栏: overlay 抽屉 (85vw, max 320px) 从左侧滑入
→ 右栏: overlay 抽屉 (85vw, max 320px) 从右侧滑入
```

---

## 3. 用户操作路径详解

### 3.1 配置接入（首次使用）

```
用户首次启动
    │
    ▼
[左栏: 空会话列表]
[中栏: 空状态页 — 3 个引导按钮]
[右栏: 设置未配置]
    │
    ├── 用户点击"开始聊聊"或任意引导
    │     │
    │     ▼
    │   Footer 输入框出现
    │     │
    │     ▼
    │   发送消息 → 后端检查无 API Key
    │     → chat:send 返回错误
    │     → ChatView 显示 ErrorBanner
    │     → 用户点击"配置"
    │
    ▼
[右栏: SettingsWorkspace]
    │  配置 API Key + Base URL + 模型
    │  点击测试连接 → config:testConnection
    │  保存 → config:set
    │
    ▼
使用配置完成，回到聊天
```

**消费的接口**：
| 接口/通道 | 方向 | 用途 |
|:----------|:-----|:------|
| `config:get` | Renderer → Main | 获取现有配置 |
| `config:set` | Renderer → Main | 保存 API Key |
| `config:testConnection` | Renderer → Main | 测试 API 连通性 |
| `useConfigStore` | Store | 前端缓存配置状态 |
| `session:create` | Renderer → Main | 自动创建新会话 |

---

### 3.2 提交作品 → 诊断分析（核心闭环）

```
[中栏: ChatView] 用户输入/粘贴作品
    │
    ▼
Footer: 点击发送 → chat:send
    │
    ▼
[后端: ChatOrchestrator.sendMessage()]
    ├── 保存用户消息 (session:saveMessage)
    ├── IntentRouter.route() → "diagnose"
    ├── DiagnosisOrchestrator.analyze()
    │     ├── 调用诊断 Agent (LLM)
    │     ├── 规则引擎兜底 (analyzeByRules)
    │     └── 返回 DiagnosisAnalysis
    │
    ▼
[后端: 诊断结果持久化]
    ├── DiagnosisService.save()
    ├── EvidenceService.save()
    ├── DiagnosisMerger.merge() → 合并到 TeachingState
    ├── (可选) TeachingDecisionService.record()
    │
    ▼
[后端: 流式回复]
    ├── event: diagnosis:updated → 推送前端
    ├── event: chat:stream:data → 逐 token 流式回复
    └── event: chat:stream:end → 流结束
    │
    ▼
[前端: ChatView]
    ├── MessageBubble (intent=diagnose, 蓝色底色)
    │     └── 折叠/展开 (diagnose 专属)
    ├── DiagnosisCard → 显示症候列表
    ├── EditPanel → 针对特定症候展示修改建议
    ├── TrainingBridgeCard → 推荐训练 (可选)
    │
    ▼
用户根据诊断回复决定下一步
    ├── 提问追问 → learn 意图 → 学习技法
    ├── 要求练习 → train 意图 → 进入训练
    ├── 再次提交修改 → diagnose 意图 → 重新诊断
    └── 跳转到右侧面板 → 查看技法目录/进度/笔记
```

**消费的接口**：

| invoke 接口 | 用途 |
|:------------|:------|
| `chat:send` | 发送消息（含诊断分析） |
| `chat:stop` | 中断流式响应 |
| `diagnosis:query` | 查询历史诊断 |

| event 接口 | 用途 |
|:-----------|:------|
| `chat:stream:data` | 逐 token 接收 AI 回复 |
| `chat:stream:end` | 流式结束信号 |
| `diagnosis:updated` | 诊断结果推送 |

| store | 用途 |
|:------|:------|
| `useChatStore` | 消息列表、加载状态、流状态 |
| `useDiagStore` | 当前诊断、历史诊断、症候映射 |
| `useTeachingStateStore` | 教学阶段状态 |

---

### 3.3 学习技法

```
用户提问"什么是描写"、"教教我对话怎么写"
    │
    ▼
IntentRouter → "learn"
    │
    ▼
[后端: handleLearn()]
    ├── TeachingContext.prepareLight()
    ├── PromptBuilder (含技法池)
    ├── executeStream() → 流式回复
    │
    ▼
[前端: MessageBubble (intent=learn, 绿色底色)]
    │
    │
用户可能：
    ├── 继续追问 → 深入某个技法
    ├── 打开右侧技法目录 → catalog workspace
    │     ├── 按分类浏览技法
    │     └── 点击技法 → 在 ChatView 中继续讨论
    └── 记录笔记 → 学习日志 (growth workspace)
```

**消费的接口**：

| 接口 | 用途 |
|:-----|:------|
| `chat:send` | 同上（核心统一入口） |
| `teachingNote:record` | 记录教学笔记 |
| `teachingNote:getTree` | 查看笔记树 |
| `useTeachingStateStore` | 教学阶段同步 |

---

### 3.4 训练练习

```
触发方式 A: 用户主动要求训练
    │  用户说"练一下这个"或"出个题"
    │  IntentRouter → "train"
    │
触发方式 B: 系统推荐训练
    │  诊断完成后 TrainingBridgeCard 展示
    │  用户点击"开始训练"
    │  training:recommend → 获取推荐列表
    │
    ▼
[中栏: centerMode → 'training']
    ├── TrainingWorkshop 渲染
    │     ├── RecommendationsSection (训练推荐)
    │     ├── ActiveTrainingView (五步训练流)
    │     │     ├── Step 1: 解说技法
    │     │     ├── Step 2: 例证展示
    │     │     ├── Step 3: 确认理解 (用户输入)
    │     │     ├── Step 4: 主动尝试 (用户改写/创作)
    │     │     └── Step 5: 修改反馈 (AI 评估 + 迭代)
    │     ├── ErrorCardsSection (历史诊断症候)
    │     ├── HistorySection (训练历史)
    │     └── ProgressSummary (进度总览)
    │
    ▼
训练完成
    ├── 回到 chat (centerMode → 'chat')
    ├── 训练结果反馈到 TeachingState
    │     └── 评分 >= 7 → 降级症候严重度
    └── completedTasks ≥ 3 → 自动进入 REVIEW 阶段
```

**消费的接口**：

| invoke 接口 | 用途 |
|:------------|:------|
| `training:recommend` | 基于活跃症候获取训练推荐 |
| `training:assign` | 分配具体训练挑战 |
| `training:complete` | 完成训练 |
| `training:evaluate` | 提交训练评估 |
| `training:history` | 获取训练历史 |
| `training:skip` | 跳过训练推荐 |
| `training:deriveBehavior` | 行为推导（F-03） |
| `training:catalog` | 获取技法分类目录 |
| `training:generateFlow` | 生成五步训练流 |

| store | 用途 |
|:------|:------|
| `useTrainingStore` | centerMode、训练推荐、活跃训练、评估结果 |
| `useTeachingStateStore` | 教学阶段同步、症候严重度 |

---

### 3.5 复盘总结

```
自动触发 (completedTasks ≥ 3)
    │
    ▼
TeachingState → REVIEW 阶段
    │
    ▼
[中栏: centerMode → 'retro']
    ├── RetroSummaryView 渲染
    │     ├── 训练总览 (时间、数量、分数)
    │     ├── 症候改善轨迹
    │     ├── 能力成长总结
    │     └── 下一步建议
    │
    ▼
用户确认 → 回到 chat 继续下一轮
```

**消费的接口**：

| invoke 接口 | 用途 |
|:------------|:------|
| `retro:generate` | 生成复盘总结 |
| `retro:save` | 保存复盘结果 |
| `growth:getTrends` | 获取成长趋势数据 |

| store | 用途 |
|:------|:------|
| `useTrainingStore` | retroSummary、训练历史 |
| `useProgressStore` | 进度数据（含 persist） |

---

### 3.6 持续使用 — 历史回顾与切换

```
桌面端操作路径:

[左栏: 会话列表]
    ├── 点击历史会话 → session:getMessages → 恢复对话
    ├── 搜索 → session:searchMessages
    ├── 过滤: all / chat / train
    ├── 重命名 → session:rename
    └── 删除 → session:delete

[右栏: 工具面板]
    ├── catalog workspace → 浏览技法目录
    ├── progress workspace → 查看教学进度
    ├── growth workspace → 查看/记录学习日志
    │     └── learningLog:list / learningLog:save
    ├── works workspace → 管理作品章节
    │     └── manuscript:list / chapter:list / chapter:updateContent
    ├── teaching-note workspace → 查看教学笔记
    ├── settings workspace → 修改配置/态度
    └── stage workspace → 查看发展路径/七阶段进度

[中栏: 主视图]
    ├── 继续对话 (默认)
    ├── 进入训练工坊 (需要时)
    ├── 打开编辑器 (workspace 联动)
    └── 查看复盘 (阶段结束时)
```

**消费的接口**：

| invoke 接口 | 用途 |
|:------------|:------|
| `session:list` | 获取会话列表 |
| `session:getMessages` | 获取会话消息 |
| `session:searchMessages` | 搜索消息 |
| `session:rename` / `session:delete` | 会话管理 |
| `manuscript:list` / `chapter:list` | 作品/章节管理 |
| `project:list` | 项目列表 |
| `teachingNote:getTree` | 教学笔记树 |
| `prescription:getStageProgress` | 发展阶段进度 |

---

## 4. 完整接口消费清单

### 4.1 IPC invoke 接口（Renderer → Main）

| 通道 | 消费者 (UI/Store) | 调用时机 |
|:-----|:------------------|:---------|
| `chat:send` | Footer → ChatView | 用户点击发送 |
| `chat:stop` | ChatView (停止按钮) | 用户中断流式回复 |
| `session:list` | LeftPanel → SessionList | 应用启动、会话变更 |
| `session:create` | ChatView (自动) | 首次发送 |
| `session:delete` | SessionList | 用户删除会话 |
| `session:rename` | SessionList | 用户重命名 |
| `session:getMessages` | ChatView | 会话切换 |
| `session:searchMessages` | SessionList 搜索 | 用户搜索 |
| `config:get` | SettingsWorkspace、ConfigStore | 应用启动 |
| `config:set` | SettingsWorkspace | 用户保存配置 |
| `config:testConnection` | SettingsWorkspace | 用户测试连接 |
| `diagnosis:query` | DiagnosisCard | 查看历史诊断 |
| `training:recommend` | TrainingBridgeCard、TrainingWorkshop | 训练推荐 |
| `training:assign` | TrainingWorkshop | 开始训练 |
| `training:complete` | FiveStepFlow | 完成训练 |
| `training:evaluate` | StepFeedback | 提交评估 |
| `training:history` | TrainingWorkshop → HistorySection | 查看历史 |
| `training:catalog` | CatalogWorkspace | 技法目录 |
| `training:generateFlow` | FiveStepFlow | 生成训练流 |
| `training:skip` | RecommendationsSection | 跳过推荐 |
| `training:deriveBehavior` | FiveStepFlow | 行为推导 |
| `teachingNote:record` | LearnLogWorkspace | 记录笔记 |
| `teachingNote:getTree` | TeachingNoteWorkspace | 查看笔记 |
| `retro:generate` | RetroSummaryView | 生成复盘 |
| `retro:save` | RetroSummaryView | 保存复盘 |
| `growth:getTrends` | GrowthCard、ProgressWorkspace | 查看成长 |
| `prescription:getStageProgress` | StageProgressWorkspace | 发展进度 |
| `manuscript:list` / `chapter:list` | WorksWorkspace | 作品管理 |
| `project:list` | LeftPanel → ProjectList | 项目管理 |

### 4.2 IPC event 接口（Main → Renderer）

| 事件通道 | 订阅者 | 用途 |
|:---------|:-------|:------|
| `chat:stream:data` | ChatView | AI 回复逐 token 流 |
| `chat:stream:end` | ChatView | 流结束 |
| `diagnosis:updated` | ChatView → DiagnosisCard | 诊断结果推送 |
| `teachingState:updated` | TeachingStateStore | 教学阶段变更 |
| `teachingState:mastery` | TeachingStateStore | 掌握度更新 |

### 4.3 Zustand Store 清单

| Store | 主要消费者 | 持久化 |
|:------|:-----------|:-------|
| `useConfigStore` | SettingsWorkspace、ChatView | 否 (通过 IPC) |
| `useChatStore` | ChatView、MessageList | 否 (通过 IPC) |
| `useSessionStore` | SessionList | 否 (通过 IPC) |
| `useTeachingStateStore` | CenterPanel、ProgressWorkspace | 否 |
| `useDiagStore` | ChatView、DiagnosisCard | 否 |
| `useTrainingStore` | TrainingWorkshop、FiveStepFlow | 否 |
| `useProgressStore` | ProgressWorkspace | localStorage |
| `usePanelSessionStore` | RightPanel | 否 |
| `useRightToolsStore` | RightPanel | 否 |
| `useDrawerStore` | RightPanel | 否 |
| `useUiStore` | 全局 | 否 |
| `useUiLayoutStore` | AppShell | 否 |
| `useParadigmStore` | 全局 | 否 |
| `useChapterStore` | Editor、WorksWorkspace | 否 |
| `useManuscriptStore` | WorksWorkspace | 否 |
| `useProjectStore` | LeftPanel → ProjectList | 否 |
| `useEditorStore` | Editor | localStorage |
| `useStudentContextStore` | ChatView | localStorage |
| `useHintStore` | 全局 | 否 |

---

## 5. 用户路径覆盖检查

### 5.1 已覆盖的路径

- [x] **配置接入**：SettingsWorkspace → ConfigStore → config:set
- [x] **提交作品**：Footer → chat:send → ChatOrchestrator → DiagnosisOrchestrator → DiagnosisCard
- [x] **学习技法**：chat:send (learn) → handleLearn → stream → MessageBubble (green) + CatalogWorkspace
- [x] **训练练习**：training:recommend/assign/complete/evaluate → TrainingWorkshop → FiveStepFlow
- [x] **复盘总结**：retro:generate/save → RetroSummaryView
- [x] **移动端适配**：AppShell 响应式 + TabBar + overlay drawer（Phase A v1-v3）
- [x] **意图气泡差异化**：MessageBubble 5 类底色/标签（Phase A v2）
- [x] **微交互**：入场动画 + 点击反馈 + 标签弹跳（Phase A v2）

### 5.2 已识别但未覆盖的路径

- [ ] **降级提示**：degraded prop 就绪但后端未传递置信度（D-DEBT-01）
- [ ] **TabBar 与 Footer 的键盘冲突**：软键盘弹出时 TabBar 行为未定义
- [ ] **Training → Editor 链路**：sendToEditor 接口就绪但无实际触发点
- [ ] **空状态引导**：3 个引导按钮已有，但第一次就诊前 vs 训练后的空状态未区分
- [ ] **学习日志 (growth) 的 IPC 通道**：learningLog:* 通道在 IPC 白名单中但 handler 未注册
- [ ] **移动端诊断卡片交互**：DiagnosisCard/EditPanel/TrainingBridgeCard 在移动端的折叠/展开未处理

---

## 6. 用户使用路径简化图（面向开发）

```
┌───────────────────────────────────────────────────────────────────────────┐
│                       用户 → [Footer 输入]"帮我看看这段"                      │
│                               │                                            │
│                               ▼                                            │
│                     IntentRouter → "diagnose"                              │
│                               │                                            │
│                    ┌──────────┴──────────┐                                  │
│                    ▼                      ▼                                 │
│           [后端] 诊断分析          [前端] MessageBubble(蓝)                  │
│                    │                      │                                 │
│                    ▼                      ▼                                 │
│            diagnosis:updated       DiagnosisCard 展示症候                    │
│                    │                      │                                 │
│                    ▼                      │                                 │
│              用户选择下一步               │                                  │
│                    │                      │                                 │
│        ┌───────────┼──────────────┐       │                                  │
│        ▼           ▼              ▼       │                                  │
│    "怎么改"    "练一下"    "重写提交"      │                                  │
│    learn       train      diagnose(再)    │                                  │
│    (绿气泡)    (橙气泡)     (蓝气泡)       │                                  │
│        │           │              │       │                                  │
│        ▼           ▼              ▼       ▼                                  │
│    学习技法   五步训练流     诊断结果更新     │                                  │
│    (右侧目录)  (中栏切换)   (症候跟踪)      │                                  │
│        │           │              │       │                                  │
│        └───────────┼──────────────┘       │                                  │
│                    ▼                      ▼                                  │
│            completedTasks ≥ 3                                              │
│                    │                                                       │
│                    ▼                                                       │
│              [复盘] RetroSummaryView                                       │
│                    │                                                       │
│                    ▼                                                       │
│              [持续迭代] 回到聊天，重复循环                                     │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 7. 关键结论

### 核心统一入口
- **`chat:send`** 是唯一的用户输入入口。所有意图（diagnose/learn/train/review/general_chat）都通过同一个通道进入，后端 IntentRouter 负责分流。
- **`centerMode`** 是唯一的视图切换机制。聊天、训练、编辑器、复盘四种模式通过 store 状态驱动，无路由库。

### 未覆盖的接口
| 接口 | 说明 | 影响 |
|:-----|:------|:------|
| `learningLog:*` | 学习日志 IPC 通道已定义但 handler 未注册 | 学习日志 workspace 数据不持久 |
| `teachingHistory:add` | 教学历史通道已定义但消费者未实现 | 教学历史数据未被前端使用 |
| `teachingDecision:*` | 教学决策记录只发生后端，前端无消费 | 用户不可见历史决策 |

### 架构风险
| 风险 | 说明 |
|:-----|:------|
| 单一入口压力 | 所有交互通过 chat:send，意图路由错误无法从 UI 层面纠正 |
| 移动端诊断卡片 | DiagnosisCard/EditPanel/TrainingBridgeCard 在 ≤768px 无响应式适配 |
| 键盘 + TabBar 冲突 | 移动端软键盘弹出时 TabBar 仍固定在底部，可能遮挡输入区域 |
| 降级提示未启用 | degraded prop 就绪但后端未传递置信度字段 |
