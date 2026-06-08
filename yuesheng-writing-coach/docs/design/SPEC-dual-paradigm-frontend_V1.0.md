# 前端架构重构 — 双范式设计规格 V1.0

> **状态**: V1.3（上级 AI 审查反馈已采纳，5 项修订）  
> **日期**: 2026-06-06 ~ 2026-06-07  
> **项目**: 月笙写作教练 (yuesheng-writing-coach)  
> **技术栈**: Electron + React + TypeScript + Zustand + SQLite

---

## 零、已确认决策记录

### ✅ Q1：EditorView 编辑能力
**决策：可编辑纯文本 + 版本历史，分两阶段实施（上级 AI 审查采纳）**

| 决策项 | 结论 |
|--------|------|
| V1 目标 (B-01a) | **只读展示 + 行号 + 整行内联标记 + 点击交互** |
| V1.5 升级 (B-01b) | `contentEditable` 编辑能力 + 防抖保存(2s) + Ctrl+S + 版本快照 |
| 分阶段原因 | contentEditable 存在 IME 组合输入、撤销栈、粘贴清洗、光标跳转等已知坑；V1 先确保教练闭环完整 |
| 版本快照（V1.5） | 保留最近 10 个版本，AI 分析时可引用 diff |
| 内联标记实现 | 标记为覆盖层（decoration/absolute positioning），与编辑层分离 |
| 本质定位 | 小说纯文本编辑器 + AI 侧边栏插件（类 VS Code 插件模型） |

### ✅ Q2：范式 B 的 RightPanel 命运
**决策：CoachPanel 完全替换 RightPanel + 可折叠模式（上级 AI 审查采纳）**

| 决策项 | 结论 |
|--------|------|
| 范式 B 右侧面板 | CoachPanel（诊断列表 ↔ 对话 双视图） |
| **默认宽度** | **380px**（宽屏 ≥1366px） |
| **折叠宽度** | **260px**（窄屏 ≤1280px 或用户手动折叠） |
| 折叠态内容 | 仅显示诊断列表 + 迷你成长趋势；点诊断项 → 弹出浮层/抽屉显示对话 |
| 展开/折叠触发 | 用户手动按钮 + CSS 响应式断点自动切换 |
| 原 RightPanel 内容 | 能力画像 → Sidebar 底部折叠区；成长趋势 → Header 菜单或 Sidebar |
| 控制变量 | CSS 变量 `--coach-panel-w`（380px / 260px） |

### ✅ Q3：文稿数据存储
**决策：选项 A — SQLite（含版本快照表），数据模型待二期完善**

| 决策项 | 结论 |
|--------|------|
| 主存储 | SQLite `manuscripts` 表（每章一行，content 字段存全文） |
| 版本历史 | `manuscript_versions` 表（manuscript_id FK + version + content + saved_at） |
| 保留策略 | 最近 10 个版本，超出自动清理 |
| ⚠️ 待定 | 完整项目数据模型（Work/Chapter/Foreshadow/Character）作为**独立二期任务**设计，不阻塞当前 UI 重构 |

### ⚠️ 待深入：双记忆系统桥接（独立跟踪项）

用户识别出的根本性问题：对话型记忆（Session→Message）与文档型记忆（Work→Chapter→Manuscript）需要互通。

关键桥接点：
- 文字来源：聊天粘贴文字可"存入"章节；编辑器文字可作为聊天上下文
- 诊断对象：diagnosis 表加 `source_type: 'message' | 'manuscript'`
- 章节联动：新建章节时加载前一章摘要/结尾/活跃伏笔
- 伏笔追踪：foreshadows 表跨章节生命周期（planted→active→recalled→expired）
- 角色一致性：characters + character_states 跨章状态快照

**此部分需要单独出一份 SPEC（数据模型 + 业务逻辑），不在本文档范围。**

---

### ✅ Q4：Sidebar 两种范式差异
**决策：选项 B — 同一组件，默认 tab 随范式切换**

| 决策项 | 结论 |
|--------|------|
| 组件策略 | 同一套 Sidebar 组件，双 tab（作品/任务） |
| 宽度差异 | 范式 A = 240px，范式 B = 220px（CSS 变量切换） |
| 默认 tab | 范式 A → 任务 tab；范式 B → 作品 tab |
| 控制方式 | `useParadigmStore.activeParadigm` 驱动 |

### ✅ Q5：模式切换动画
**决策：选项 B 为基线 — 淡入淡出 200ms，后续用 skill 优化**

| 决策项 | 结论 |
|--------|------|
| 基线实现 | CSS `transition: opacity 200ms ease`，交叉渐变 |
| 后续优化 | 使用 impeccable / taste-skill 动效系统精调 |
| 第一版可接受 | 硬切（A）也可先上线，纯体验优化不阻塞功能 |

### ✅ Q6：Onboarding 适配
**决策：选项 A → 渐进升级到 C（上级 AI 审查采纳：触发条件修正）**

| 决策项 | 结论 |
|--------|------|
| 当前 Onboarding | 不变（三步向导：背景→目标→态度档位） |
| 范式 B 发现机制 | **行为信号触发**（满足任意 2 个即提示）：① 累计粘贴/输入 ≥5000 字 ② 完成≥3 次训练且评分≥7 ③ 使用 M-2 改写功能 ≥2 次 |
| 编辑器引导 | 独立 Onboarding B（30s 快速指引），首次切到 B 时触发 |
| 核心原则 | 新手不展示两种模式选择，避免决策负担（设计哲学 §7） |
| 修订原因 | 原"章节 badge≥3"语义模糊；改为行为信号更精准反映用户真实需求 |

### ✅ Q7：内联标记粒度
**决策：第一版 A（整行），B（精确词组）作为优化目标**

| 决策项 | 结论 |
|--------|------|
| V1 实现 | 整行 wavy underline（`line.diag` 有值即标记） |
| 升级路径 | 诊断 parser 支持 `charOffset` + `charLength` 后切换到精确标记 |
| 点击交互 | 点整行任意位置 → 打开 CoachPanel 对应 thread |
| 视觉参考 | Grammarly 早期模式（段落级→词语级演进路线） |

---

## 一、设计动机

### 1.1 现状瓶颈

当前前端采用**单内容区互斥切换**架构（`centerMode: 'chat' | 'training'`），导致：

| 症状 | 影响 |
|------|------|
| ChatView 与 TrainingWorkshop 抢同一个坑 | 用户无法"边聊边对照训练" |
| RightPanel 340px 塞满诊断/画像/成长/历史 | 信息密度过高，新功能无处安放 |
| 新手功能（成就/地图/脚手架）无展示位置 | 设计哲学 §7.3 规划的 3 个大招全部未落地 |
| 每加一个功能需改动 App.tsx 条件渲染分支 | 扩展耦合度高 |

### 1.2 核心洞察

月笙的用户行为天然分为**两类**，强行塞进同一套 UI 是根源问题：

```
用户类型 A：「我不知道该写什么 / 这段写得对不对」
  → 需要：对话引导、诊断反馈、训练推荐
  → 心理模型：和老师聊天
  → 最佳形态：聊天界面（Chat-First）

用户类型 B：「我在改这段文字 / 这个角色前后不一致」
  → 需要：文本编辑、内联标记、行级定位
  → 心理模型：在编辑器里写作
  → 最佳形态：编辑器视图（Editor-Centric）
```

### 1.3 方案选择：双范式（Dual Paradigm）

参考产品：**Scrivener**（编写模式 / 研究模式）、**Tree**（文档 / 笔记）、**Ulysses**（编辑 / 预览）

**核心思路**：不做 Tab 栏堆叠，也不做多窗口分裂，而是提供两种**完整的应用形态**，通过顶栏按钮一键切换，共享底层全部数据。

---

## 二、架构总览

### 2.1 双范式结构图

```
┌──────────────────────────────────────────────────────────────┐
│  AppHeader                                                    │
│  [🌙 月笙]  [💬 ←→ ✏️ 模式切换]          [⚙️] [👤]         │
├──────────┬─────────────────────────────┬──────────────────────┤
│          │                             │                      │
│ Sidebar  │     Main Content            │    RightPanel        │
│ (240px)  │     (flex: 1)               │    (300px)           │
│          │                             │                      │
│ ┌──────┐ │  ┌───────────────────────┐  │  ┌────────────────┐  │
│ │范式 A│─┼─▶│ TabBar                │  │  │ 诊断症候        │  │
│ │Chat  │ │  │ [对话][训练][成就]    │  │  │ 分层反馈(F-04)  │  │
│ └──────┘ │  │ [地图][工具]          │  │  │ 能力画像        │  │
│          │  ├───────────────────────┤  │  │ 成长趋势        │  │
│ ┌──────┐ │  │                       │  │  └────────────────┘  │
│ │范式 B│─┼─▶│ EditorView            │  │                      │
│ │Editor│ │  │ 行号 | 文稿(内联标记)  │  │  ┌────────────────┐  │
│ └──────┘ │  ├───────────────────────┤  │  │ CoachPanel      │  │
│          │  │ QuickBar              │  │  │ 诊断列表↔对话   │  │
│ 共享组件: │  │ [诊断][续写][灵感]    │  │  │ (仅范式B显示)   │  │
│ 作品树   │  └───────────────────────┘  │  └────────────────┘  │
│ 任务列表 │  ┌───────────────────────┐  │                      │
│          │  │ InputArea             │  │  (仅范式A显示)       │
│          │  │ 快捷指令+输入框+发送   │  │                      │
│          │  └───────────────────────┘  │                      │
└──────────┴─────────────────────────────┴──────────────────────┘

                    共享底层（不受范式切换影响）:
                    SQLite · IPC Channels · Zustand Stores · Services
```

### 2.2 组件层级

```
App.tsx
├── AppHeader          （固定，含模式切换按钮）
├── AppShell           （三栏骨架）
│   ├── AppSidebar     （双范式共享，内部有 tab 切换）
│   │   ├── WorksPanel    （作品文件树）
│   │   └── TasksPanel    （任务列表）
│   ├── MainContent     （根据 activeParadigm 渲染不同内容）
│   │   ├── 【范式 A】ParadigmChat
│   │   │   ├── TabBar         （对话/训练/成就/地图/工具）
│   │   │   ├── ChatView       （复用现有）
│   │   │   ├── TrainingWorkshop（复用现有）
│   │   │   ├── AchievementWall（新建）
│   │   │   ├── CreationMap    （新建）
│   │   │   └── ScaffoldTools  （新建）
│   │   │   └── InputArea      （快捷指令+输入框）
│   │   └── 【范式 B】ParadigmEditor
│   │       ├── Breadcrumb     （作品 > 章节 > 文稿）
│   │       ├── EditorTabs      （文稿/训练/成就/地图 - 轻量版）
│   │       ├── EditorView      （新建：行号+文本区+内联标记）
│   │       ├── CoachPanel      （新建：诊断列表↔对话 双视图）
│   │       └── QuickBar        （底部快捷操作栏）
│   └── RightPanel      （双范式共享，但内容可因范式而异）
│       ├── DiagnosisZone  （复用现有 F-04 分层反馈）
│       ├── AbilityProfile （复用现有）
│       └── GrowthTrend    （复用现有）
└── OnboardingFlow     （首次启动全屏覆盖，不变）
```

---

## 三、范式 A：对话教学（Chat-First）

### 3.1 目标用户与场景

| 属性 | 说明 |
|------|------|
| **默认入口** | 新用户首次进入自动进入此范式 |
| **核心场景** | "我不知道该怎么写"、"帮我看看这段文字的问题"、"给我出个练习" |
| **心理模型** | 和写作教练聊天 — 提问→得到反馈→练习→进步 |
| **类比产品** | ChatGPT / Notion AI / Cursor Chat |

### 3.2 布局详情

```
┌─────────────────────────────────────────────────────────┐
│ Header: [🌙月笙] [💬←→✏️]                    [⚙️] [👤] │
├────────┬──────────────────────────────┬────────────────┤
│ Sidebar│ TabBar                        │ RightPanel     │
│ (240px)│ [对话] [训练] [成就] [地图] [工具]│ (300px)        │
│        ├──────────────────────────────┤                │
│ [作品] │                              │ 📋 需要处理  (2) │
│ [任务] │  ChatView / TrainingWorkshop  │ ▎P003 对话机械  │
│        │  / AchievementWall / ...      │ ▎P009 展示不足  │
│ 📚星河  │                              │ 📋 仅供参考  (1) │
│  #第1章 │                              │ ▎P015 节奏单一  │
│  #第2章 │                              │                │
│  #第3章 │                              │ 📈 成长趋势     │
│        │                              │ ▐▐▐▐▐▐▐       │
│ 📚深海  │                              │                │
│  #序章  │                              │                │
│        ├──────────────────────────────┤                │
│ 任务:   │ [诊断] [训练] [灵感] [续写]  │                │
│ ○完成..│ ┌──────────────────────────┐ │                │
│ ○修改..│ │ 写点什么...        [发送] │ │                │
│ ✓修正..│ └──────────────────────────┘ │                │
└────────┴──────────────────────────────┴────────────────┘
```

### 3.3 Sidebar 结构（双 Tab）

**Tab 1：作品**
```
┌─────────────────┐
│ [+ 新建作品]     │
│                 │
│ ▼ 《星河之外》   │
│   # 第一章：启程  │ ③ ← 未处理症候数 badge
│   # 第二章：迷雾  │
│   # 第三章：暗流  │ ①
│   # 第四章：抉择  │
│   # 第五章：归途  │
│ ▶ 《长安夜雨》   │
│   # 开篇试写      │
│   # 人物初设讨论  │
│ ▶ 《深海回声》   │
│   # 序章：沉没    │ ⑤
│   # 世界观设定    │
└─────────────────┘
```

**Tab 2：任务**
```
┌─────────────────┐
│ 进行中           │
│                 │
│ ○ 完成「展示而非  │
│   告知」训练     │  训练工坊·剩余2题
│ ○ 修改第三章对话  │  诊断反馈·待改写
│ ○ 《深海回声》    │  自我标记·下周截止 │
│                 │
│ 已完成           │
│                 │
│ ✓ 修正第三章对话  │  诊断反馈·已完成改写
│ ✓ POV一致性检查   │  训练工坊·得分85   │
│ ✓ 《长安夜雨》    │  已完成·昨天提交   │
└─────────────────┘
```

### 3.4 TabBar 五个入口

| Tab | 图标 | 内容 | 来源 | 状态 |
|-----|:----:|------|:----:|:----:|
| **对话** | 💬 | ChatView（消息流 + 反思卡片 + 桥接卡片） | 现有 | ✅ 可复用 |
| **训练** | 🏋️ | TrainingWorkshop（推荐 + 执行 + 历史 + 角色推导） | 现有 | ✅ 可复用 |
| **成就** | 🏆 | AchievementWall（徽章网格 + 进度条 + 解锁条件） | N-01 新建 | 🔲 待开发 |
| **地图** | 🗺️ | CreationMap（里程碑时间线 + 进度百分比） | N-03 新建 | 🔲 待开发 |
| **工具** | 🔧 | ScaffoldTools（世界观生成器 / 开篇生成器 / 角色推导 / 情节测试） | N-02 新建 | 🔲 待开发 |

### 3.5 底部 InputArea（两行结构）

```
┌──────────────────────────────────────────────────────────┐
│ [诊断] [训练] [灵感] [续写]  │  │/指令│    态度: 直接    │
├──────────────────────────────────────────────────────────┤
│ [@] [+]  写点什么，或粘贴你的文字...                 [>]  │
└──────────────────────────────────────────────────────────┘
```

- **第一行**：快捷 Pill 按钮 + 态度选择器
- **第二行**：输入框（圆角胶囊形）+ 附件按钮 + 发送按钮
- `flex-shrink: 0` 保证不被挤压

### 3.6 RightPanel（与范式 B 共享）

在范式 A 中，RightPanel 显示：
1. **分层诊断区**（F-04 已实现）：需要处理 / 仅供参考
2. **能力画像**（已有）
3. **成长趋势折线图**（T-013 已实现）

---

## 四、范式 B：写作辅助（Editor-Centric）

### 4.1 目标用户与场景

| 属性 | 说明 |
|------|------|
| **触发方式** | 用户主动点击 Header 的模式切换按钮，或在范式 A 中"打开文稿" |
| **核心场景** | "我在改第三章"、"这个角色的对话前后矛盾"、"看看我写到哪了" |
| **心理模型** | 在编辑器里写作，教练在旁边随时待命 |
| **类比产品** | Scrivener 编写模式 / Tree 编辑器 / VS Code |

### 4.2 布局详情

```
┌──────────────────────────────────────────────────────────────┐
│ Header: [🌙月笙·星河之外·第1章] [💬←→✏️]     [☰作品] [🎯教练] │
├──────────┬────────────────────────────┬────────────────────────┤
│ Sidebar  │ Breadcrumb                 │ CoachPanel (380px)     │
│ 文件树   │ 星河之外 › 第1章 › 文稿    │                        │
│ (220px)  │ [文稿] [训练] [成就] [地图] │ [诊断] [对话]  ← tab切换│
│          ├────────────────────────────┤ ───────────────────── │
│ ▼星河之外 │  1 │ 林逸从星舰残骸中...    │                        │
│   第1章   │  2 │ 他拍了拍身上的碎屑...  │ 📋 P003 对话机械感     │
│   第2章   │  3 │ 没有人回答。            │ "你好，我是林逸。"     │
│   第3章   │  4 │ "~~你好，我是林逸。~~"│ ～波浪线内联标记～      │
│ ▶深海回声 │  5 │ 他叹了口气...          │ 第5行 · 等回复          │
│          │  6 │ "别动。"               │                        │
│ 当前任务  │  7 │ 林逸僵住了。           │ 📋 P009 角色动机缺失    │
│ ●P003... │  8 │ "转身，慢慢转。"       │ "我们合作吧。"她说。    │
│ ○现实锚点 │  9 │ ...                   │ 第11行 · 进行中         │
│          │                            │                        │
│          ├────────────────────────────┤ 💬 教练对话区（选中后） │
│          │ QuickBar                   │ 🌙 我注意到第5行的登场  │
│          │ [全身诊断] [选段诊断]       │ 对话——                  │
│          │ [给点灵感] [继续写]         │ "你好，我是林逸。"       │
│          │                            │ 这句话没有帮读者看见...  │
│          │                            │ ❓ 他紧张？自信？还是... │
│          │                            │ [他其实很紧张] [故作轻松] │
└──────────┴────────────────────────────┴────────────────────────┘
```

### 4.3 EditorView（核心新组件）

**4.3.1 结构**

```
EditorView
├── Breadcrumb     （面包屑导航：作品 › 章节 › 当前文件）
├── EditorTabs      （轻量 tab：文稿 / 训练 / 成就 / 地图）
├── EditorScroll    （滚动容器）
│   ├── LineNumbers （行号列，44px 宽，等宽字体）
│   └── EditorBody  （文本区域，楷体/衬线，1.85 倍行高）
└── QuickBar        （底部快捷操作栏）
```

**4.3.2 内联诊断标记**

这是范式 B 的**杀手级交互**：

```typescript
// 数据模型：manuscriptLines 中的 diag 字段关联 thread ID
interface ManuscriptLine {
  text: string;
  type: 'normal' | 'dialogue' | 'heading' | 'blank';
  diag?: string;  // 关联的 thread ID，如 'd1'
}

// 渲染：diag 标记的行显示 wavy underline
// 点击标记 → 高亮该行 + 打开 CoachPanel 对应对话
```

视觉规范：
- **普通警告**：橙色波浪下划线 (`border-bottom: 2px wavy #c47a2a`) + 浅橙背景
- **严重错误**：红色波浪下划线 (`#b85c3a`) + 浅红背景
- **激活态**：加深背景 + 外发光框 (`box-shadow: 0 0 0 2px rgba(196,122,42,0.3)`)
- **悬停态**：背景微加深

**4.3.3 文本渲染规则**

| 规则 | 值 | 说明 |
|------|:---:|------|
| 字体 | LXGW WenKai / Noto Serif SC | 中文用楷体，营造书写感 |
| 字号 | 15px | 大于 UI 字体，接近纸质阅读体验 |
| 行高 | 1.85 | 宽松行距，便于批注定位 |
| 行号宽度 | 44px | 固定宽，右对齐，等宽字体 |
| 段落间距 | 0 | `line-height` 统一控制，不用 margin |
| 正文颜色 | `#3c2f1e` | 深棕色，比纯黑柔和 |
| 标题字号 | 17px / 700 | 章节标题略大加粗 |

### 4.4 CoachPanel（替代范式 A 的 RightPanel）

**注意**：在范式 B 中，传统的 RightPanel 被 CoachPanel 替代。因为编辑器需要更宽的教练交互空间。

**4.4.1 双视图结构**

```
CoachPanel
├── CoachHeader
│   ├── 教练状态指示灯（绿=在线，脉冲动画）
│   └── Tab 切换：[诊断列表] [对话]
│
├── 视图 1：ThreadListView（诊断列表）
│   ├── ThreadCard × N
│   │   ├── 标题（如 "P003 对话机械感"）
│   │   ├── 预览文本（一句话描述问题）
│   │   ├── 元信息（行号 + 状态标签）
│   │   └── 左侧彩色边框（warning=橙 / error=红 / resolved=绿）
│   └── 点击 Card → 切换到对话视图
│
├── 视图 2：ConversationView（对话视图）
│   ├── 返回按钮（"← 返回诊断列表"）
│   ├── 当前线程标题 + 行号引用
│   ├── Messages（教练/用户气泡）
│   │   ├── CoachBubble
│   │   │   ├── 引用原文块（高亮样式，斜体）
│   │   │   ├── 教练分析正文
│   │   │   └── 提问块（带 ❓ 前缀的引导问题）
│   │   └── UserBubble（右对齐）
│   ├── QuickReplies（快捷回复 Pills）
│   └── InputRow（输入框 + 发送按钮）
│
└── 数据来源：threads[] 数组（每个元素 = 一个诊断线程）
```

**4.4.2 Thread 数据模型**

```typescript
interface DiagnosticThread {
  id: string;              // 'd1', 'd2', ...
  line: number;            // 问题所在行号
  type: 'warning' | 'error';
  status: 'awaiting' | 'in-progress' | 'resolved';
  title: string;           // 'P003 对话机械感'
  preview: string;         // 一句话预览
  snippet: string;         // 原文引用片段
  messages: ThreadMessage[];
  quickReplies: string[];  // 快捷回复选项
}

interface ThreadMessage {
  role: 'coach' | 'user';
  text: string;
  quote?: string;          // 教练引用的原文
  question?: string;       // 教练提出的引导问题
}
```

### 4.5 QuickBar（底部快捷栏）

```
┌────────────────────────────────────────────────────────────┐
│ [🔍 全身诊断]  [📋 选段诊断]  [💡 给点灵感]  [✍️ 继续写]     │
│ 态度: 直接  ·  DeepSeek V4  ·  3 症候                       │
└────────────────────────────────────────────────────────────┘
```

高度 36px，固定在编辑器底部。每个 Pill 是一个 IPC 调用触发器。

### 4.6 Sidebar（范式 B 变体）

范式 B 的 Sidebar 从"会话列表"变为**文件树导航**：

```
┌──────────────────┐
│ 作品空间    [☰]  │
│                  │
│ ▼ 星河之外       │
│   ▼ 第一章：启程 │
│     💬 诊断#12  │ ③
│     💬 诊断#11  │
│     📝 大纲梳理 │
│   第二章：异星   │
│     💬 世界观讨论│
│   第三章：归途   │
│                  │
│ ──────────────── │
│ 当前任务          │
│ ● P003 对话机械感│
│ ○ 现实锚点训练   │
└──────────────────┘
```

- 宽度 220px（比范式 A 的 240px 窄 20px，给编辑器更多空间）
- 支持折叠/展开（`collapsed` 状态 width → 0）
- 底部保留"当前任务"摘要区

---

## 五、模式切换机制

### 5.1 切换触发点

唯一入口：**AppHeader 左上角的模式切换按钮**

```
┌─────────────────────────────────────────────┐
│ [🌙] 月笙写作教练   [ 💬 chat ←→ editor ✏️ ]  │
└─────────────────────────────────────────────┘
                     ↑
               点击这里切换
```

### 5.2 切换行为

| 行为 | 说明 |
|------|------|
| **全局切换** | 整个 MainContent 区域替换为另一范式的内容 |
| **Sidebar 保留** | Sidebar 不受影响，但内部面板内容可调整 |
| **RightPanel vs CoachPanel** | 范式 A 显示 RightPanel（300px），范式 B 显示 CoachPanel（380px） |
| **状态保持** | 切换前各范式的滚动位置、输入内容、选中状态均保留 |
| **数据同步** | 两个范式读写同一份 Store / SQLite，无需手动同步 |

### 5.3 状态管理

```typescript
// 新增 store: useParadigmStore
interface ParadigmState {
  activeParadigm: 'chat' | 'editor';    // 当前活跃范式
  
  // 范式 A 状态
  chatActiveTab: 'chat' | 'train' | 'achieve' | 'map' | 'tools';
  sidebarActivePanel: 'works' | 'tasks';
  
  // 范式 B 状态
  editorActiveFile: string | null;       // 当前打开的文件路径
  editorActiveTab: 'manuscript' | 'train' | 'achieve' | 'map';
  coachView: 'threads' | 'conversation';
  activeThreadId: string | null;         // 当前打开的诊断线程
  sidebarCollapsed: boolean;
  coachCollapsed: boolean;
}
```

### 5.4 默认策略

| 场景 | 默认范式 |
|------|:--------:|
| 首次启动（无作品） | **A** — 对话教学 |
| 有作品但从未用过编辑器 | **A** — 保持习惯 |
| 用户上次停留在编辑器 | **B** — 记住偏好 |
| 从范式 A 中点击"打开文稿" | **B** — 自动切换 |
| 从范式 B 中点击"返回对话" | **A** — 自动切换 |

---

## 六、数据流与共享层

### 6.1 共享数据（两个范式共用）

| 数据 | 存储 | 两个范式如何使用 |
|------|------|----------------|
| **Sessions（会话）** | SQLite | A: Sidebar 会话列表；B: 文件树的叶子节点 |
| **Messages（消息）** | SQLite | A: ChatView 消息流；B: CoachPanel 对话视图 |
| **DiagnosisResults（诊断）** | SQLite | A: RightPanel 分层反馈；B: EditorView 内联标记 + CoachPanel 线程列表 |
| **TrainingRecords（训练）** | SQLite | A: TrainingWorkshop；B: EditorTabs 中的训练视图 |
| **AuthorProfile（画像）** | SQLite | A/B: RightPanel 能力画像（仅 A 显示或两者都显示） |
| **StudentModel（学生模型）** | SQLite | A/B: 影响回复风格和推荐策略 |
| **Manuscript（文稿）** | SQLite / 文件系统 | B: EditorView 主内容区；A: 聊天上下文引用源 |

### 6.2 范式专属数据

| 数据 | 所属范式 | 存储位置 |
|------|:--------:|----------|
| **ChatInput 草稿** | A | 内存（useParadigmStore） |
| **Chat scrollPosition** | A | 内存 |
| **Editor cursor position** | B | 内存 |
| **CoachPanel activeThreadId** | B | 内存 |
| **Editor selection range** | B | 内存 |

### 6.3 跨范式联动场景

| 操作 | 在范式 A 执行 | 范式 B 的反应 |
|------|:------------:|:------------:|
| 诊断完成，发现 3 个症候 | RightPanel 更新 | 切到 B 后 EditorView 显示内联标记 |
| 用户在对话中粘贴了一段文字 | ChatView 显示 | 切到 B 后可出现在 EditorView |
| 训练得分 ≥7，症候降级 | TrainingWorkshop 更新 | EditorView 内联标记颜色变化（resolved→绿色） |
| 用户在 B 中完成了改写 | CoachPanel 标记 resolved | 切回 A 后 RightPanel 症候数减少 |

---

## 七、设计 Tokens（视觉规范）

### 7.1 色彩系统

基于 fusion-demo 的暖色调体系（`--ys-*` 系列），与 new-paradigm-v2 的 `--*` 系列合并统一：

```css
:root {
  /* === 页面背景 === */
  --bg-page:        #F8F6F1;     /* 主背景，米白 */
  --bg-sidebar:     #F1EDE6;     /* 侧栏背景 */
  --bg-card:        #FFFFFF;     /* 卡片/面板背景 */
  --bg-editor:      #FFFefc;     /* 编辑器背景（更暖的白） */
  --bg-hover:       #EDE8DF;     /* 悬停态 */
  --bg-active:      #E8E2D6;     /* 选中态 */
  
  /* === 品牌色 === */
  --amber:          #BA7517;     /* 主品牌色（琥珀金） */
  --amber-light:    #FAEEDA;     /* 浅琥珀（背景用） */
  --amber-text:     #854F0B;     /* 琥珀文字色 */
  
  /* === 文字 === */
  --text-primary:   #2C2C2A;     /* 主文字 */
  --text-secondary: #5F5E5A;     /* 次要文字 */
  --text-tertiary:  #888780;     /* 辅助文字 */
  
  /* === 边框 === */
  --border:         rgba(0,0,0,0.08);
  --border-hover:   rgba(0,0,0,0.15);
  --border-focus:   #BA7517;     /* 聚焦边框 */
  
  /* === 语义色 === */
  --severity-high:  #D85A30;     /* 高严重度（红橙） */
  --severity-mid:   #EF9F27;     /* 中严重度（琥珀） */
  --severity-low:   #5DCAA5;     /* 低严重度（绿） */
  --success:        #5DCAA5;
  --error:          #D85A30;
  
  /* === 尺寸 === */
  --header-h:       52px;
  --sidebar-w:      240px;       /* 范式 A */
  --sidebar-w-b:    220px;       /* 范式 B */
  --rightpanel-w:   300px;       /* 范式 A RightPanel */
  --coach-w:        380px;       /* 范式 B CoachPanel */
  --tabbar-h:       40px;
  --input-h:        36px;
  
  /* === 圆角 === */
  --radius:         10px;
  --radius-sm:      6px;
  
  /* === 字体 === */
  --font-ui:         "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif;
  --font-editor:     "LXGW WenKai", "Noto Serif SC", serif;
  --font-mono:       "Cascadia Code", "Fira Code", monospace;
}
```

### 7.2 动效规范

| 动效 | 参数 | 用途 |
|------|------|------|
| **Sidebar 展开/收起** | `width 0.25s ease` | 两侧栏折叠 |
| **Tab 切换** | `opacity 0.15s` | 内容淡入淡出 |
| **CoachPanel 视图切换** | `slide + fade 0.2s` | 诊断列表 ↔ 对话 |
| **内联标记激活** | `box-shadow 0.15s` | 点击诊断标记时的高亮 |
| **Badge 脉冲** | `pulse 2s infinite` | 教练在线指示灯 |

---

## 八、新增组件清单与优先级

### Phase 1：范式 A 骨架迁移（预计 3-4 天）

| # | 组件 | 类型 | 说明 | 依赖 |
|:-:|------|:----:|------|:----:|
| A-01 | **TabBar** | 新建 | 五 tab 切换容器 | 无 |
| A-02 | **Sidebar 双 Tab** | 改造 | 现有 Sidebar 加 tab 切换（作品/任务） | 无 |
| A-03 | **InputArea 两行化** | 改造 | 现有输入区拆分为快捷 pills + 输入框 | 无 |
| A-04 | **AppShell 范式路由** | 改造 | MainContent 根据 paradigm 渲染不同子树 | A-01 |
| A-05 | **AchievementWall（壳）** | 新建 | 徽章网格布局，先空壳后填数据 | A-01 |
| A-06 | **CreationMap（壳）** | 新建 | 里程碑时间线，先空壳后填数据 | A-01 |
| A-07 | **ScaffoldTools（壳）** | 新建 | 工具卡片列表，先空壳后填数据 | A-01 |

### Phase 2：范式 B 编辑器（预计 5-7 天）

| # | 组件 | 类型 | 说明 | 依赖 |
|:-:|------|:----:|------|:----:|
| B-01 | **EditorView** | 新建 | 行号 + 文本区 + 内联诊断标记 | 无 |
| B-02 | **CoachPanel** | 新建 | 诊断列表 ↔ 对话 双视图面板 | 无 |
| B-03 | **QuickBar** | 新建 | 底部快捷操作栏 | 无 |
| B-04 | **Breadcrumb** | 新建 | 作品 › 章节 › 文件 导航 | B-01 |
| B-05 | **FileTree** | 新建 | 作品章节文件树（Sidebar 范式 B 视图） | 无 |
| B-06 | **Paradigm 切换逻辑** | 新建 | Header 按钮 + store + 路由 | A-04 |

### Phase 3：数据打通与完善（预计 3-4 天）

| # | 任务 | 说明 | 依赖 |
|:-:|------|------|:----:|
| C-01 | 内联标记 ↔ 诊断数据绑定 | EditorView 的 diag 标记从 diagnosis results 读取 | B-01 |
| C-02 | CoachPanel ↔ Chat 数据互通 | CoachPanel 对话写入 messages 表 | B-02 |
| C-03 | 成就系统后端 | 成就判定规则 + 进度计算 + SQLite 持久化 | A-05 |
| C-04 | 创作地图后端 | 里程碑定义 + 进度追踪 + SQLite 持久化 | A-06 |
| C-05 | 脚手架工具后端 | 各工具的 Prompt + IPC handler | A-07 |
| C-06 | 跨范式状态持久化 | 记住用户的范式偏好、最后打开的文件等 | B-06 |

---

## 九、决策汇总（全部 7 项已确认 + 上级 AI 审查修订）

| # | 问题 | 决策 | 关键参数 |
|:-:|------|:----:|----------|
| Q1 | EditorView 编辑能力 | **V1只读 + V1.5可编辑**（分阶段） | V1:只读+行号+内联标记; V1.5:contentEditable+防抖保存+10版本快照 |
| Q2 | 范式 B RightPanel | **CoachPanel 替换 + 可折叠** | 展开380px/折叠260px, 响应式+手动切换 |
| Q3 | 文稿数据存储 | **SQLite** | manuscripts + manuscript_versions 两张表 |
| Q4 | Sidebar 差异 | **同一组件，默认tab随范式切换** | A=240px/任务tab, B=220px/作品tab |
| Q5 | 切换动画 | **淡入淡出200ms为基线** | 后续用 impeccable/taste-skill 优化 |
| Q6 | Onboarding适配 | **不变 + 行为信号触发** | 满足2/3: 输入≥5000字 / 训练≥3次(评分≥7) / M-2改写≥2次 |
| Q7 | 内联标记粒度 | **V1整行，后续精确词组** | 依赖parser支持charOffset后升级 |

### ⚠️ DiagnosticThread 数据模型（Phase 3 前置定义，上级 AI 审查采纳）

CoachPanel 的诊断线程不挂在 sessions 下，而是独立表。Phase 3 打通前必须确定外键关系：

```typescript
/** 诊断线程 — CoachPanel 中围绕单个问题展开的对话单元 */
interface DiagnosticThread {
  id: string;

  // === 多态绑定关系（核心外键）===
  /** 来源类型：聊天消息 or 文稿行 */
  sourceType: 'message' | 'manuscript';
  /**
   * 来源引用：
   *   - message 模式: message_id (如 "msg_001")
   *   - manuscript 模式: "manuscript_id:line_number" (如 "ms_003:12")
   */
  sourceRef: string;

  // === 线程内容 ===
  syndromeId: SyndromeId;          // 关联的症候 ID
  messages: ThreadMessage[];        // 线程内对话（独立于主 chat messages 表）
  status: 'open' | 'resolved' | 'archived';

  createdAt: string;
  resolvedAt?: string;
}
```

**设计要点**：
- threads 是**独立的实体表**，不 FK 关联 sessions 或 manuscripts（避免循环依赖）
- 通过 `sourceType + sourceRef` 字符串做松耦合关联
- 范式 A 和范式 B 的线程**共存于同一张表**，CoachPanel 统一查询
- `ThreadMessage` 结构可复用现有 `Message` 的子集（role + content + timestamp）

### 独立跟踪项（不在本文档范围，需单独 SPEC）

| 跟踪项 | 说明 | 优先级 |
|--------|------|:------:|
| **双记忆系统桥接** | 对话型记忆(Session→Message)与文档型记忆(Work→Chapter→Manuscript)互通方案 | P0-下一Phase |
| **完整项目数据模型** | Work/Chapter/Foreshadowing/Character/CharacterState 的表结构设计 | P0-下一Phase |
| **章节联动机制** | 新建章节时自动加载前一章摘要/结尾/活跃伏笔/角色状态 | P0-下一Phase |
| **伏笔生命周期系统** | planted→active→recalled→expired 状态机 + AI识别+手动标记 | P1 |
| **版本diff可视化** | AI分析时展示v3 vs v5的文字对比，标注进步方向 | P1 |

---

## 十、实施路线图

### Phase 1：范式 A 骨架迁移（UI 层，预计 3-4 天）

| # | 任务 | 前置依赖 |
|:-:|------|---------|
| A-01 | TabBar 组件（五 tab 容器） | 无 |
| A-02 | Sidebar 改造（双 tab：作品/任务） | 无 |
| A-03 | InputArea 两行化（快捷pills + 输入框） | 无 |
| A-04 | AppShell 范式路由（MainContent 按 paradigm 渲染） | A-01 |
| A-05 | AchievementWall 壳组件 | A-01 |
| A-06 | CreationMap 壳组件 | A-01 |
| A-07 | ScaffoldTools 壳组件 | A-01 |

**DoD**: TabBar可切换5个tab且内容区正确渲染；Sidebar双tab切换正常；InputArea两行布局不溢出；tsc 0错误

### Phase 2：范式 B 编辑器（UI层，预计 4-5 天）

| # | 任务 | 前置依赖 | 说明 |
|:-:|------|---------|------|
| **B-01a** | **EditorView V1（只读 + 行号 + 整行内联标记 + 点击交互）** | 无 | **V1 核心任务** |
| B-02 | CoachPanel（诊断列表 ↔ 对话 双视图 + 可折叠 380/260px） | 无 | 含折叠模式 |
| B-03 | QuickBar（底部快捷操作栏） | 无 | |
| B-04 | Breadcrumb（作品 › 章节 › 文件导航） | B-01a | |
| B-05 | FileTree（Sidebar 范式B视图） | 无 | |
| B-06 | Paradigm切换逻辑（Header按钮 + store + 淡入淡出） | A-04 | |
| **B-01b** | **EditorView V1.5（contentEditable 编辑能力 + 防抖保存 + 版本快照）** | B-01a, C-01 | **V1.5 升级项** |

**DoD (V1)**: EditorView只读展示文稿+行号+内联标记点击打开CoachPanel；CoachPanel双视图切换+折叠正常；模式切换动画流畅；tsc 0错误
**DoD (V1.5)**: 在V1基础上增加可编辑能力、自动防抖保存、版本快照查看/diff

### Phase 3：数据层 + 打通（后端+前端，预计 3-4 天）

| # | 任务 | 前置依赖 |
|:-:|------|---------|
| C-01 | manuscripts + versions 表 migration + service | B-01 |
| C-02 | 内联标记 ↔ 诊断数据绑定 | B-01, C-01 |
| C-03 | CoachPanel 对话写入 messages 表 | B-02 |
| C-04 | 版本快照保存/读取/比对 IPC | C-01 |
| C-05 | 跨范式状态持久化（记住偏好/最后文件） | B-06 |

**DoD**: 编辑器文字可持久保存并恢复；版本快照可查看；切换范式后状态保持；测试覆盖核心流程

### Phase 4+（独立项目，另起文档）

- 完整项目数据模型 SPEC
- 双记忆桥接方案
- 章节联动机制
- 伏笔生命周期系统

---

## 变更记录

| 日期 | 版本 | 内容 |
|------|:----:|------|
| 2026-06-07 | V1.0 | 初版：双范式架构完整设计规格，7个开放问题 |
| 2026-06-07 | V1.1 | 新增"零、已确认决策"章节，Q1~Q3 确认；新增双记忆系统桥接警告 |
| 2026-06-07 | V1.2 | Q4~Q7 全部确认；更新决策汇总、实施路线图、独立跟踪项 |
| 2026-06-07 | **V1.3** | **上级 AI 审查采纳 5 项修订：① Q2 CoachPanel 加可折叠(380/260px) ② Q1 B-01 拆分(V1只读/V1.5可编辑) ③ DiagnosticThread 数据模型前置定义(sourceType+sourceRef 多态绑定) ④ Q6 触发条件改为行为信号(输入≥5000字/训练≥3次/M-2≥2次) ⑤ Phase 2 工期从5-7天修正为4-5天** |
