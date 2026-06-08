# SPEC: V2 工作台布局（Workspace Layout）

> 版本：V1.0 | 日期：2026-06-07 | 状态：已批准
>
> 替代：SPEC-dual-paradigm-frontend_V1.0.md 中的范式 A 布局部分

## 一、设计动机

### 1.1 问题诊断

当前 V1 双范式布局存在以下核心问题：

| # | 问题 | 影响 |
|---|------|------|
| P1 | 三栏固定布局，对话区仅 ~580px | 长文本阅读/写作体验差 |
| P2 | TabBar + 左侧 tab + 右侧面板 = 3 套导航系统 | 认知负担高，用户需判断"我在哪" |
| P3 | 右侧面板始终占用 300px，内容未必需要 | 屏幕空间浪费 23% |
| P4 | 视觉元素过多（~25 个静止元素） | 写作场景下噪音干扰沉浸感 |

### 1.2 设计哲学

> **对话是唯一主战场。一切辅助功能围绕对话展开，不抢占视觉焦点。**

参考：
- **WorkBuddy** — 左侧图标导航 + 项目树/任务混合内容区
- **SOLO** — 右侧按需抽屉（"打开工具"模式）

### 1.3 与 V1 双范式的关系

本规格**替代** V1 的「范式 A」布局定义。双范式的**概念保留**（Phase 2 编辑器模式仍通过 Header 切换），但范式 A 的具体布局从「三栏固定」改为「工作台模式」。

---

## 二、架构总览

### 2.1 布局结构

```
┌──────────────────────────────────────────────────────────────────┐
│  [月] 月笙写作教练        💬↔✏️    [🔍] [📋] [📈] [⚙]      │  Header (52px)
├──────┬─────────────────────────────────────┬────────────────────┤
│ 导航  │                                     │                    │
│ 图标  │        对话主战场（永远不变）        │    右侧抽屉        │
│ 栏   │                                     │   (默认隐藏)       │
│ ───  │  ┌───────────────────────────────┐  │   宽度: 0 → 360px  │
│      │  │                               │  │                    │
│ 内容  │  │         消息流                 │  │  点击 Header 图标  │
│ 区域  │  │         （可滚动）             │  │  触发滑出          │
│      │  │                               │  │                    │
│ 混合  │  ├───────────────────────────────┤  │  ┌──────────────┐ │
│ 滚动  │  │ pills | 输入框 | [>]          │  │  │ 诊断/成长/   │ │
│      │  └───────────────────────────────┘  │  │  能力/工具    │ │
│      │                                     │  └──────────────┘ │
└──────┴─────────────────────────────────────┴────────────────────┘
  ~220px              flex:1                      0→360px
```

### 2.2 三区域职责

| 区域 | 职责 | 宽度 | 可见性 |
|------|------|------|--------|
| **A. 左侧栏** | 导航 + 工作状态总览 | ~220px | 始终可见 |
| **B. 中间区** | 对话主战场 | flex:1 | 始终可见 |
| **C. 右侧抽屉** | 辅助信息面板（诊断/成长/能力/工具） | 0→360px | 按需显示 |

---

## 三、区域详细规格

### 3.1 A 区：左侧栏（AppSidebar V2）

#### 3.1.1 整体结构

分为上下两层：

```
┌──────────────────┐
│  导航图标栏 (48px) │  ← 固定高度，不滚动
├──────────────────┤
│                  │
│  混合内容区       │  ← flex:1，可滚动
│  (项目树+任务)     │
│                  │
│                  │
└──────────────────┘
```

#### 3.1.2 上层：导航图标栏

4 个精简图标按钮，垂直排列或水平排列在顶部：

| 序号 | 图标 | 功能 | 交互 |
|:----:|:----:|------|------|
| 1 | `+` | 新建会话 | amber 主色强调 |
| 2 | `🔍` | 全局搜索 | 输入框浮层 |
| 3 | `🎯` | 训练工坊 | 点击 → 中间区嵌入训练视图 |
| 4 | `📋` | 任务视图 | 点击 → 内容区滚动到任务分组 |

> **移除的按钮：** 设置（移到 Header）、折叠按钮（保留但优化位置）

#### 3.1.3 下层：混合内容区

不使用 tab 切换。项目树和任务列表在同一滚动区域内，用**分组标题**分隔：

```
┌─────────────────────────────┐
│ 📂 我的作品                   │ ← SectionHeader (不可点击)
│ ▼ 《星河之外》                │ ← WorkTreeNode (可展开/折叠)
│   # 第一章：启程          [3] │ ← ChapterNode (badge=待处理数)
│   # 第二章：迷雾              │
│   # 第三章：暗流           [1] │
│   # 第四章：抉择              │
│   # 第五章：归途              │
│ ▶ 《长安夜雨》                │
│   # 开篇试写                  │
│                              │
│ 📋 待处理 (3)                │ ← SectionHeader (带计数)
│ ● 完成展示而非告知训练         │ ← TaskCard (amber dot)
│   训练工坊 · 剩余 2 题         │
│ ● 修改第三章对话节奏           │ ← TaskCard
│   诊断反馈 · 待改写            │
│                              │
│ ✅ 已完成 (3)                │ ← SectionHeader
│ ● POV一致性检查训练            │ ← TaskCard (green dot)
│   训练工坊 · 得分 85           │
└─────────────────────────────┘
```

**数据模型（新增类型）：**

```typescript
/** 分组标题 */
interface SectionHeader {
  type: 'header';
  label: string;       // "我的作品" / "待处理" / "已完成"
  icon: string;        // emoji
  count?: number;      // 可选计数
}

/** 作品树节点 */
interface WorkTreeNode {
  type: 'work';
  id: string;
  title: string;
  expanded?: boolean;
  children: ChapterNode[];
}

/** 章节节点 */
interface ChapterNode {
  type: 'chapter';
  id: string;
  title: string;
  badge?: number;      // 未处理数
}

/** 任务卡片 */
interface TaskCard {
  type: 'task';
  id: string;
  title: string;
  source: string;      // "训练工坊" / "诊断反馈" / "自我标记"
  meta: string;        // "剩余 2 题" / "待改写"
  done: boolean;
}

/** 混合内容区项 = 上述任一类型的联合 */
type SidebarItem = SectionHeader | WorkTreeNode | ChapterNode | TaskCard;
```

#### 3.1.4 折叠态

- 折叠时宽度 → 48px（仅显示图标导航）
- 混合内容区隐藏
- 图标导航变为垂直排列的单列图标

### 3.2 B 区：中间区（Chat Workspace）

#### 3.2.1 核心变更：移除 TabBar

**TabBar 组件保留代码但不渲染。** 中间区永远是对话界面。

```
┌──────────────────────────────────────────┐
│                                          │
│          消息流 (MessageList)             │  flex:1, overflow-y:auto
│                                          │
│          （对话、诊断卡片、               │
│           训练嵌入视图）                   │
│                                          │
├──────────────────────────────────────────┤
│ [🤔提问] [📎片段] [🔍诊断] [💡灵感] [✏️改写] │  快捷 pills 行
│ [@] [________________发送_____] [>]     │  输入行
└──────────────────────────────────────────┘
```

#### 3.2.2 训练入口方式

不再切换到独立 tab，而是**在对话区内嵌入**：

1. 用户点击左侧 `🎯` 或对话中的训练推荐卡片
2. 训练组件（ActiveTrainingView）以**全屏覆盖层**形式出现在消息区上方
3. 训练完成后自动收起，回到对话
4. 返回按钮始终可见（右上角 `← 返回对话`）

这种方式保持"训练是对话的自然延伸"的心智模型。

#### 3.2.3 诊断信息呈现

不在右侧面板被动等待查看，而是**主动推送到对话中**：

- 诊断完成时，在对话流中插入一张**诊断摘要卡片**
- 卡片包含：发现 N 个问题 · [查看详情]
- 点击 [查看详情] → 触发右侧抽屉打开诊断面板

### 3.3 C 区：右侧抽屉（RightDrawer）

#### 3.3.1 触发方式

Header 右侧放置 4 个图标按钮：

| 图标 | 面板内容 | 默认宽度 |
|------|---------|:--------:|
| 🔍 或 🩺 | 诊断面板（症候列表） | 320px |
| 📈 | 成长趋势（图表） | 280px |
| 🧑 | 能力画像 | 300px |
| 🔧 | 工具箱（世界观生成器等） | 360px |

#### 3.3.2 交互行为

```
默认状态:     [中间区 full width]                          抽屉 width=0
                                              ↓ 点击 Header 图标
展开状态:     [中间区 --------] [=== 抽屉面板 === ×]        抽屉 width=320~360px
                                              ↓ 点击 × 或 图标 或 面板外
收回状态:     [中间区 full width]                          抽屉 width=0
```

**动画规格：**
- 方向：从右向左滑入
- 时长：280ms ease-out (cubic-bezier(0.16, 1, 0.3, 1))
- 遮罩：抽屉打开时，中间区加半透明遮罩（opacity 0.05），点击遮罩关闭抽屉
- 同一时间只允许一个面板打开

#### 3.3.3 抽屉内部结构

每个面板独立组件，共享相同的容器框架：

```
┌─────────────────────┐
│ [× 关闭]  面板标题   │  ← DrawerHeader (固定)
├─────────────────────┤
│                     │
│   面板特定内容       │  ← DrawerBody (flex:1, overflow-y:auto)
│                     │
│                     │
└─────────────────────┘
```

---

## 四、状态管理

### 4.1 新增 Store：drawer.store.ts

```typescript
interface DrawerState {
  /** 当前打开的面板 ID，null 表示关闭 */
  activePanel: 'diagnosis' | 'growth' | 'profile' | 'tools' | null;
  /** 是否正在动画中 */
  isAnimating: boolean;
}

interface DrawerActions {
  openPanel: (panel: NonNullable<DrawerState['activePanel']>) => void;
  closePanel: () => void;
  togglePanel: (panel: NonNullable<DrawerState['activePanel']>) => void;
}
```

### 4.2 paradigm.store.ts 变更

- **移除** `activeTab`（TabBar 不再存在）
- **移除** `sidebarTab`（左侧不再有 tab 切换）
- **保留** `activeParadigm`（Phase 2 用）
- **保留** `setView()` 用于 config 页面切换

### 4.3 状态总数对比

| | V1 | V2 |
|---|----|----|
| paradigm store | activeTab + sidebarTab + activeParadigm = **3** | activeParadigm = **1** |
| drawer store | 无 | activePanel = **1** |
| **总计** | **3** | **2** |

---

## 五、组件清单与文件规划

### 5.1 需修改的现有组件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `App.tsx` | **重大修改** | 移除 TabBar 渲染；引入 RightDrawer；调整布局结构 |
| `AppShell.tsx` | 修改 | 适配新三区域布局 |
| `AppSidebar.tsx` | **重写** | 导航图标栏 + 混合内容区 |
| `AppHeader.tsx` | 修改 | 右侧增加抽屉触发图标组 |
| `TabBar.tsx` | 保留不删 | 代码保留但不渲染，Phase 2 可能复用 |
| `RightPanel.tsx` | **替换** | 改为 RightDrawer 容器 |

### 5.2 新增组件

| 文件 | 职责 |
|------|------|
| `components/layout/RightDrawer.tsx` | 抽屉容器（动画 + 遮罩 + 面板插槽） |
| `components/layout/SectionHeader.tsx` | 左侧栏分组标题 |
| `stores/drawer.store.ts` | 抽屉状态管理 |
| `components/drawer/DiagnosisPanel.tsx` | 诊断面板内容 |
| `components/drawer/GrowthPanel.tsx` | 成长趋势面板内容 |
| `components/drawer/ProfilePanel.tsx` | 能力画像面板内容 |
| `components/drawer/ToolsPanel.tsx` | 工具箱面板内容 |

### 5.3 组件依赖关系

```
App.tsx
 ├── AppHeader (mode switch + drawer triggers)
 ├── AppSidebar V2 (icon nav + mixed content)
 ├── ChatView (always visible)
 │   ├── MessageList
 │   ├── ActiveTrainingView (overlay mode)
 │   └── MessageInput
 └── RightDrawer (conditional)
     ├── DiagnosisPanel
     ├── GrowthPanel
     ├── ProfilePanel
     └── ToolsPanel
```

---

## 六、实施路线图

### Phase 1：骨架搭建（本次实施）

| 任务 | 内容 | DoD |
|:----:|------|-----|
| A-01 | 创建 drawer.store.ts | openPanel/closePanel/togglePanel 可用 |
| A-02 | 重写 AppSidebar（图标导航 + 混合内容区） | 4 图标 + Mock 数据渲染正确 |
| A-03 | 创建 RightDrawer 组件（空壳 + 动画） | 从右滑入/滑出动画流畅 |
| A-04 | AppHeader 加抽屉触发图标 | 4 个图标点击能开关抽屉 |
| A-05 | App.tsx 布局重构（移除 TabBar，集成抽屉） | 对话全屏，抽屉按需出现 |
| A-06 | 训练改为 overlay 模式 | 点击训练入口后覆盖消息区 |

### Phase 2：面板内容填充

| 任务 | 内容 |
|:----:|------|
| B-01 | DiagnosisPanel（症候卡片列表） |
| B-02 | GrowthPanel（成长趋势迷你图表） |
| B-03 | ProfilePanel（能力雷达图） |
| B-04 | ToolsPanel（工具网格） |

### Phase 3：数据接入

| 任务 | content |
|:----:|---------|
| C-01 | 左侧栏接真实 manuscripts 数据 |
| C-02 | 任务列表接真实 training/diagnosis 状态 |
| C-03 | 抽屉面板接真实数据源 |

---

## 七、设计决策记录 (ADR)

| # | 决策 | 理由 | 替代方案 |
|---|------|------|---------|
| ADR-001 | 移除 TabBar | 对话是唯一主战场，减少导航系统数量 | 保留 TabBar 但精简到 2-3 个 |
| ADR-002 | 右侧用滑出抽屉 | 节约屏幕空间，按需加载 | 始终显示窄条(40px) + hover 展开 |
| ADR-003 | 左侧混合内容区（无 tab） | 一屏看到全部工作状态 | 保留作品/任务 tab 切换 |
| ADR-004 | 训练用 overlay 模式 | 训练是对话的自然延伸 | 独立页面/独立 tab |
| ADR-005 | 诊断结果推送对话流 + 抽屉详情 | 主动通知 vs 被动等待 | 仅在右侧面板展示 |

---

## 八、变更记录

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|---------|------|
| V1.0 | 2026-06-07 | 初版，基于 WorkBuddy + SOLO 参考设计 | AI |
