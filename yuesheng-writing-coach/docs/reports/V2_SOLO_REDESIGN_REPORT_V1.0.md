# V2 SOLO 模式 — 系统改造总报告

> **文档版本**: V1.0
> **创建日期**: 2026-06-07
> **状态**: 待评审
> **关联文档**: [项目缺陷报告](../reports/V2_PROJECT_DEFECTS_REPORT_V1.0.md) | [V2 工作台原型](../../prototype-v2-workspace.html)

---

## 一、执行摘要

### 1.1 改造背景

月笙写作教练当前 UI 采用「AppHeader + 三栏」布局，与产品核心定位——**以对话为中心的 AI 写作教练**——存在根本性矛盾。用户的核心价值链路是：

```
用户作品 → 发现问题 → 解释原因 → 制定训练 → 执行训练 → 验证进步 → 形成能力
```

但当前界面将**对话区压缩到约 45% 屏幕宽度**，Header 占据 40px 顶部空间，左右侧栏混合了过多不同层级的导航元素，导致用户注意力被分散。

### 1.2 改造方案概述

基于 `prototype-v2-workspace.html`（3144 行高保真交互原型），提出 **SOLO 模式** 重构方案：

| 维度 | 当前（旧） | 目标（新） |
|------|-----------|-----------|
| 布局模型 | AppHeader(40px) + 三栏 | **无 Header 纯三栏沉浸式** |
| 对话区占比 | ~45% 屏幕 | **≥60% 屏幕** |
| 左侧栏职责 | 导航+内容+任务混合堆叠 | **项目视图 / 对话历史双视图切换** |
| 右侧面板 | 工具列表选择式 | **图标直接切换 + 多标签页内容查看** |
| 全局上下文感知 | 无 | **Status Bar 实时显示当前作品/章节/字数** |
| 对话历史管理 | 无法切换/回顾 | **按时间分组的完整对话列表** |

### 1.3 核心结论

| 维度 | 结论 |
|------|------|
| **改造必要性** | **高** — 当前 UI 与产品定位矛盾，用户体验受损 |
| **改造可行性** | **可行** — Store 防腐层完善，37 个 IPC 通道可用，UI 与底层解耦 |
| **推荐策略** | **有条件采纳原型 + 分四阶段迁移** |
| **预估工作量** | **29 人天**（Phase 0: 7d + Phase 1: 10d + Phase 2: 12d） |
| **最大风险** | manuscripts/chapters 数据表缺失、App.tsx 455 行瓶颈需先拆分 |

---

## 二、现状分析

### 2.1 技术架构全景

```
┌─────────────────────────────────────────────────────────┐
│                    Electron 主进程                         │
│  ┌────────────┐  ┌──────────┐  ┌────────────────────┐   │
│  │  DB 层      │  │  服务层    │  │  IPC Handler 层     │   │
│  │  8张表      │  │  ~30个服务 │  │  37个通道           │   │
│  │  10个迁移    │  │  4个空壳   │  │  27 invoke + 4 event │   │
│  └────────────┘  └──────────┘  └────────────────────┘   │
├─────────────────────────────────────────────────────────┤
│                   渲染进程 (React)                         │
│  ┌────────────┐  ┌──────────┐  ┌────────────────────┐   │
│  │  Store 层   │  │  组件层   │  │  布局组件            │   │
│  │  9个Store   │  │  ~38组件  │  │  AppShell→Header     │   │
│  │  Zustand    │  │          │  │  →Sidebar→RightPanel │   │
│  └────────────┘  └──────────┘  └────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 2.2 关键数据资产盘点

| 资产类别 | 数量 | 成熟度 | 备注 |
|---------|------|--------|------|
| IPC 通道 | **37 个** (27 invoke + 4 event) | ★★★★☆ | 核心业务通道完整可用 |
| Zustand Store | **9 个** | ★★★★☆ | 防腐层完善，UI 解耦良好 |
| 数据库表 | **8 张** (10 个迁移文件) | ★★★☆☆ | **缺 manuscripts / chapters 表** |
| React 组件 | **~38 个** | ★★★☆☆ | App.tsx 过重(455行), Sidebar 828行 |
| Prompt 模板 | **10 个** | ★★★★★ | 版本化管理，结构清晰 |
| 症候定义 | **20 个** (P001-P010 + H/I/E 系列) | ★★★★★ | 完整覆盖 |
| 教学阶段 | **5 大阶段 / 14 子阶段** | ★★★★☆ | 状态机完整 |
| JSON 配置文件 | **20 个** | ★★★★☆ | 配置外置规范基本遵循 |

### 2.3 当前 UI 的六大核心问题

#### P0：布局哲学矛盾

当前 `AppShell.tsx` 强制包含 40px 高的 `AppHeader.tsx`，而产品的设计哲学要求**对话是唯一主视区**——任何非对话的顶部横条都在抢占用户对教练的注意力。

**具体影响：**
- Header 在 1366px 分辨率下占用对话区 ~3% 的垂直空间
- Header 承载的功能（标题栏按钮）可以分散到各区域内部
- 用户心理感受：「这是一个工具软件」而非「这是我的教练办公室」

#### P1：左侧栏认知过载

当前左侧栏在 240px 宽度内塞入了 **6 个功能模块**：

| # | 模块 | 服务对象 | 使用频率 |
|---|------|---------|---------|
| 1 | 范式切换（SOLO/IDE） | 产品模式控制 | 低频 |
| 2 | 任务筛选 | 任务管理 | 低频 |
| 3 | 导航图标（搜索/训练/任务） | 视图切换 | 元操作 |
| 4 | 新建按钮 | 内容创建 | 中频 |
| 5 | 作品树（作品+章节） | 内容定位 | 中高频 |
| 6 | 任务卡片列表 | 进度追踪 | 中频 |

这 6 个模块服务于 **3 种不同的用户心智状态**（操控产品 / 找东西 / 追踪进度），但混在同一个狭小空间内。

#### P2：对话区被过度压缩

三栏布局中，中间对话区的实际视觉权重不足：
- 左侧栏固定 240px (~17.6% @1366px)
- 右侧面板展开时 380-420px (~28-31%)
- Header 占用 40px 垂直空间
- **对话区实际仅占 ~45% 屏幕面积**

而对话是产品的**唯一核心价值交付点**。

#### P3：无全局上下文感知

用户在长时间对话后容易迷失：
- 「我现在在聊哪个作品的哪一章？」— 需要自己去左侧栏找
- 「教练刚才引用的是哪段文字？」— 没有便捷的内容锚点
- 「我之前聊到哪了？」— 无对话历史快速入口

#### P4：右侧面板交互效率低

当前右侧面板需要「先选工具分类 → 再看工具列表 → 再打开」，三步才能到达目标面板。而用户的多数操作是重复访问同一面板（如训练工坊）。

#### P5：对话历史不可管理

- 无法查看历史对话列表
- 无法搜索过去的对话内容
- 无法给对话命名或归档
- 长期使用后大量对话内容丢失风险高

---

## 三、新 UI 设计理念解读

### 3.1 SOLO 模式的四层含义

| 层面 | 含义 | 在原型中的体现 |
|------|------|---------------|
| **布局层面** | 无 Header 的沉浸式三栏布局 | CSS 注释反复强调「绝对没有 Header / Top Bar 层」 |
| **交互层面** | 对话是唯一主视区，AI Panel 占据最大空间 | `.solo-chat-area` 使用 `flex: 1` 自适应占据最大空间 |
| **心理层面** | 用户与教练的一对一私密对话体验 | 教练头像使用品牌字「月」而非通用图标 |
| **哲学层面** | 「教可教的认知能力，而非才华」（项目设计哲学） | 训练工坊、诊断面板围绕可量化的写作能力构建 |

### 3.2 与传统工具的本质区别

| 维度 | 传统 IDE (VS Code) | 传统写作工具 (Scrivener) | 月笙 SOLO 模式 |
|------|-------------------|------------------------|----------------|
| **中心区域** | 代码编辑器 | 文档编辑区 | **AI 对话区** |
| **左侧栏** | 文件浏览器 | 手稿/研究资料 | **作品树 + 对话历史** |
| **右侧栏** | 源代码控制/扩展 | 笔记/属性 | **诊断/训练/成长工具** |
| **顶部** | Menu Bar + Tabs | Toolbar | **无（内嵌到各区域）** |
| **核心隐喻** | 工作台 (Workbench) | 粘贴板 (Binder) | **教练办公室 (Coach Office)** |

**最本质的区别：传统工具以「文档」为中心，月笙以「对话」为中心。文档变成了对话的上下文，而非操作的直接对象。**

### 3.3 信息架构决策理由

#### 为什么左侧栏放「项目 / 对话」双视图？

这两套视图回答了用户两个核心问题：
- **「我写了什么？」** → 项目视图（作品树 + 任务）
- **「我们聊了什么？」** → 对话视图（按时间分组的历史列表）

将它们放在同一侧栏通过 Tab 切换，而非分成两个独立面板，是为了**保持认知负荷的最小化**——用户永远只需要关注一个导航维度。

#### 为什么右侧是工具面板？

采用「图标条 + 可展开面板」的双态设计：
1. **渐进式披露 (Progressive Disclosure)**：工具默认收起为 48px 图标条，不占用核心对话空间
2. **上下文感知**：点击章节后自动展开内容查看器，实现「选中即打开」的流畅体验
3. **多标签页系统**：内容查看器内部支持多文件标签，允许同时打开多个章节对照阅读

### 3.4 「对话为中心」在每个细节中的体现

1. **输入区的视觉权重**：输入框使用 16px 大圆角 + max-width:800px 居中，成为整个页面最「友好」的交互元素
2. **消息模型的教练身份**：每条消息都有品牌渐变色头像 + 角色标签，强化「这是教练在说话」
3. **Chat Header 内嵌**：教练身份徽章放在对话区顶部，而非全局 header，强化「这是我们的对话空间」
4. **Status Bar 的上下文感知**：底部始终显示当前作品名和章节名，让用户知道「我们在聊什么」
5. **发送按钮微交互**：hover 时 scale(1.04) 放大，active 时 scale(0.96) 回弹，给予明确操作反馈

---

## 四、设计系统提取（可直接复用于生产）

### 4.1 色板 — 金棕暖灰体系

```css
/* 品牌色梯度 */
--accent:          #C4883A;    /* 主品牌色 - 金棕 */
--accent-hover:    #B07830;    /* 悬停态 */
--accent-light:    #D4A56A;    /* 浅金棕 - 渐变末端 */
--accent-subtle:   rgba(196,136,58,0.10);  /* 微妙背景 */
--accent-faint:    rgba(196,136,58,0.06);   /* 极淡背景 */
--text-on-accent:  #FFFFFF;     /* 品牌色上的文字 */

/* 语义色 */
--success: #4A7C59;    /* 成功/完成 - 森林绿 */
--warning: #C4883A;    /* 警告/进行中 */
--error:   #B54D4D;    /* 错误 */

/* 中性色梯度 - 暖灰系（非冷科技蓝灰）*/
--bg-primary:   #FAF8F5;    /* 最浅 - 页面底色，暖白 */
--bg-secondary: #F3EDE4;    /* 次要 - 侧栏/图标条，暖米 */
--bg-card:      #FFFFFF;    /* 卡片 - 纯白 */
--bg-hover:     rgba(180,140,90,0.08);  /* 悬停 */
--bg-active:    rgba(180,120,60,0.12);  /* 激活 */

--border:       #E8E0D4;    /* 主边框 - 暖灰棕 */
--border-light: #EDE7DD;    /* 轻边框 */
--border-focus: var(--accent);

--text-primary:   #2C2416;  /* 主文字 - 深褐黑（非纯黑，减少刺眼）*/
--text-secondary: #5C4D3A;  /* 次要 */
--text-tertiary:  #8A7B68;  /* 辅助 */
```

**色彩哲学**：整个色板建立在「暖纸质」美学之上。`--text-primary` 使用深褐而非纯黑，减少屏幕阅读刺眼感，呼应「写作」主题的纸笔联想。

### 4.2 字体系统

| 用途 | 字族 | 基准字号 | 行高 |
|------|------|---------|------|
| 展示（品牌触点） | Noto Serif SC / 宋体 | - | - |
| 界面正文 | system-ui / Noto Sans SC | **14px** | 1.5 |
| 对话内容 | 同上 | 14px | **1.75**（更舒适阅读）|
| 文稿内容 | 同上 | 14px | **1.8**（最高舒适度）|
| 辅助标注 | 同上 | 11-12px | 1.3-1.4 |
| 徽章数字 | 同上 | 10px | 1.4 |

字重阶梯：400(normal) / 500(medium) / 600(semibold) / 700(bold)

### 4.3 间距体系

基于 **4px 基准网格**（含半步值 5/7/9px 用于微调平衡）：

| 值 | 典型用途 |
|----|---------|
| 2-4px | 极紧密：图标间距、内联元素间隙 |
| 5-6px | 小间隙：按钮内 icon-text gap |
| 8px | 标准中：容器 padding-x、statusbar gap |
| 10px | 标准大：view-tab padding、work-item padding |
| 12-14px | 区块级：chapter-item padding、panel-header padding |
| 16-20px | 更大：chat-messages padding、input-area padding |
| 28-40px | 容器级/空状态：panel-placeholder、conv-empty |

### 4.4 圆角 / 阴影 / 动效 / Z-index

| 系统 | 参数 | 使用场景 |
|------|------|---------|
| **圆角 4档** | 6px(sm) / 10px(md) / 16px(lg) / 9999px(full) | 按钮 / 头像 / 输入框(最亲和) / 标签徽章 |
| **阴影 3档** | sm / md / lg（均为暖色调 rgba） | 列表悬浮 / fixed浮动按钮 / overlay遮罩 |
| **动效时长** | 150ms(fast) / 200ms(normal) / 250ms(slow) | hover反馈 / 面板展开 / 侧栏折叠 |
| **缓动曲线** | ease-out / spring(cubic-bezier(0.4,0,0.2,1)) | 减速反馈 / 弹性物理 |
| **Z-index 4级** | 40(overlay) / 50(sidebar) / 55(tool-panel) / 200(dropdown) | 语义化层级 |

### 4.5 响应式断点

| 断点 | 侧栏宽 | 工具面板宽 | 布局策略 |
|------|--------|-----------|---------|
| Desktop (>1024px) | 240px | 380px | 完整三栏 |
| Tablet (≤1024px) | 200px (-40px) | 320px (-60px) | 压缩三栏 |
| Mobile (≤768px) | fixed drawer | fixed overlay | 单栏 + 抽屉覆盖 |

> 注：移动端适配在本轮改造中优先级低，桌面端为主。

---

## 五、新旧系统组件映射矩阵

| 新 UI 组件 | 现有对应组件 | 匹配度 | 所需改动类型 |
|-----------|-------------|--------|------------|
| **对话主区域 (ChatArea)** | ChatPanel + chat store | ★★★★☆ | 移除 Header 压缩，扩大 flex 权重 |
| **SOLO/IDE 模式切换器** | 无 | ★★☆☆☆ | **全新组件**，IDE 侧延后实现 |
| **侧栏-项目视图** | AppSidebar（部分） | ★★★☆☆ | 重构：提取作品树 + 任务列表为独立子组件 |
| **侧栏-对话视图** | **不存在** | ★☆☆☆☆ | **全新开发**，需扩展 sessions schema |
| **右侧工具面板 (ToolPanel)** | RightDrawer | ★★★★☆ | 改造双态机制（图标条↔展开面板） |
| **内容查看器 (ContentViewer)** | **不存在** | ★☆☆☆☆ | **全新开发**，依赖 manuscripts 表 → **Phase 3** |
| **训练工坊面板** | TrainingPanel（占位） | ★★★☆☆ | 补充真实数据和交互逻辑 |
| **诊断面板** | DiagnosisPanel（占位） | ★★★☆☆ | 对接 diagnosis_results 表 |
| **成长记录面板** | **不存在** | ★★☆☆☆ | **需先设计能力指标数据模型** |
| **能力画像面板** | **不存在** | ★★☆☆☆ | 同上 |
| **Status Bar** | **不存在** | ☆☆☆☆☆ | **新建轻量组件**，~100 行 |
| **多文件标签页** | **不存在** | ☆☆☆☆☆ | **依赖 ContentViewer** → **Phase 3** |

---

## 六、数据流对接方案

### 6.1 必须新增的数据实体

#### manuscripts 表（作品）

```sql
-- 文件位置: src/main/db/009_manuscripts.sqlite
CREATE TABLE IF NOT EXISTS manuscripts (
  id TEXT PRIMARY KEY,              -- UUID
  title TEXT NOT NULL,               -- 作品标题
  description TEXT DEFAULT '',       -- 作品简介
  genre TEXT DEFAULT '',             -- 类型/题材
  status TEXT DEFAULT 'active' CHECK(status IN ('active','archived')),
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
  sort_order INTEGER DEFAULT 0       -- 排序权重
);
```

#### chapters 表（章节）

```sql
-- 文件位置: src/main/db/009_manuscripts.sqlite（同一迁移文件）
CREATE TABLE IF NOT EXISTS chapters (
  id TEXT PRIMARY KEY,              -- UUID
  manuscript_id TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
  title TEXT NOT NULL,               -- 章节标题
  content TEXT DEFAULT '',           -- 正文内容（纯文本或 Markdown）
  word_count INTEGER DEFAULT 0,      -- 字数（缓存）
  sort_order INTEGER DEFAULT 0,
  status TEXT DEFAULT 'draft' CHECK(status IN ('draft','revising','complete')),
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);
CREATE INDEX IF NOT EXISTS idx_chapters_manuscript ON chapters(manuscript_id);
```

#### sessions 表扩展

```sql
-- 文件位置: src/main/db/010_sessions_extend.sql
ALTER TABLE sessions ADD COLUMN title TEXT;              -- 对话标题（自动生成或用户编辑）
ALTER TABLE sessions ADD COLUMN preview TEXT;             -- 最后一条消息预览（截取前 80 字）
ALTER TABLE sessions ADD COLUMN manuscript_id TEXT REFERENCES manuscripts(id);
ALTER TABLE sessions ADD COLUMN chapter_id TEXT REFERENCES chapters(id);
```

### 6.2 必须新增的 IPC 通道

| Channel 名 | 方向 | 参数 | 返回值 | 用途 |
|------------|------|------|--------|------|
| `manuscript:list` | render→main | 无 | `Manuscript[]` | 获取作品列表 |
| `manuscript:get` | render→main | `{id}` | `Manuscript \| null` | 获取单个作品详情 |
| `manuscript:create` | render→main | `{title, description?}` | `Manuscript` | 创建新作品 |
| `manuscript:update` | render→main | `{id, title?, ...}` | `Manuscript` | 更新作品信息 |
| `chapter:list` | render→main | `{manuscriptId}` | `Chapter[]` | 获取某作品的所有章节 |
| `chapter:get` | render→main | `{id}` | `Chapter \| null` | 获取单个章节（含内容）|
| `chapter:updateContent` | render→main | `{id, content}` | `{wordCount}` | 更新章节正文 |
| `session:listWithMeta` | render→main | `{limit?, offset?}` | `SessionMeta[]` | 含 title/preview 的会话列表 |
| `session:updateTitle` | render→main | `{id, title}` | `boolean` | 更新对话标题 |

### 6.3 必须新增/重构的 Store

| Store 名 | 变更类型 | 核心状态 | 关键 Action |
|----------|---------|---------|------------|
| **manuscriptStore** | **全新** | `currentManuscript`, `manuscripts[]`, `loading` | `fetchList()`, `select()`, `create()` |
| **chapterStore** | **全新** | `chapters[]`, `currentChapter`, `openFiles[]`, `contentCache{}` | `fetchByWork()`, `select()`, `loadContent()`, `openTab()`, `closeTab()` |
| **conversationStore** | **重构** | 扩展 sessionStore | `conversations[]`, `groupByTime()`, `search()`, `switchTo()` |
| **uiLayoutStore** | **全新** | `sidebarCollapsed`, `sidebarView`(projects\|conversations), `toolPanelState`(collapsed\|expanded\|viewId), `globalMode`(solo\|ide) | `toggleSidebar()`, `switchView()`, `openPanel()`, `switchMode()` |
| **appStore** | **拆分** | 从 App.tsx 抽取全局状态 | （拆分后分散到各子 Store）|

---

## 七、改造执行计划（四阶段）

### Phase 0：基础设施准备（预估 3-4 人天）⭐ 先决条件

**目标：为 UI 重构扫清所有底层障碍**

| # | 任务 | 产出物 | 依赖 | 验收标准 |
|---|------|--------|------|---------|
| 0.1 | **拆分 App.tsx**（455→<150 行） | AppShell / AppContent / AppProviders | 无 | App.tsx 仅做 Provider 嵌套 + 路由入口 |
| 0.2 | **新建 manuscripts + chapters 迁移** | `009_manuscripts.sqlite` | 无 | migration 可通过 `npm run migrate` 执行成功 |
| 0.3 | **扩展 sessions schema** | `010_sessions_extend.sql` | 无 | ALTER 不破坏现有数据 |
| 0.4 | **新增 9 个 IPC 通道 + handler** | `manuscript.handler.ts`, session 扩展 | 0.2, 0.3 | 每个 channel 有单元测试 |
| 0.5 | **新增 manuscriptStore + chapterStore** | stores/manuscript.store.ts, chapter.store.ts | 0.4 | TypeScript 编译零错误 |
| 0.6 | **新增 uiLayoutStore** | stores/ui-layout.store.ts | 无 | 可正确读写布局状态 |
| 0.7 | **提取 Design Token 为共享模块** | styles/tokens.css 或 Tailwind theme config | 无 | 所有现有组件可引用 token |

**Phase 0 DoD：**
- [ ] App.tsx < 150 行
- [ ] 所有新表可通过 migration 创建且不破坏现有数据
- [ ] 新 IPC 通道通过单元测试
- [ ] 新 Store 通过 TypeScript 类型检查
- [ ] Design Token 可被至少 3 个现有组件引用

---

### Phase 1：核心布局迁移（预估 5-6 人天）🎯 最高优先级

**目标：实现 SOLO 三栏布局，用户可直观感受到变化**

| # | 任务 | 产出物 | 依赖 | 验收标准 |
|---|------|--------|------|---------|
| 1.1 | **重写 AppShell（去除 AppHeader）** | SoloWorkspace 组件 | 0.1, 0.7 | 三栏布局正确渲染，无 Header |
| 1.2 | **实现 SoloSidebar**（项目/对话双视图） | Sidebar + ProjectView + ConversationView | uiLayoutStore | 双 Tab 切换正常，侧栏可折叠/展开 |
| 1.3 | **实现 SoloChatArea**（增强版对话主区域） | ChatArea 组件（更大空间 + Status Bar） | 无 | 对话区 ≥60% 屏幕宽度 |
| 1.4 | **实现 SoloToolPanel**（双态右侧面板） | ToolPanel 组件（图标条 ↔ 展开面板） | uiLayoutStore | 图标直接切换面板，记忆上次视图 |
| 1.5 | **实现 Status Bar** | StatusBar 组件 | uiLayoutStore | 显示当前作品/章节数/状态 |
| 1.6 | **实现 ModeSwitch**（SOLO/IDE 切换器） | ModeSwitch 组件 | uiLayoutStore | 切换时显示 mode-indicator |
| 1.7 | **侧栏恢复按钮**（收起后的展开入口） | ReopenButton 组件 | 1.2 | 收起时可见，点击恢复 |

**Phase 1 DoD：**
- [ ] 三栏布局在 Electron 窗口中正确渲染（无 Header）
- [ ] 侧栏可通过按钮折叠/展开，收起后恢复按钮可见
- [ ] 对话区占据 ≥60% 屏幕宽度
- [ ] Status Bar 正确显示上下文信息
- [ ] SOLO/IDE 切换正常工作（IDE 侧显示「开发中」提示）
- [ ] 项目视图和对话视图可切换
- [ ] 右侧面板双态转换流畅（带动画）

---

### Phase 2：业务面板实现（预估 6-8 人天）

**目标：所有面板从占位符变为真实可用的业务工具**

| # | 任务 | 产出物 | 依赖 | 验收标准 |
|---|------|--------|------|---------|
| 2.1 | **训练工坊面板完整版** | TrainingPanel（真实数据 + 交互） | trainingStore, 推荐引擎修复 | 可展示推荐训练、执行训练、记录结果 |
| 2.2 | **诊断面板完整版** | DiagnosisPanel（对接 diagnosis_results） | diagnosis parser | 可展示诊断结果列表 + 详情 |
| 2.3 | **对话视图完整版** | ConversationView（加载 + 搜索 + 分组） | session 扩展 schema | 可加载历史会话、搜索对话、按时间分组 |
| 2.4 | **任务面板完整版** | TaskPanel（对接 teaching_state） | teachingStateStore | 可查看/操作任务卡片 |
| 2.5 | **成长记录面板 MVP** | GrowthPanel（基础趋势图） | 能力数据模型设计 | 至少展示一个维度的能力变化趋势 |
| 2.6 | **设置面板基础版** | SettingsPanel | configStore | 可修改 API 密钥等基础配置 |
| 2.7 | **能力画像面板 MVP** | ProfilePanel（基础雷达图） | 能力数据模型 | 至少展示 5 个维度 |

**Phase 2 DoD：**
- [ ] 6 个业务面板均可打开并显示**真实数据**（非 mock/占位符）
- [ ] 对话视图可加载并切换历史会话
- [ ] 训练面板可完成「推荐→执行→记录」完整流程
- [ ] 诊断面板可展示最近一次诊断结果
- [ ] 设置变更可持久化

---

### Phase 3：高级功能（预估 5-7 人天）🔮 远期规划

**目标：IDE 功能 + 内容管理系统**

| # | 任务 | 说明 | 前置依赖 |
|---|------|------|---------|
| 3.1 | **内容查看器 (ContentViewer)** | 章节文本渲染（Markdown→HTML） | chapterStore + 内容加载 API |
| 3.2 | **多文件标签页系统** | FileTabManager（创建/激活/关闭/排序） | ContentViewer |
| 3.3 | **IDE 模式编辑器集成** | EditorView（contentEditable，非富文本库） | ContentViewer |
| 3.4 | **能力画像完整版** | 雷达图 + 趋势线 + 里程碑时间线 | 能力数据模型 v2 |
| 3.5 | **M-2/M-3/M-4/M-5 功能嵌入** | 内联改写/AI评价/成长记录/简化诊断 | 对话流程改造 |

> **Phase 3 不纳入本轮改造范围。** 本报告聚焦 Phase 0-2。

---

## 八、资源需求与时间规划

### 8.1 人力需求估算

| 角色 | Phase 0 | Phase 1 | Phase 2 | 合计 |
|------|---------|---------|---------|------|
| **前端工程师** (React/TS/Electron) | 2人 × 2d | 2人 × 4d | 2人 × 6d | **24 人天** |
| **后端工程师** (Node/SQLite/IPC) | 1人 × 3d | 0.5人 × 1d | 1人 × 2d | **6.5 人天** |
| **全栈/架构师**（技术方案 + 代码审查） | 0.5人 × 3d | 0.5人 × 2d | 0.5人 × 2d | **3.5 人天** |
| **小计** | **~7 人天** | **~10 人天** | **~12 人天** | **~29 人天** |

### 8.2 时间线（甘特图概念）

```
Week 1          Week 2            Week 3            Week 4            Week 5
████████        ████████          ████████          ████████          ████████
Phase 0          Phase 1           Phase 2a           Phase 2b           缓冲+验收
基础设施         核心布局           业务面板前半        业务面板后半
(DB+IPC+Store)  (三栏+侧栏)       (训练+诊断)         (对话+任务+设置)
```

### 8.3 技术资源清单

| 资源 | 状态 | 来源 |
|------|------|------|
| SOLO 模式原型 HTML | ✅ 已就绪 | `prototype-v2-workspace.html` (3144 行) |
| CSS Design Token 体系 | ✅ 已提取 | 原型 :root 变量（~50 个 token）|
| IPC 通道规范 | ✅ 27 个可复用 | 现有 `src/main/ipc/` |
| 数据库迁移框架 | ✅ 可用 | better-sqlite3 + 迁移脚本 |
| Zustand Store 模式 | ✅ 参考充分 | 9 个现有 store |
| Prompt 模板体系 | ✅ 完整 | 10 个版本化 prompt |

---

## 九、风险评估

### 9.1 高风险项

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| **App.tsx 拆分引发回归** | 中 | **高** | 逐模块拆分，每步跑通 E2E 测试；保留 feature flag 回退 |
| **sessions schema 扩展破坏现有数据** | 低 | **高** | 迁移脚本做 backward-compatible（ALTER ADD COLUMN 带 DEFAULT）|
| **推荐引擎空壳导致训练面板无内容** | **高** | 中 | Phase 2 前必须修复 recommendTasks() 或实现临时推荐逻辑 |
| **性能：大量消息时的 DOM 渲染** | 中 | 中 | 引入虚拟滚动（react-virtuoso 或 react-window）|

### 9.2 中风险项

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| Design Token 迁移与现有组件样式冲突 | 中 | 低 | 使用 CSS Module 或 CSS-in-JS 做 scope 隔离 |
| Electron 窗口尺寸限制影响三栏布局 | 低 | 中 | 设置合理的 minWidth=1200px, minHeight=700px |
| 移动端适配过度工程化 | 低 | low | Phase 1-2 只做桌面端，Mobile 延后至独立迭代 |

### 9.3 低风险项

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| Design Token 迁移工作量低估 | 中 | low | Token 数量有限（~50 个），1 天内可完成 |
| 用户习惯改变阻力 | 中 | low | SOLO 作为默认模式，保留配置回退路径 |
| 原型中部分交互细节无法 1:1 复现 | 低 | low | 以原型为参考基线，不必像素级复制 |

---

## 十、预期效果评估

### 10.1 定量目标

| 指标 | 当前值 | 目标值 | 测量方式 |
|------|--------|--------|---------|
| 对话区占屏幕宽度比 | ~45% | **≥60%** | DevTools 布局测量 |
| 用户到达「发送消息」的操作步数 | 3-4 步 | **≤2 步** | 任务分析 |
| 侧栏功能查找平均时间 | >3s | **<1.5s** | 用户测试（5 人样本）|
| 控制台错误/警告数 | **68 处** | **<10 处** | CI lint + 手动审计 |
| App.tsx 代码行数 | **455 行** | **<150 行** | cloc 统计 |
| IPC 通道覆盖率（原型假设 vs 实际实现）| ~73% | **≥95%** | 逐 channel 对照 |

### 10.2 定性目标

| 维度 | 当前体验 | 目标体验 |
|------|---------|---------|
| **产品定位传达** | 「又一个写作辅助工具」 | **「你的 AI 写作教练」** |
| **对话体验质量** | 被其他 UI 元素干扰和压缩 | **沉浸式一对一教练对话** |
| **信息架构清晰度** | 功能混杂堆叠，用户需自行寻找 | **三层分离：内容管理 / 对话 / 工具** |
| **长期使用友好度** | 对话容易丢失，无法回溯 | **对话永久保存 + 快速检索 + 时间分组** |
| **视觉品质** | 功能导向，缺乏品牌一致性 | **暖纸质美学 + 金棕品牌色系 + 细节打磨** |
| **可扩展性** | 新功能难以找到合适位置 | **右侧面板插件化 + 多标签页扩展** |

---

## 十一、最终结论与采纳建议

### 采纳建议：**有条件采纳，分阶段实施**

```
✅ 立即采纳（Phase 0 + Phase 1）
   → SOLO 三栏布局、侧栏双视图、Status Bar、ModeSwitch
   → 这些是零/低后端依赖的纯前端改造，效果立竿见影
   → 用户可在 2 周内直观感受到产品体验的质变

⏳ 条件采纳（Phase 2）
   → 业务面板的真实数据对接
   → 前提条件：DB schema 扩展(0.2/0.3) + IPC 新增(0.4) + 推荐引擎修复

🔮 延后规划（Phase 3）
   → 内容查看器、多文件标签页、IDE 编辑器
   → 前提条件：manuscripts/chapters 表 + 内容管理流程设计
```

### 核心论点

> **原型的最大价值不在某个具体组件，而在于它重新定义了产品与用户的对话关系——从「工具操作者」到「教练学员」。这个理念的落地不需要等所有后端就绪，可以从布局改造开始，逐步填充。**

### 下一步行动

1. **评审本报告** — 确认范围、优先级、时间线
2. **启动 Phase 0** — 从 App.tsx 拆分和数据库迁移开始
3. **同步推进缺陷修复** — 参考[ companion defect report](../reports/V2_PROJECT_DEFECTS_REPORT_V1.0.md)处理 P0/P1 问题
4. **建立 CI 质量门禁** — 确保改造过程中不引入新的技术债务

---

*文档结束*
