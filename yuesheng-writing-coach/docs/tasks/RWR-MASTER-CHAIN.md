# RWR 王牌任务链（Master Chain）

> **权威依据**：[系统重构规格文档](../dev-docs/designs/2026-06-17-system-rewrite-spec.md)
> **所有设计决策以此为准，禁止偏离。如有疑问，先查规格文档，再查 TASK-CHAIN.md，最后问用户。**
>
> **当前基点**：`ac60ded`（FB-032 终态，RWR-P1-12 ✅）
> **创建日期**：2026-06-17

---

## 一、已完成（a5ec9d9 包含）

| 任务 | 内容 | 涉及文件 |
|:-----|:-----|:---------|
| P0-1 | DB 数据模型扩展 | `021_teaching_progress.sql`（diagnosis.teachingProgress + student_model） |
| P0-2 | progress.store | `stores/progress.store.ts` |
| P0-3 | Store 导出路径统一 | `stores/index.ts`（barrel export）+ 删除旧 rightPanelService |
| P0-4 | 项目 IPC + 项目表 migration | `022_projects.sql` + `ipc/project.ipc.ts` |
| P0-5 | 数据迁移脚本 | `023_data_migration.sql` |
| P0-6 | useRightPanel hook + SettingsPanel | `hooks/useRightPanel.ts` + 设置面板 |
| P1-1 | AppShell 三栏独立布局 | `components/layout/AppShell.tsx` + `.module.css` |
| P1-2 | SoloSidebar 三标签 + 训练按钮联动右栏 | `SoloSidebar.tsx`（[对话][项目] + [训练] 全宽按钮） |
| P1-3 | ProjectSelector + InputToolbar + AttitudeIndicator | `components/layout/ProjectSelector.tsx`、`components/chat/InputToolbar.tsx`、`components/chat/AttitudeIndicator.tsx` |
| P1-4 | 输入区 1/6 屏高重构 | `ChatView.tsx`、`MessageInput.tsx`（maxHeight=180px） |
| P1-5 | TeachingProgressBar + ProgressTimeline | `training/TeachingProgressBar.tsx` + `ProgressTimeline.tsx` + 4 store 扩展 |
| P1-6 | 教学决策记录层 + 诊断联动 progress | `024_teaching_decision_log.sql` + `decision.service.ts` + `diagnosis-processor.ts` + `app-controller.ts` |
| P1-7 | studentModel 持久化层（teachingHistory + attitudePreference） | `student-model-service.ts`（+4 方法）+ `types-teaching.ts`（+3 类型） |
| P1-8 | 右侧栏"进步摘要"卡片（精通确认高亮） | `training/ProgressSummary.tsx` + `ProgressSummary.module.css` + `App.tsx` 接入 |
| P1-9 | 训练反馈回路 + 精通门控 | `teaching-history.contract.ts`（新）+ `training.handler.ts`（+1 handler + emit `teachingState:mastery`）+ `training.actions.ts`（line 266+ 反馈链）+ `constants.ts`（+2 通道） |
| P1-10 | 教学状态机消费 mastery 事件 | `teaching-state.contract.ts`（+MasteryEvent + api.mastery）+ `types-ipc.ts`（+channel）+ `teaching-state.service.ts`（+onMastery）+ `teaching-state.store.ts`（+masteredSyndromeIds）+ `app-controller.ts`（+step 6） |
| P1-11 | 精通信息注入 Prompt | `App.tsx`（handleSendMessage 追加 masterySuffix，空列表不追加） |
| P1-12 | AI 收到 mastery 后的回应对齐 | `yuesheng-prompt-v3.md`（+精通技法处理规则段）+ RWR-MASTER-CHAIN.md（+RWR-DEBT-1 段）|

---

## 二、待执行（按依赖顺序排列）

### Phase A：导航与输入（P1 布局收尾）

#### A-1 [P1-2] SoloSidebar 三标签 [对话][项目][训练]

| 属性 | 值 |
|:-----|:-----|
| 前置 | P1-1 ✅ |
| 目标 | 现有 SoloSidebar（当前 ModeSwitch 只有 [对话][项目]）→ 三标签 [对话][项目][训练] |
| 涉及文件 | `SoloSidebar.tsx`（改）、`SoloSidebar.module.css`（改） |
| DoD | □ [对话][项目][训练] 三个 tab 可见可切换<br>□ [训练] 点击后中间栏进入训练视图<br>□ 原有拖拽/折叠/宽度记忆不破坏 |
| 依据 | 规格 §6.1 左侧栏设计 |

#### A-2 [P1-4] 输入区 1/6 屏高重构

| 属性 | 值 |
|:-----|:-----|
| 前置 | A-1 |
| 目标 | ChatView 输入区从当前固定高度 → 屏幕高度 1/6（max 180px） |
| 涉及文件 | `ChatView.tsx`（改）、`ChatView.module.css`（改）、`MessageInput.tsx`（改） |
| DoD | □ 输入区高度 = `min(max(1/6 屏高, 60px), 180px)`<br>□ 输入区顶部放 InputToolbar<br>□ AttitudeIndicator 显示在输入区左下角<br>□ 输入区自适应文字增多而增加（不超过 max） |
| 依据 | 规格 §5（输入区域设计） |

---

### Phase B：教学进度（核心反馈层）

#### B-1 [P1-5] TeachingProgressBar + ProgressTimeline ✅ (c6f0e64)

| 属性 | 值 |
|:-----|:-----|
| 前置 | A-1（左侧栏）、P0-2 ✅（progress.store） |
| 目标 | 右侧栏教学进度面板 0/N，按阶段分组（认知→工具→技能），点击展开详情 |
| 涉及文件 | `TeachingProgressBar.tsx`（新）、`ProgressTimeline.tsx`（新）+ drawer-constants / drawer.store / panel-session.store / right-panel.store 扩展 |
| DoD | ✅ 进度条显示 resolvedIssues / totalIssues<br>✅ 分母只增不减，按 status 分组<br>✅ 点击展开 ProgressTimeline（概览，不暴露诊断细节）<br>✅ 当前指针标记（第一个非 mastered issue） |
| 依据 | 规格 §4.2（教学进度追踪） |

**当前指针 → B-2 [P1-6]**

#### B-2 [P1-6] 诊断表与进度联动 + 教学决策记录 ✅ (56208ff)

| 属性 | 值 |
|:-----|:-----|
| 前置 | B-1、P0-1 ✅ |
| 目标 | 诊断完成后自动更新 progress.store；TeachingDecisionLog 写入 DB（先写不读） |
| 涉及文件 | `024_teaching_decision_log.sql`（新）+ `decision.service.ts`（新）+ `diagnosis-processor.ts`（改）+ `service-config.ts`（改）+ `app-controller.ts`（改）+ `types-teaching.ts`（扩）+ `teaching-decision.contract.ts`（新） |
| DoD | ✅ 诊断产生后自动更新 progressMap（app-controller onDiagnosisUpdate 调 appendIssues）<br>✅ TeachingDecisionLog 数据结构落地（024 migration + 6 个测试通过）<br>✅ 不暴露症候细节给用户（decision log 系统内部，contract 无读通道） |
| 简化决策 | strategyChosen 暂固定 'GUIDE'，studentState 暂默认值；spec §8.3 Phase 1 = 写不读，C 阶段再提级策略路由 |
| 依据 | 规格 §8（教学决策记录层）、§4.2 进度条"不暴露症候" |

**当前指针 → C-1 [P1-7]**

---

### Phase C：反馈增强

#### C-1 [P1-7] 画像增强（teachingHistory + attitudePreference 持久化）✅ (0a6937e)

| 属性 | 值 |
|:-----|:-----|
| 前置 | P0-1 ✅（student_model 表已存在） |
| 目标 | studentModel 持久化层：teachingHistory[] 追加写入 + attitudePreference 跨 session 复用 |
| 涉及文件 | `student-model-service.ts`（+4 方法：ensureSessionRow / appendTeachingHistory / setAttitudePreference / getAttitudePreference）+ `types-teaching.ts`（+3 类型）+ 1 个新测试文件 |
| DoD | ✅ appendTeachingHistory 自动创建行 + 200 条 FIFO 截断<br>✅ setAttitudePreference 写当前 session<br>✅ getAttitudePreference 跨 session 取最近一条非空<br>✅ C-1 不接触发点（C-3 训练反馈回路再敲钉子）<br>✅ 不重构现有方法（R-010 最小化） |
| 决策 | teachingHistory 上限 200 条 / attitudePreference 跨 session = 最近一条非空 / 不写报告 |
| 依据 | 规格 §4.4（画像增强） |
| 债务 | service 突破 500 行，RWR-P3-2 全局清理时拆 RowManager |

**当前指针 → C-2 [P1-8]**

#### C-2 [P1-8] 右侧栏"进步摘要"卡片 ✅ (b051f56)

| 属性 | 值 |
|:-----|:-----|
| 前置 | B-2 ✅ + C-1 ✅ + P0-6 ✅ + P1-5 ✅ |
| 目标 | 右侧栏新增"进步摘要"工具,在精通确认时刻展示教学进展（短暂高亮） |
| 涉及文件 | `training/ProgressSummary.tsx`（新 89 行）+ `ProgressSummary.module.css`（新 47 行）+ `App.tsx`（panelContent 接入 + 删 unused import） |
| DoD | ✅ 包装 TeachingProgressBar（不重复 0/N 显示）<br>✅ 监听 progress.store resolvedIssues 增长触发高亮（200ms 激活 + 3s 窗口）<br>✅ session 切换清空高亮（spec §4.9 跨 session 行为）<br>✅ 不主动打开右侧栏（spec §4.8）<br>✅ 不暴露症候 name/description（R-021）<br>✅ 不造 IPC（消费 progress.store）<br>✅ 不接 BeatCheckChart / 不实现弱项对比（spec 范围不要求） |
| 决策 | 数据驱动（resolvedIssues 变化）/ 不接 BeatCheckChart / 不写报告 |
| 依据 | 规格 §4.8（不主动打开）+ §4.9（精通确认时刻）+ §十五.4.2（1 文件 UI） |

**当前指针 → D-1 [P2-1] LearningLogPanel（Phase C 整体完成）**

#### C-3 [训练反馈回路]（原 P2-2 提级）

| 属性 | 值 |
|:-----|:-----|
| 前置 | A-1（[训练] tab）、P0-2 ✅（progress.store） |
| 目标 | 训练完成后自动更新进度（resolvedIssues++ / totalIssues 不变） |
| 涉及文件 | `training.service.ts`（改）、`progress.store.ts`（改） |
| DoD | □ 完成训练 session → 进度更新<br>□ 不重新计算 totalIssues |
| 依据 | 规格 §4.6（训练三层体系中的 L3） |

---

### Phase D：增强与打磨

#### D-1 [P2-1] LearningLogPanel

| 属性 | 值 |
|:-----|:-----|
| 前置 | B-2（进度数据存在）、P0-6 ✅（useRightPanel） |
| 目标 | 右侧栏"学习日志"工具，展示用户完成的教学项、掌握度变化 |
| 涉及文件 | `LearningLogPanel.tsx`（新） |
| DoD | □ 按时间倒序排列<br>□ 每个条目显示技法名 + 完成状态 + 时间<br>□ 点击跳转到对应会话 |
| 依据 | 规格 §4.6（右侧栏进阶） |

#### D-2 [P2-3] IPC 错误处理 + 骨架屏

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（可随时做） |
| 目标 | IPC invoke 统一 try/catch 包裹，失败时静默展示；左侧栏 + 右侧栏骨架屏 |
| 涉及文件 | `utils/ipc.ts`（改）、各组件 |
| DoD | □ IPC 调用失败不弹窗<br>□ 错误在内容区展示<br>□ 左侧栏列表 + 右侧栏工具有 skeleton |
| 依据 | 规格 §13.5 |

#### D-3 [P2-4] 空状态全覆盖 + placeholder 轮换

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（可随时做） |
| 目标 | 所有面板的空状态 + 输入框 placeholder 随机轮换 |
| 涉及文件 | `WelcomeCard`、`SessionList`、`WorkTreePanel` 等 |
| DoD | □ 无会话 → 空状态<br>□ 无项目 → 空状态<br>□ 输入框 placeholder 随机轮换 |
| 依据 | 规格 §7（空状态设计） |

---

### Phase F：前端二次重写（一栏一状态打磨）

> **背景**：C 阶段完成后验收前端，发现当前 `components/` 目录 59 个文件与 spec 偏差累积。组件位置、布局细节、状态切换多处与 spec 不一致。
> **策略**：旧前端不删，移到 `src/renderer/components/_archived/` 作参考。严格按 spec §2.1 布局 + §13.2 目录规范（每组件一目录）逐栏重建。
> **驱动**：调用前端 skill（`design-taste-frontend` + `impeccable` + `frontend-design`）对 spec 做专业评审，输出《二次重写设计评审报告》作为 P5-A~E 的执行依据。
> **节奏**：一栏一状态，每任务独立可验收，可中断可恢复。

#### F-0 [P5-0] 隔离旧前端 + spec 设计评审

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（独立任务） |
| 目标 | (1) 把 `src/renderer/components/` 全部移到 `src/renderer/components/_archived/`（不删留参考）<br>(2) 调 `design-taste-frontend` + `impeccable` 对 spec §2~§6 做专业评审<br>(3) 输出 `docs/designs/2026-06-18-frontend-rewrite-design-review.md`：每栏每状态的可视化 + 组件清单 + 状态机 + 动画规范 |
| 涉及文件 | `components/_archived/`（移动） + `docs/designs/2026-06-18-frontend-rewrite-design-review.md`（新建） |
| DoD | □ 旧 components 移到 `_archived/`<br>□ 评审报告含 §2.1 布局图的每像素解读<br>□ 报告含左/中/右三栏每个状态的可视化示意<br>□ 报告含动画缓动规范<br>□ 报告含 F-1~F-5 任务依据 |
| 依据 | spec §2~§6（布局+输入+左侧栏） + §13.2（目录规范） |

#### F-1 [P5-A] 左侧栏一栏三态打磨

| 属性 | 值 |
|:-----|:-----|
| 前置 | F-0 |
| 目标 | 严格按 spec §6.1 重建左侧栏：header（[☰]+[⚙]） + 三行布局（[训练]单行 / [对话][项目]双 tab / 搜索栏） + 列表区 |
| 子状态 | 1) 展开态（min=180px）<br>2) 收起态（width=0，中间栏自动扩展）<br>3) [对话] 标签下显示会话列表<br>4) [项目] 标签下显示项目树<br>5) [训练] 点击后**只**触发右侧栏展开（不切换 sidebarView）<br>6) 搜索 + 筛选 ([全部][对话][训练]) |
| 涉及目录 | `components/layout/Sidebar/`（新）+ `Sidebar/index.tsx` + `Sidebar.module.css` + 4 个子组件 `SidebarHeader/ SidebarTabs/ SidebarSearch/ SidebarList/` |
| DoD | □ header 左 [☰] / 右 [⚙]<br>□ [训练] 单独在上方行（占满宽）<br>□ [对话][项目] 并列下方行<br>□ 分隔线视觉区分按键区与列表区（无独立 UI）<br>□ 收起态 width=0 + 200ms ease 动画（spec §2.5）<br>□ [训练] 点击后仅调 `useRightPanelStore.openTool('training')`（不再 `setSidebarView('training')`）<br>□ 拖拽调整宽度边界 180~480<br>□ 不破坏 F-2 中间栏的 column 布局 |
| 依据 | spec §6.1（结构） + §2.5（动画） + §2.3（状态表） + §6.2（按键布局） |

#### F-2 [P5-B] 中间栏 header 与三态切换

| 属性 | 值 |
|:-----|:-----|
| 前置 | F-0 |
| 目标 | 严格按 spec §2.1 重建中间栏：header 视觉隐形（无背景色 / 无分割线）+ 左 [▼ 当前项目 ▾] + 右 [＋][⚙] + 三岔路口/聊天中/Header 三态 |
| 子状态 | 1) 三岔路口态（首次进入：📝 我有作品 / 🌱 从头学习 / 💬 先聊聊）<br>2) 聊天中态（消息列表）<br>3) header 左上角有"状态指示器"小标签（教学中/诊断中/梳理中）<br>4) 项目下拉打开后展示项目列表 + 切换行为 |
| 涉及目录 | `components/layout/ChatHeader/`（新）+ `components/chat/ChatView/`（重建）+ `components/chat/ThreeWayPath/`（新） + `components/chat/MessageList/` + `components/chat/MessageBubble/` |
| DoD | □ header 视觉隐形（无 bg / 无 border-bottom）<br>□ [▼ 项目名 ▾] 点击下拉<br>□ [＋] 新建会话归入当前项目<br>□ [⚙] 打开 SettingsPanel<br>□ 三岔路口态：3 个按钮（我有作品/从头学习/先聊聊）<br>□ 状态指示器小标签：教学/诊断/梳理 三态<br>□ 项目切换 → 自动切到该项目最后活跃会话 |
| 依据 | spec §2.1（ASCII 布局图） + §4.1（三岔路口） + §2.4（按钮表） + §3.3（项目-会话关系） |

#### F-3 [P5-C] 右侧栏一栏四态打磨

| 属性 | 值 |
|:-----|:-----|
| 前置 | F-0 |
| 目标 | 严格按 spec §2.1 + §2.4 重建右侧栏：header [⤢][─][□][✕] **不用 fixed** + 动态工具标签 + 工具网格空态 + 多工具切换 |
| 子状态 | 1) 完全收起态（width=0）<br>2) 工具网格态（无 activePanel：展示 6 个工具卡 2 列）<br>3) 单工具态（activePanel 有 1 个，标签 1 个）<br>4) 多工具态（activePanel 有 N 个，标签 N 个 + 标签 [＋]）<br>5) 工具网格态的 [⤢] 行为：点击展开到工具网格（不切到具体工具）<br>6) 标签 [×] 关闭单工具<br>7) 标签 [＋] 打开工具网格（不主动选工具） |
| 涉及目录 | `components/layout/RightPanel/`（新）+ `RightPanel/index.tsx` + `RightPanel.module.css` + 5 个子组件：`RightPanelHeader/ ToolGrid/ ToolTabs/ ToolContent/ WindowControls/` |
| DoD | □ [⤢][─][□][✕] 在 RightPanel 内 `position: relative`（不是 fixed）<br>□ 工具网格态：2 列 6 个工具卡<br>□ 单工具态：标签层 + 内容层<br>□ 多工具态：标签层 N 个 + 标签 [＋]<br>□ 标签 [＋] 打开工具网格（与 F-3-2 一致）<br>□ 标签 [×] 移除单工具<br>□ 收起态 width=0 + 200ms ease 动画<br>□ 不主动打开右侧栏（spec §4.8 跨 F-1/F-2/F-3/F-4/F-5 通用）<br>□ 工具网格卡片点击 → `useRightPanelStore.openTool(id)` |
| 依据 | spec §2.1 + §2.2 + §2.4 + §4.8（不主动打开） + §13.1（不封装基础 UI 库） |

#### F-4 [P5-D] 输入区一区四态打磨

| 属性 | 值 |
|:-----|:-----|
| 前置 | F-0 |
| 目标 | 严格按 spec §5 重建输入区：工具栏一行（[模板] + 🟢🟡🔴 + 🔒）+ 输入框 + 发送按钮；总高 = 屏幕 1/6 |
| 子状态 | 1) 工具栏态：左 [模板] / 右 🟢🟡🔴 + 🔒<br>2) 输入框态：focus 高亮 + placeholder 随机轮换（4 条 prompt）<br>3) 发送按钮态：空时 disabled / 有内容时 enabled<br>4) 态度灯态：🟢 默认 / 点击切换 / 🔒 锁定后 AI 不自动切换<br>5) 教学笔记预览态：[模板] 触发后聊天中弹出预览卡片 + [记录到教学笔记] 按钮 |
| 涉及目录 | `components/chat/InputArea/`（新）+ 5 个子组件：`InputToolbar/ AttitudeIndicator/ MessageInput/ SendButton/ TeachingTip/ TemplatePreview/` |
| DoD | □ 工具栏高度 32px（`--toolbar-height`）<br>□ 输入区总高 = `clamp(60px, 100vh/6, 180px)`<br>□ AttitudeIndicator 3 灯 + 1 锁（spec §5.2）<br>□ 态度灯点击切换：当前亮，其余灭<br>□ 🔒 锁定后锁图标变实心 + 颜色加深<br>□ placeholder 4 条随机轮换（spec §5.3）<br>□ 输入框不随教学阶段改变 UI（spec §5.4）<br>□ [模板] 触发 → 聊天末尾插入 TemplatePreview 卡片<br>□ TemplatePreview 卡片 [记录到教学笔记] 按钮 → 右侧栏展开"教学笔记"工具（spec §4.11） |
| 依据 | spec §5 + §4.11（教学笔记） + §12.2（输入区 token） |

#### F-5 [P5-E] 动画与过渡打磨

| 属性 | 值 |
|:-----|:-----|
| 前置 | F-1、F-2、F-3、F-4 完成（依赖具体组件） |
| 目标 | 严格按 spec §2.5 动画规范统一所有过渡 |
| 涉及文件 | `styles/variables.css`（动画 token 统一）+ 上述 4 个组件微调 |
| DoD | □ 左侧栏宽度 200ms `cubic-bezier(0.25, 1, 0.5, 1)`<br>□ 右侧栏宽度 200ms 同缓动<br>□ 工具标签切换 150ms ease<br>□ 态度灯切换 150ms ease（opacity + transform）<br>□ 卡片高亮（C-2 ProgressSummary）3s 窗口 + 弹性脉冲<br>□ `prefers-reduced-motion` 支持：减弱所有过渡<br>□ CSS 变量统一在 variables.css 定义缓动 |
| 依据 | spec §2.5 + §12.2（缓动统一 token） |

#### F-6 [P5-F] 二次重写全局验收

| 属性 | 值 |
|:-----|:-----|
| 前置 | F-1~F-5 全部完成 |
| 目标 | 跨栏全状态验证 + E2E 闭环 |
| DoD | □ `npm run typecheck` 0 error<br>□ `npm run test` 全绿<br>□ `npm run lint` 0 error<br>□ 跨栏所有状态（每栏 × 8 种状态）目视 + 截图核对<br>□ 与 spec §2.1 ASCII 布局图逐像素对齐<br>□ 用户手动验收签字 |

---

### Phase E：调研与收尾

#### E-1 [P3-5] 外部项目代码研究

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（可随时做，建议在 E 阶段） |
| 目标 | Clone 并研读 6 个外部项目，输出可落地模式参考 |
| 研究范围 | **代码级**：InkOS（状态机+真相文件）、OpenWrite（Codex UI+项目管理）、Letta（记忆调度）<br>**产品级**：91Writing（提示词库+进度可视化）、SoloEnt（故事宪法）<br>**论文级**：CoachGPT（Scaffolding 教学）、Khan Academy WC |
| DoD | □ InkOS Truth File 实现报告<br>□ OpenWrite Codex 组件树报告<br>□ Letta 记忆调度分析<br>□ 其他项目产品级参考笔记 |
| 依据 | 规格 §附录B、附录C、决策日志 Letta 记录 |

#### E-2 [P3-1] 文件上传 + 分章

| 属性 | 值 |
|:-----|:-----|
| 前置 | P0-4 ✅（项目 IPC 就绪） |
| 目标 | 用户上传文件（txt/docx）自动导入为作品、插入分章 IPC 失败路径 |
| 涉及文件 | 文件选择器组件 + IPC 通道 |
| DoD | □ 支持 txt/docx 上传<br>□ 上传后自动创建项目章节<br>□ 失败时静默提示 |
| 依据 | 规格 §7（文件上传） |

#### E-3 [P3-2~4] 全局清理与遗留评估

| 属性 | 值 |
|:-----|:-----|
| 前置 | 全部 A~D 完成 |
| 目标 | TypeScript 全局清理（as / ts-ignore）、旧待定任务决策（SKILL/DIST/INFRA）、V4 评估 |
| 涉及文件 | 全局 |
| DoD | □ 所有 `as` 断言清理（除 DOM API）<br>□ 旧待定任务标记为保留/关闭/外迁<br>□ 决策日志中有记录 |
| 依据 | R-019、决策日志 |

#### E-4 [P3-6] 全链路验收测试

| 属性 | 值 |
|:-----|:-----|
| 前置 | 全部 E-1~E-3 完成 |
| 目标 | 验证完整教学闭环：对话→诊断→教学→训练→验证 |
| DoD | □ `npm run gate` 全绿<br>□ 教学闭环可走通<br>□ 进度一致性验收<br>□ 数据迁移验收<br>□ IPC 失败降级验收<br>□ 加载态覆盖验收 |
| 依据 | 规格 §15（验收标准） |

---

## 三、依赖图

```
Phase A ─── Phase B ─── Phase C ─── Phase D ─── Phase E
  │            │            │            │            │
  A-1          B-1          C-1          D-1          E-1 (独立)
  │            │            │            │            │
  A-2 ──── B-2 ──┬─── C-2   D-2 (独立)  E-2
                  │         D-3 (独立)  │
                  └─── C-3              E-3
                                       │
                                       E-4
```

---

## 四、执行纪律

1. **先读规格再动手** — 每个 Phase 开始前，重读 `system-rewrite-spec.md` 对应章节
2. **不跳步** — A 未完成不进入 B，B 未完成不进入 C
3. **不顺手改无关文件** — R-021 约束
4. **交付前跑门禁** — `npm run gate`（typecheck + test + lint）
5. **失败回退** — 一个任务超过 2 小时或遇到阻塞，停手问用户
6. **完成标记** — 每个 DoD 项目打 ✅ 后，更新 TASK-CHAIN.md + TASK-TABLE.md 状态

---

## 五、引用索引

| 引用文件 | 用途 |
|:---------|:-----|
| `dev-docs/designs/2026-06-17-system-rewrite-spec.md` | 设计权威来源，所有实现以此为准 |
| `docs/tasks/TASK-CHAIN.md` | 全景依赖图 + 历史已完成任务 |
| `docs/tasks/TASK-TABLE.md` | 优先级总表 + 状态追踪 |
| `docs/tasks/REWRITE-TASK-DETAILS.md` | 每个任务的详细目标/DoD/涉及文件 |
| `docs/decision-log.md` | 关键决策历史 |
| `AGENTS.md` | 项目规则入口 |


## 四、待处理（债务记录）

记录 B/C 阶段发现但不在当前任务范围、需要后续阶段处理的问题。

### RWR-DEBT-1: V4.0 Skill 拆分未在代码中集成

- **发现阶段**: C-6 (P1-12)
- **现象**:
  - `resources/prompts/skills/` 下 5 个 Skill 文件已存在 (SKILL-IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO)
  - `yuesheng-prompt-v3.md` 是 V4.0 装配说明 (105 行),不是行为约束 Prompt
  - `prompt-loader.ts` 和 `dynamic-context.service.ts` 不读 Skill 文件
  - 实际行为约束真源 (`teacher-prompt.md` / `teaching-agent-prompt-v1.md` / `core-principles.md`) 代码不读
- **当前绕过**: C-6 行为约束直接追加到 v3.md 末尾 (文档语义不干净,但即时生效)
- **后续处理**: 后续阶段重接 prompt 加载逻辑,让 Skill 文件生效