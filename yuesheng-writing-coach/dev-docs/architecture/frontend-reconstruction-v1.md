# 前端重构方案 V1

> 基于新设计稿（5 页面 + TabBar 导航）的架构分析与重构路线图。
>
> 关联：user-journey-v1.md, AGENTS.md, R-019 代码规范标准, R-010 最小化范围

---

## 目录

1. [现有架构评估](#1-现有架构评估)
2. [页面路由设计](#2-页面路由设计)
3. [组件树重建](#3-组件树重建)
4. [Store 改造方案](#4-store-改造方案)
5. [IPC 复用情况](#5-ipc-复用情况)
6. [重构步骤（分阶段）](#6-重构步骤分阶段)
7. [现有组件复用清单](#7-现有组件复用清单)
8. [风险与依赖](#8-风险与依赖)

---

## 1. 现有架构评估

### 1.1 当前布局的问题

| 问题 | 描述 | 影响 |
|------|------|------|
| **桌面优先三栏布局** | 左侧栏 220px + 中栏 flex:1 + 右侧栏 360px | 移动端 overlay 抽屉模式是事后补丁，体验割裂；新设计采用全屏页面栈模式，无需三栏 |
| **右侧栏 7 workspace 膨胀** | Catalog/Progress/LearningLog/Works/TeachingNote/Settings/StageProgress 全部挤在右侧面板 | 用户注意力分散，新设计将这些功能分散到 5 个独立页面中 |
| **CenterPanel 4 视图切换** | chat/training/editor/retro 四模式通过 centerMode 切换 | 耦合严重，训练工坊、复盘、编辑器复用度低，新设计应拆为独立页面 |
| **TabBar 仅用于移动端** | 桌面端无底部导航，TabBar 只有 3 个 tab（会话/消息/工具） | 新设计需要 4 tab（书架/对话/应用）作为主导航，TabBar 需要升级为一级路由载体 |
| **Store 数量膨胀（20 个）** | 状态分散在 20 个 zustand store 中，部分 store 职责重叠 | 维护成本高，部分 store 在新设计下可合并或废弃 |

### 1.2 新旧设计核心差异

| 维度 | 当前架构 | 新设计 |
|------|---------|--------|
| **导航模型** | 桌面三栏+拖拽 / 移动端 TabBar | 全平台统一 TabBar (4 tab) + 页面栈 push/pop |
| **页面关系** | 同屏多面板并行 | 单屏单页面 + 栈式层级 |
| **内容组织** | 左栏(列表)→中栏(内容)→右栏(工具) | 书架→项目空间→对话 / 对话列表 / 应用中心 |
| **TabBar 可见性** | 仅移动端，3 tab | 全平台，4 tab（书架页/对话列表页/应用中心页，隐藏于项目空间页和对话页） |
| **应用入口** | 左栏 SessionList 直接进入对话 | 书架页 ProjectCard → 项目空间 → 开始学习 → 对话 |

---

## 2. 页面路由设计

### 2.1 页面栈结构

```
TabBar 页面（3 tab，TabBar 可见）：
  ├── 📚 BookshelfPage          ← Tab 1: 书架
  ├── 💬 ConversationsPage       ← Tab 2: 对话列表
  └── 🧩 AppsPage                ← Tab 3: 应用中心

TabBar 隐藏页面（页面栈 push/pop）：
  ├── ProjectSpacePage          ← 从 BookshelfPage push
  │     └── ChatPage            ← 从 ProjectSpacePage "开始新学习" push
  │           └── (训练/复盘等嵌套视图)
  └── (ChatPage 也可从 ConversationsPage push)
```

### 2.2 页面栈关系图

```
TabBar[书架] → BookshelfPage
  └── 点击项目卡片 → push → ProjectSpacePage
        └── 点击"开始新的学习" → push → ChatPage

TabBar[对话] → ConversationsPage
  └── 点击对话项 → push → ChatPage

TabBar[应用] → AppsPage
  └── (各应用卡片打开方式待定，可能是 overlay 或独立页)

TabBar 可见性：
  BookshelfPage       → TabBar ✅ 显示
  ConversationsPage   → TabBar ✅ 显示
  AppsPage            → TabBar ✅ 显示
  ProjectSpacePage    → TabBar ❌ 隐藏（push 状态）
  ChatPage            → TabBar ❌ 隐藏（push 状态）
```

### 2.3 路由实现方案

使用 React Context + useState 实现轻量页面栈路由，不引入 react-router（避免 Electron 环境下 hash/history 路由的额外复杂度）：

```typescript
// src/renderer/routing/PageStackContext.tsx
type PageId = 'bookshelf' | 'conversations' | 'apps' | 'project-space' | 'chat';

interface PageStackEntry {
  id: PageId;
  params?: Record<string, string>;  // 如 { projectId: 'xxx' }
}

// TabBar 可见性规则：栈顶为 bookshelf/conversations/apps 时显示
function shouldShowTabBar(stack: PageStackEntry[]): boolean {
  const top = stack[stack.length - 1];
  return top?.id === 'bookshelf' || top?.id === 'conversations' || top?.id === 'apps';
}
```

替代方案：若后续需要更深层嵌套（如 ChatPage 内打开设置页），可升级为社区路由库如 `atomic-router` 或 `wouter`，但初期手动栈管理足够。

---

## 3. 组件树重建

### 3.1 新组件树结构

```
App (保持)
└── PageStackRouter          ← 新增：页面栈管理器
    ├── TabBar               ← 改造：升级为 4 tab，条件渲染
    ├── BookshelfPage        ← 新建
    │   ├── ProjectCard      ← 新建（可复用 ProjectList 的样式）
    │   └── NewProjectButton ← 新建
    ├── ConversationsPage    ← 新建
    │   └── ConversationItem ← 新建（借鉴 SessionList）
    ├── AppsPage             ← 新建
    │   ├── GrowthSection    ← 新建（借鉴 GrowthPanel）
    │   └── ToolSection      ← 新建
    ├── ProjectSpacePage     ← 新建
    │   ├── ProjectHeader    ← 新建
    │   ├── StatsOverview    ← 新建
    │   ├── RadarChart       ← 新建（五维能力画像）
    │   ├── RecentRecords    ← 新建（学习记录列表）
    │   └── ChapterList      ← 复用 ChapterEditor / CatalogWorkspace 部分逻辑
    └── ChatPage             ← 新建（整合现有 ChatView + 改造）
        ├── ChatHeader       ← 新建（项目名 + 学习状态徽章）
        ├── WelcomeCard      ← 复用现有 WelcomeCard
        ├── MessageList      ← 复用现有 MessageList（需改造）
        ├── MessageBubble    ← 复用现有 MessageBubble（需改造：AI 教学气泡）
        ├── TypingIndicator  ← 复用现有 TypingIndicator
        ├── FooterInputBar   ← 新建（替代现有 Footer，去掉态度灯等）
        └── TrainingWorkshop ← 复用（作为 ChatPage 内嵌组件）
```

### 3.2 废弃的顶级组件

| 组件 | 废弃原因 | 替代方案 |
|------|---------|---------|
| AppShell | 三栏布局不再适用 | PageStackRouter + TabBar |
| LeftPanel | 左侧栏废弃 | BookshelfPage 取代项目列表功能；ConversationsPage 取代会话列表功能 |
| CenterPanel | centerMode 多视图切换废弃 | 各页面独立，ChatPage 直接渲染聊天内容 |
| RightPanel | 右侧栏废弃 | 能力画像、作品列表、学习记录等功能分散到 ProjectSpacePage / AppsPage |
| Footer（旧） | 态度灯/模板/锁不再需要 | 全新 FooterInputBar，仅含工具条+输入框+发送 |

### 3.3 保留/改造的组件

见第 7 节[现有组件复用清单]。

---

## 4. Store 改造方案

### 4.1 当前 20 个 Store 分析

| 编号 | Store 名称 | 当前职责 | 改造建议 |
|:----:|-----------|---------|---------|
| 1 | useChatStore | 消息列表、流式发送、onboarding | **保留核心功能**，移除 onboaring（迁至专用 store），拆分出 useChatUI |
| 2 | useSessionStore | 会话 CRUD | **保留**，但 ConversationsPage 需要新 selector |
| 3 | useTrainingStore | 训练工坊全状态 | **保留**，作为 ChatPage 内嵌训练功能的数据源 |
| 4 | useProjectStore | 项目列表 CRUD | **保留**，BookshelfPage 主数据源 |
| 5 | useManuscriptStore | 作品列表 CRUD | **保留**，ProjectSpacePage 需要 |
| 6 | useChapterStore | 章节管理 + 缓存 | **保留**，ProjectSpacePage 需要章节列表 |
| 7 | useProgressStore | 教学进度 | **保留** persist，为项目空间页统计提供数据 |
| 8 | useDiagStore | 诊断数据 | **保留**，ChatPage 的诊断卡片需要 |
| 9 | useTeachingStateStore | 教学状态机 | **保留**，ChatPage 头部状态徽章需要 |
| 10 | useStudentContextStore | 学生画像 | **保留**，但简化 localStorage 方案 |
| 11 | useConfigStore | API 配置 | **保留**，全局依赖 |
| 12 | useEditorStore | 编辑器偏好 | **保留** persist，但需确认编辑器在新设计中的位置 |
| 13 | useUiStore | 左栏 tab、态度档位 | **需要改造**：态度档位移至 useConfigStore，左栏 tab 废弃，保留训练上下文 |
| 14 | useUiLayoutStore | 三栏宽度、拖拽 | **废弃**：新设计为全屏页面栈，无需三栏宽度管理 |
| 15 | useDrawerStore | 右侧栏开闭 | **废弃**：右侧栏在新设计中被移除 |
| 16 | useRightPanelStore | 多 Store 协调 | **废弃**：X-01 协议不再需要 |
| 17 | useRightToolsStore | 工具标签管理 | **废弃**：右侧工具面板不再存在 |
| 18 | usePanelSessionStore | 右侧栏会话标签 | **废弃**：不再需要 L1 标签管理 |
| 19 | useHintStore | 提示点数 | **保留**，但功能位置待定 |
| 20 | useParadigmStore | chat/editor 范式切换 | **废弃**：新设计不使用双范式架构 |

### 4.2 收敛后 Store 清单（约 12 个）

```
保留（核心业务）：
  useChatStore        — 消息流，去掉 onboaring 相关
  useSessionStore     — 会话 CRUD
  useTrainingStore    — 训练工坊
  useProjectStore     — 项目
  useManuscriptStore  — 作品
  useChapterStore     — 章节
  useProgressStore    — 教学进度（persist）
  useDiagStore        — 诊断
  useTeachingStateStore — 教学状态
  useStudentContextStore — 学生画像
  useConfigStore      — 配置

废弃（旧架构产物）：
  useUiLayoutStore    — 三栏宽度不再需要
  useDrawerStore      — 右侧栏移除
  useRightPanelStore  — 协调层不再需要
  useRightToolsStore  — 工具面板移除
  usePanelSessionStore — 标签会话移除
  useParadigmStore    — 双范式废弃

需要改造：
  useUiStore          — 废弃 leftTab/attitudeLocked，保留 trainingContexts
  useEditorStore      — 保留但确认用途
  useHintStore        — 保留

新增：
  usePageStackStore   — 页面栈管理（当前页面栈、TabBar 可见性）
  useBookshelfStore   — 书架页 UI 状态（排序、筛选、搜索）
  useChatUIStore      — 对话页 UI 状态（搜索、快捷选项、输入栏状态）
```

### 4.3 usePageStackStore 设计

```typescript
interface PageStackState {
  stack: PageStackEntry[];
  // 派生值
  currentPage: PageId;
  showTabBar: boolean;
}

interface PageStackActions {
  push: (page: PageStackEntry) => void;
  pop: () => void;
  popToRoot: () => void;
  navigateToTab: (tab: PageId) => void;  // 切换 TabBar 页面，清空栈
}
```

TabBar 可见性规则：栈顶是 `'bookshelf' | 'conversations' | 'apps'` 之一时显示，其余隐藏。

---

## 5. IPC 复用情况

### 5.1 直接复用的 IPC 通道

新设计需要的 IPC 通道几乎全部可以直接复用：

| IPC 通道 | 新页面消费方 | 备注 |
|----------|-------------|------|
| `project:list/get/create/update/delete` | BookshelfPage, ProjectSpacePage | 完全复用 |
| `session:list/create/delete/rename/getMessages` | ConversationsPage, ChatPage | 完全复用 |
| `chat:send` / `chat:stop` | ChatPage | 完全复用 |
| `chat:stream:data` / `chat:stream:end` | ChatPage | 事件订阅 |
| `diagnosis:query` | ChatPage | 完全复用 |
| `training:recommend/assign/complete/evaluate` | ChatPage 内 TrainingWorkshop | 完全复用 |
| `manuscript:list/get/create/update/delete` | ProjectSpacePage | 完全复用 |
| `chapter:list/get/create/delete/updateContent` | ProjectSpacePage | 完全复用 |
| `retro:generate/save` | ChatPage 内训练回溯 | 完全复用 |
| `ability:getProfile` | ProjectSpacePage（雷达图） | 完全复用 |
| `growth:getTrends/getGlobalTrends` | AppsPage（成长报告） | 完全复用 |
| `config:get/set` | 设置入口 | 完全复用 |
| `teachingState:get/update/confirm` | ChatPage | 完全复用 |

### 5.2 需要新增的 IPC 通道

| 新通道 | 用途 | 备注 |
|--------|------|------|
| `project:getStats` | 项目空间页的统计（诊断次数、训练次数、学习天数） | 可以从现有数据聚合，但专门的统计查询更高效 |
| `project:getCapabilityRadar` | 项目空间页（五维雷达图） | 能力画像的聚合版本 |
| `conversation:getSummaries` | 对话列表页（对话摘要文本） | 目前 session:list 返回的基础信息不够 |

### 5.3 事件通道复用

| 事件通道 | 新页面消费方 | 备注 |
|----------|-------------|------|
| `diagnosis:updated` | ChatPage | 完全复用 |
| `teachingState:updated` | ChatPage（状态徽章） | 完全复用 |
| `teachingState:mastery` | ChatPage | 完全复用 |
| `chat:tool:executing` | ChatPage | 完全复用 |

---

## 6. 重构步骤（分阶段）

### 阶段 A — 基础设施（预估：3-5 天）

**目标**：建立新页面栈路由骨架，确保基础导航可用，TabBar 按规则显示/隐藏。

**交付物**：
1. `usePageStackStore` — 页面栈管理
2. `PageStackRouter` — 页面栈渲染容器
3. 改造 `TabBar` — 从 3 tab(会话/消息/工具) 升级为 4 tab(书架/对话/应用)
4. 5 个页面的空壳（BookshelfPage / ConversationsPage / AppsPage / ProjectSpacePage / ChatPage）
5. TabBar 可见性条件渲染
6. 将当前 `App.tsx` 中 `AppShell` 替换为 `PageStackRouter + TabBar`

**门禁**：
- `npm run typecheck` 零错误
- TabBar 4 tab 切换正确，各页面空壳渲染
- push ProjectSpacePage / ChatPage 时 TabBar 隐藏
- pop 回一级页面时 TabBar 恢复

**回退**：保留 `AppShell` 组件，通过条件编译切换（`__NEW_UI__` flag），失败时回退到旧 `AppShell`。

### 阶段 B — 新页面实现（预估：5-7 天）

**目标**：实现 5 个页面的 UI 内容，重用现有组件。

**子任务 B1 — BookshelfPage + ProjectSpacePage（2 天）**
- BookshelfPage：项目卡片列表 + 新建项目按钮
- ProjectSpacePage：项目统计、五维雷达图、最近学习记录、章节列表
- 复用：`useProjectStore`、`useManuscriptStore`、`useChapterStore`、`useProgressStore`
- 新建：`ProjectCard` 组件、`RadarChart` 组件、`StatsOverview` 组件

**子任务 B2 — ChatPage 核心（3 天）**
- ChatPage 顶部：项目名 + 学习状态徽章（复用 `useTeachingStateStore`）
- 欢迎引导：月笙头像 + 快捷选项（复用 `WelcomeCard`，改造样式）
- 消息气泡流：复用 `MessageList` + `MessageBubble`，改造 AI 教学气泡样式
- Footer 输入栏：新建 `FooterInputBar`（去掉态度灯、模板、锁）
- 训练/复盘作为 ChatPage 内嵌视图

**子任务 B3 — ConversationsPage + AppsPage（2 天）**
- ConversationsPage：对话列表（复用 `useSessionStore`）
- AppsPage：应用网格（成长报告、训练计划、技法库、素材库 等）

**门禁**：
- 每个页面独立可测
- BookshelfPage 项目列表加载正确，点击进入 ProjectSpacePage
- ChatPage 消息发送/流式接收正常
- ConversationsPage 对话列表加载正确，点击进入 ChatPage
- `npm run test` 全绿

### 阶段 C — Store 瘦身（预估：2-3 天）

**目标**：废弃 6 个旧布局 Store，收敛到约 12 个核心 Store。

**具体操作**：
1. `useUiLayoutStore` → 标记废弃，确认无引用后删除
2. `useDrawerStore` → 标记废弃，确认无引用后删除
3. `useRightPanelStore` → 标记废弃，确认无引用后删除
4. `useRightToolsStore` → 标记废弃，确认无引用后删除
5. `usePanelSessionStore` → 标记废弃，确认无引用后删除
6. `useParadigmStore` → 标记废弃，确认无引用后删除
7. `useUiStore` → 瘦身，移除 leftTab / attitudeLocked，保留 trainingContexts

**注意**：各个 Store 之间有隐式依赖（如 `useRightPanelStore` 内部调用了 `useDrawerStore` 和 `usePanelSessionStore`），必须在所有消费方全部移除后才可删除 Store 文件。

**门禁**：
- 废弃 Store 文件删除后 `npm run typecheck` 零错误
- 旧页面（AppShell 等）已不再引用废弃 Store
- `npm run test` 全绿

**回退**：不删除源文件，只标记 `@deprecated`，保留至阶段 E 确认新架构稳定再物理删除。

### 阶段 D — 组件重用与重构（预估：3-4 天）

**目标**：完成各组件的改造/重构，消除旧布局代码的遗留引用。

**子任务 D1 — 聊天组件改造（2 天）**
- 改造 `MessageBubble`：支持 AI 教学气泡（诊断分析标签 + 问题列表 + 引导操作按钮）
- 改造 `MessageList`：支持分步渐入动画（step-in）
- 改造 `TypingIndicator`：三点脉冲 + 文字状态
- 新建 `FooterInputBar`：工具条 + 输入框 + 发送按钮

**子任务 D2 — 诊断/训练组件整理（1-2 天）**
- 确认 `DiagnosisCard` / `EditPanel` / `EvaluationCard` / `GrowthCard` 在 ChatPage 中的复用路径
- `TrainingWorkshop`（含 FiveStepFlow 等子组件）作为 ChatPage 内嵌视图

**门禁**：
- 聊天组件改造后功能完整（发送/接收/流式/诊断卡片）
- 训练工坊从 ChatPage 正常进入和退出

### 阶段 E — 旧组件废弃与清理（预估：1-2 天）

**目标**：删除不再需要的旧组件文件和 Store，确保代码库无死代码。

**具体操作**：
1. 确认无引用后物理删除：`AppShell` 目录、`LeftPanel` 目录、`RightPanel` 目录、`CenterPanel` 目录
2. 确认无引用后物理删除废弃 Store 文件
3. 将 `components_archived/` 中的非必要备份清理（或确认不再需要后删除）
4. 更新 `AGENTS.md` 中的组件/Store 索引

**门禁**：
- `npm run typecheck` 零错误
- `npm run test` 全绿
- `npm run lint --max-warnings 300` 零 error

### 阶段重置计划

| 阶段 | 前置依赖 | 风险 | 若失败则 |
|:----:|---------|------|---------|
| A | - | 低 | 回退到 `AppShell` |
| B | A | 中 | 保留旧页面并行运行 |
| C | B | 中高 | Store 只标记 @deprecated，不物理删除 |
| D | B | 中 | 保留旧组件文件，新页面用新组件 |
| E | C+D | 低 | 保留废弃文件 |

---

## 7. 现有组件复用清单

### 7.1 可直接复用的组件

| 组件 | 文件路径 | 新页面使用方式 |
|------|---------|--------------|
| `MessageBubble` | `components/chat/MessageBubble.tsx` | ChatPage 消息气泡（需样式改造，结构不变） |
| `MessageList` | `components/chat/MessageList.tsx` | ChatPage 消息列表（需动画改造） |
| `TypingIndicator` | `components/chat/TypingIndicator.tsx` | ChatPage 思考中状态 |
| `WelcomeCard` | `components/chat/WelcomeCard.tsx` | ChatPage 欢迎引导（改造快捷选项） |
| `TrainingBridgeCard` | `components/chat/TrainingBridgeCard.tsx` | ChatPage 桥接推荐 |
| `DiagnosisCard` | `components/diagnosis/DiagnosisCard.tsx` | ChatPage 诊断分析 |
| `EditPanel` | `components/diagnosis/EditPanel.tsx` | ChatPage 修改面板 |
| `EvaluationCard` | `components/diagnosis/EvaluationCard.tsx` | ChatPage 评估反馈 |
| `GrowthCard` | `components/diagnosis/GrowthCard.tsx` | ChatPage 成长总结 |
| `TrainingWorkshop` | `components/training/TrainingWorkshop.tsx` | ChatPage 内嵌训练视图 |
| `ActiveTrainingView` | `components/training/ActiveTrainingView.tsx` | TrainingWorkshop 子组件 |
| `FiveStepFlow` | `components/training/flow/FiveStepFlow.tsx` | TrainingWorkshop 子组件 |
| `RetroSummaryView` | `components/retro/RetroSummaryView.tsx` | ChatPage 内嵌复盘视图 |
| `EmptyState` | `components/common/EmptyState.tsx` | 各页面空状态 |
| `Card` | `components/common/Card.tsx` | AppPage 应用卡片 |
| `Badge` | `components/common/Badge.tsx` | 状态徽章 |
| `Button` | `components/common/Button.tsx` | 通用按钮 |
| `ErrorCardsSection` | `components/training/ErrorCardsSection.tsx` | TrainingWorkshop 子组件 |
| `RecommendationsSection` | `components/training/RecommendationsSection.tsx` | TrainingWorkshop 子组件 |
| `GoalTrackingPanel` | `components/training/GoalTrackingPanel.tsx` | TrainingWorkshop 子组件 |

### 7.2 需要改造的组件

| 组件 | 改造内容 | 预估工作量 |
|------|---------|-----------|
| `MessageBubble` | 新增 AI 教学气泡样式（诊断标签 + 问题列表 + 引导按钮）；移除旧三栏布局相关内联样式 | 中 |
| `MessageList` | 新增分步渐入动画（step-in）；移除与旧 Footer 的交互耦合 | 中 |
| `WelcomeCard` | 改为 3 个快捷选项（设计稿中的"写一段文字给我分析"等） | 低 |
| `TabBar` | 从 3 tab(会话/消息/工具) 改为 4 tab(书架/对话/应用)；图标更换；增加 TabBar 可见性 props | 低 |
| `TrainingWorkshop` | 适配 ChatPage 内嵌容器，移除对 RightPanel 的依赖 | 中 |
| `EvaluationCard` / `GrowthCard` | 适配新设计中的气泡样式 | 低 |

### 7.3 需要新建的组件

| 组件 | 用途 | 依赖 Store |
|------|------|-----------|
| `PageStackRouter` | 页面栈渲染容器 + TabBar 可见性控制 | usePageStackStore |
| `BookshelfPage` | 项目卡片列表页 | useProjectStore |
| `ProjectCard` | 项目卡片（项目名 + 学习状态文字） | (props) |
| `ProjectSpacePage` | 项目空间主页 | useProjectStore, useProgressStore, useManuscriptStore, useChapterStore |
| `ProjectHeader` | 项目名 + 返回按钮 | (props) |
| `StatsOverview` | 诊断次数/训练次数/学习天数统计 | useProgressStore |
| `RadarChart` | 五维能力雷达图 | 能力画像 IPC |
| `RecentRecords` | 最近学习记录列表 | useTrainingStore, useDiagStore |
| `ConversationsPage` | 对话列表页 | useSessionStore |
| `ConversationItem` | 对话列表项 | (props) |
| `AppsPage` | 应用中心网格页 | - |
| `AppCard` | 应用卡片 | (props) |
| `ChatPage` | 对话主页 | useChatStore, useSessionStore, useTeachingStateStore |
| `ChatHeader` | 项目名 + 学习状态徽章 | useTeachingStateStore |
| `FooterInputBar` | 工具条 + 输入框 + 发送按钮 | useChatStore |
| `TeachingStatusBadge` | 学习状态徽章（诊断中/训练中/已完成) | useTeachingStateStore |

### 7.4 需要废弃的组件

| 组件 | 文件路径 | 废弃原因 |
|------|---------|---------|
| `AppShell` | `components/AppShell/` | 三栏布局整体废弃 |
| `LeftPanel` | `components/left/LeftPanel/` | 左侧栏整体废弃 |
| `SessionList` | `components/left/SessionList/` | ConversationsPage 替代 |
| `ProjectList` | `components/left/ProjectList/` | BookshelfPage 替代 |
| `CenterPanel` | `components/center/CenterPanel/` | centerMode 多视图切换废弃 |
| `CenterHeader` | `components/center/CenterHeader/` | 旧 Header 废弃 |
| `RightPanel` | `components/right/RightPanel/` | 右侧栏整体废弃 |
| `ToolTabs` | `components/right/ToolTabs/` | 右侧工具标签废弃 |
| `SubTabs` | `components/right/SubTabs/` | 右侧子标签废弃 |
| `ToolGrid` | `components/right/ToolGrid/` | 右侧工具网格废弃 |
| `Footer` | `components/center/Footer/` | 态度灯/模板/锁废弃，替换为 FooterInputBar |
| `ChatView` | `components/chat/ChatView.tsx` | 被 ChatPage 替代（ChatPage 直接组合 MessageList 等） |
| `OnboardingFlow` | `components/chat/OnboardingFlow.tsx` | 新引导流程在 ChatPage 内实现 |
| `ChatSearchBar` | `components/chat/ChatSearchBar.tsx` | 搜索功能移到 ChatPage 内部 |
| `RightDrawer` | `components/layout/RightDrawer.tsx` | 右侧栏废弃 |
| `HintPanel` | `components/layout/HintPanel.tsx` | 提示点面板待重新定位 |
| `DiagnosisPanel` | `components/layout/DiagnosisPanel.tsx` | 诊断面板已内嵌到聊天气泡 |
| `SessionTabBar` | `components/layout/SessionTabBar.tsx` | 会话标签废弃 |
| `ModeSwitch` | `components/layout/ModeSwitch.tsx` | 双范式废弃 |
| `SoloSidebar` | `components/layout/SoloSidebar.tsx` | 旧布局组件 |
| `WorkTreePanel` | `components/layout/WorkTreePanel.tsx` | 作品树移到 ProjectSpacePage |
| `GrowthPanel` | `components/growth/GrowthPanel.tsx` | 移到 AppsPage |
| `TrendChart` | `components/growth/TrendChart.tsx` | 移到 AppsPage |
| `AbilityProfilePanel` | `components/profile/AbilityProfilePanel.tsx` | 移到 ProjectSpacePage 雷达图 |
| `ToolsPanel` | `components/tools/ToolsPanel.tsx` | 移到 AppsPage |
| `SettingsPanel` | `components/settings/SettingsPanel.tsx` | 保留或移到单独设置页 |
| `SearchPanel` | `components/search/SearchPanel.tsx` | 保留或废弃 |
| `ManuscriptPanel` | `components/manuscript/ManuscriptPanel.tsx` | 编辑器保留，但嵌入到 ProjectSpacePage 或独立页 |
| `ChapterEditor` | `components/editor/ChapterEditor.tsx` | 同上 |
| `OnboardingFlow` | `components/onboarding/OnboardingFlow.tsx` | 保留或移到 BookshelfPage |

### 7.5 需要保留的原子组件

| 组件 | 文件路径 | 备注 |
|------|---------|------|
| `AppErrorBoundary` | `components/layout/AppErrorBoundary.tsx` | 全局错误边界，保留 |
| `AppConfigGate` | `components/layout/AppConfigGate.tsx` | 配置门禁，保留 |
| `WindowControls` | `components/layout/WindowControls.tsx` | Electron 窗口控制，保留 |
| `Card` | `components/common/Card.tsx` | 原子组件，保留 |
| `Button` | `components/common/Button.tsx` | 原子组件，保留 |
| `Badge` | `components/common/Badge.tsx` | 原子组件，保留 |
| `EmptyState` | `components/common/EmptyState.tsx` | 原子组件，保留 |

---

## 8. 风险与依赖

### 8.1 依赖关系图

```
阶段 A（基础设施）
  ├── 依赖：无
  └── 影响：阶段 B 全部

阶段 B（新页面）
  ├── 依赖：阶段 A
  ├── 依赖：所有核心 Store（useChatStore / useSessionStore 等）
  └── 影响：阶段 C / D

阶段 C（Store 瘦身）
  ├── 依赖：阶段 B（新页面不再引用废弃 Store）
  ├── 前置检查：必须确认所有废弃 Store 无引用
  └── 风险：隐式引用难发现

阶段 D（组件重构）
  ├── 依赖：阶段 B（新页面骨架就位）
  └── 影响：阶段 E

阶段 E（清理）
  ├── 依赖：阶段 C + D
  └── 风险：遗留引用导致 typecheck 失败
```

### 8.2 风险矩阵

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| 废弃 Store 的隐式引用未发现，删除后 typecheck 失败 | 高 | 中 | 先标记 `@deprecated` 保留 1-2 阶段，确认零引用再物理删除 |
| ChatPage 需要同时承载聊天 + 训练 + 复盘，复杂度高 | 中 | 高 | 用子组件（TrainingWorkshop / RetroSummaryView）内嵌，避免 ChatPage 自身膨胀 |
| 旧 Footer 中的态度灯/态度锁功能有用户依赖 | 中 | 中 | 态度档位保持全局，移到 ChatPage 设置入口或 ChatHeader 角落 |
| 页面栈路由与 Electron IPC 窗口控制的交互 | 低 | 高 | 保持 Electron 窗口控制独立于页面栈（WindowControls 不依赖路由） |
| 废弃组件 30+，清理工作量大 | 中 | 低 | 分阶段清理，先移入 `components_archived/`，稳定后再物理删除 |
| 旧测试用例（`__tests__`）引用废弃组件/Store | 高 | 中 | 分阶段同步更新测试用例；Store 方法保持向后兼容直到测试迁移完成 |
| 五维雷达图需要 IPC 数据支持 | 低 | 中 | 先使用 `ability:getProfile` 现有通道，后续优化性能时再新增 `project:getCapabilityRadar` |
| 移动端与桌面端在页面栈模式下 UX 一致性 | 中 | 中 | TabBar 统一全平台，页面栈物理返回与手势返回均支持 |

### 8.3 关键依赖

1. **Store 废弃需逐一验证引用**：使用 `grep -r "useDrawerStore" src/` 等命令确认无引用后才可物理删除
2. **阶段 B 必须完成才可开始 C**：新页面是废弃旧 Store 的前提条件
3. **`AppShell` 保留镜像文件**：在阶段 E 完成前，保留 `AppShell` 作为回退选项
4. **测试覆盖率保持**：每个阶段结束时 `npm run test` 全绿，新增页面应有至少骨架测试
5. **与 IPC 层的兼容性**：不修改现有 IPC 通道名和参数格式，确保主进程 handler 不受影响

### 8.4 执行建议

1. 阶段 A → B → D 为主线，优先确保新 UI 可用
2. 阶段 C（Store 瘦身）和 E（清理）是纯债务削减，可视团队节奏灵活排期
3. 阶段 B 内部推荐 B2（ChatPage）优先，因为这是核心交互路径
4. 每个阶段交付物必须通过 typecheck + test + lint 三道门禁（R-027）

---

## 附录 A：Store 当前行数与预估重构行数

| Store | 当前行数 | 重构后行数 | 变化 |
|-------|---------|-----------|------|
| useChatStore | ~310 | ~250 | 移除 onboarding |
| useSessionStore | ~130 | ~130 | 不变 |
| useTrainingStore | ~145 | ~145 | 不变 |
| useProjectStore | ~50 | ~50 | 不变 |
| useManuscriptStore | ~120 | ~120 | 不变 |
| useChapterStore | ~230 | ~230 | 不变 |
| useProgressStore | ~290 | ~290 | 不变 |
| useDiagStore | ~210 | ~210 | 不变 |
| useTeachingStateStore | ~125 | ~125 | 不变 |
| useStudentContextStore | ~225 | ~225 | 不变 |
| useConfigStore | ~280 | ~280 | 不变 |
| useEditorStore | ~135 | ~135 | 不变 |
| useUiStore | ~95 | ~40 | 缩减 |
| useUiLayoutStore | ~75 | 0 | 废弃 |
| useDrawerStore | ~75 | 0 | 废弃 |
| useRightPanelStore | ~175 | 0 | 废弃 |
| useRightToolsStore | ~195 | 0 | 废弃 |
| usePanelSessionStore | ~155 | 0 | 废弃 |
| useHintStore | ~65 | ~65 | 不变 |
| useParadigmStore | ~70 | 0 | 废弃 |
| usePageStackStore | 0 | ~50 | 新增 |
| useChatUIStore | 0 | ~40 | 新增 |
| 合计（废弃前） | ~3,125 | ~2,585 | -540 行 |

## 附录 B：页面与 Store 对应关系

| 页面 | 使用的 Store |
|------|-------------|
| BookshelfPage | usePageStackStore, useProjectStore |
| ProjectSpacePage | usePageStackStore, useProjectStore, useManuscriptStore, useChapterStore, useProgressStore |
| ConversationsPage | usePageStackStore, useSessionStore |
| ChatPage | usePageStackStore, useChatStore, useSessionStore, useTrainingStore, useDiagStore, useTeachingStateStore, useStudentContextStore, useConfigStore, useProgressStore |
| AppsPage | usePageStackStore |

## 附录 C：废弃组件依赖链

```
废弃依赖链 1（右侧栏）：
  useDrawerStore ← useRightPanelStore ← (CenterPanel, DiagnosisCard, TrainingWorkshop, ChatView, ...)
  移除顺序：先移除消费方 → 再移除 useRightPanelStore → 最后移除 useDrawerStore

废弃依赖链 2（左侧栏）：
  useUiLayoutStore ← AppShell, LeftPanel
  useUiStore ← LeftPanel, Footer
  移除顺序：AppShell → LeftPanel → useUiLayoutStore

废弃依赖链 3（三栏布局）：
  AppShell ← App.tsx
  AppShell → LeftPanel, CenterPanel, RightPanel, Footer, TabBar
  移除顺序：App.tsx 替换为 PageStackRouter → 物理删除 AppShell
```

---

*版本: v1.0 | 更新: 2026-06-25 | 下一阶段: Phase A 实施*
