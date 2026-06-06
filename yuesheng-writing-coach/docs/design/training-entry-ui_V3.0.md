# 训练入口 UI 设计方案 V3.0

> **状态**: 提案 | **日期**: 2026-06-05  
> **前置版本**: V2.0（左侧栏小窗口方案，已废弃）  
> **核心变更**: 训练入口采用**中心面板模式切换**，支持主动训练 + 被动推荐双入口  
> **废弃原因**: V2.0 只考虑被动推荐场景，忽略了用户主动训练需求；左侧栏 280px 空间不足以支撑真正的练习交互

## 0. V2.0 → V3.0 的关键转折

V2.0 的根本问题是**只有被动推荐**——AI诊断出问题后推荐训练，用户跟着走。但现实中用户会主动想练：*"我情绪标签化老是犯，让我专门练练展示替代告知"*。

| 维度 | V2.0（废弃） | V3.0（当前） |
|------|-------------|-------------|
| 训练入口位置 | 左侧栏小窗口 | **中心面板模式切换** |
| 空间 | 280px 宽，80-260px 高 | **全宽 flex:1 中心区域** |
| 用户主动性 | 被动——只能等AI推荐 | **主动+被动双入口** |
| 历史错误展示 | 无 | **错误卡片+内容引用** |
| 训练交互 | 简单输入框 | **步骤式练习+进度条** |
| AI个性化 | 无（静态模板匹配） | **规划中（独立子系统）** |

---

## 1. 设计核心：双模式 + 双入口

### 1.1 中心面板双模式

```
┌─ AppShell ──────────────────────────────────────────────┐
│  Header                                                  │
├──────────┬───────────────────────────────┬───────────────┤
│          │                               │               │
│ Sidebar  │   中心区域 (flex:1)           │  RightPanel   │
│ (280px)  │                               │  (320px)      │
│          │   模式 A: 对话流 (默认)       │               │
│  会话列表│   模式 B: 训练工坊            │  诊断+趋势    │
│          │                               │               │
└──────────┴───────────────────────────────┴───────────────┘
```

**模式切换方式**: `centerMode: 'chat' | 'training'`
- 默认 `'chat'` — 正常对话流
- 切换到 `'training'` — 中心区域渲染 TrainingWorkshop 组件
- 切换回 `'chat'` — 对话流恢复，消息不丢失

### 1.2 双入口设计

**入口 1: 主动入口（左侧栏训练按钮）**

在 AppSidebar 的"新建会话"按钮下方，增加一个"训练工坊"按钮：

```
┌─ AppSidebar ──────────────┐
│ + 新建会话                 │
│ 🔥 训练工坊  ← 新增按钮   │
│                            │
│ ── 最近会话 ──             │
│ 当前会话 *                 │
│ 旧会话 1                   │
└───────────────────────────┘
```

用户随时可以点击进入训练工坊，不需要等AI推荐。这解决的是"用户单纯想练某个技法"的场景。

**入口 2: 被动入口（对话流中 AI 推荐）**

在对话流中，AI诊断后如果匹配到挑战模板，插入 TrainingBridgeCard：

```
┌─ TrainingBridgeCard ────────────────┐
│ 🎯 匹配到练习                        │
│                                      │
│ 针对你的「世界观膨胀」问题，           │
│ 有一个聚焦核心场景的练习               │
│                                      │
│ [进入训练工坊]  [下次再说]            │
└──────────────────────────────────────┘
```

点击"进入训练工坊" → centerMode 切换到 `'training'`，并自动定位到对应错误卡片。

---

## 2. 训练工坊面板设计（centerMode='training'）

训练工坊包含三个区块，自上而下排列：

### 2.1 区块一：你的常见问题（基于历史诊断）

从 `diag.store` 的 `history` 中聚合用户的历史诊断，按症候分组，展示：

```
┌─ 你的常见问题 ──────────────────────────────────┐
│                                                   │
│ ┌─ P001 世界观膨胀 ──────────────┐ ┌─ P003 情绪标签化 ──┐ │
│ │ L3 | 3次诊断                   │ │ L2 | 2次诊断       │ │
│ │ 最近引用:                      │ │ 最近引用:          │ │
│ │ "整个大陆被分为五个王国，       │ │ "他很紧张，心里    │ │
│ │  每个王国都有独特的魔法体系..." │ │  充满了不安和恐惧"  │ │
│ │ [CH-P001 聚焦]                 │ │ [CH-P003 展示]     │ │
│ └────────────────────────────────┘ └──────────────────┘ │
│                                                   │
│ ┌─ P009 角色动机缺失 ────────────┐                   │
│ │ L3 | 1次诊断                   │                   │
│ │ 最近引用:                      │                   │
│ │ "主角决定去找那个人，因为       │                   │
│ │  剧情需要他这么做..."           │                   │
│ └────────────────────────────────┘                   │
└───────────────────────────────────────────────────────┘
```

**错误卡片数据源**:
- 症候 ID + 名称：来自 `DiagnosisEntry.syndromes[]`
- 诊断次数：从 `diag.store.history` 按 syndromeId 聚合计数
- 严重度：取最近一次该症候的 severity
- 最近引用：取最近一次该症候诊断时用户发送的文本片段（需要从 `chat.store.messages` 中提取对应轮次的用户输入）

**错误卡片交互**:
- 点击卡片 → 滚动到下方对应的训练任务卡片
- 卡片上的 CH-Pxxx 按钮 → 直接开始对应训练

### 2.2 区块二：推荐训练任务

基于错误卡片中的症候，从 `challenge-templates.json` 匹配挑战模板：

```
┌─ 推荐训练任务 ──────────────────────────────────┐
│                                                   │
│ ┌─ CH-P001 聚焦核心场景 ─────────────────────┐   │
│ │ structural | ~15min                         │   │
│ │ 你的开篇设定很宏大。现在请你挑出其中一个     │   │
│ │ 具体的场景，把其他设定全部删掉，只留这个场景。│   │
│ │ [P001] [A001]            [开始练习]         │   │
│ └─────────────────────────────────────────────┘   │
│                                                   │
│ ┌─ CH-P003 展示替代告知 ─────────────────────┐   │
│ │ surface | ~5min                             │   │
│ │ 删掉"紧张"这个词，只用一个具体的动作或神态   │   │
│ │ 来让读者感受到紧张。                         │   │
│ │ [P003] [A005]            [开始练习]         │   │
│ └─────────────────────────────────────────────┘   │
│                                                   │
│ ┌─────────────────────────────────────────────┐   │
│ │ AI 个性化训练：基于你的错误模式，AI 可生成   │   │
│ │ 更精准的定制练习（规划中）                    │   │
│ └─────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────┘
```

**任务卡片数据源**:
- 挑战描述/约束/难度：来自 `challenge-templates.json`
- 排序策略：fatal tier 优先 → severity 高的优先 → 诊断次数多的优先
- 标签：Pxxx（关联症候）+ Axxx（关联动作）

### 2.3 区块三：训练记录

底部展示最近的训练记录（来自 `training-record.service.ts`）：

```
┌─ 近期训练记录 ──────────────────────────────┐
│ ✓ CH-P003 展示替代告知  已完成              │
│ ○ CH-P001 聚焦场景      进行中              │
│ — CH-P009 动机深掘      已跳过              │
└─────────────────────────────────────────────┘
```

---

## 3. 训练进行中的交互设计

用户点击"开始练习"后，中心面板进入**训练进行态**：

### 3.1 步骤式练习

每个挑战模板拆解为 2-3 个步骤：

| 步骤 | CH-P001 聚焦核心场景 | CH-P003 展示替代告知 |
|------|---------------------|---------------------|
| Step 1 | 阅读你的原始文本 | 阅读你的情绪标签 |
| Step 2 | 聚焦一个场景，删除其余 | 删掉情绪词，用动作替代 |
| Step 3 | 对比修改前后的效果 | 对照原文检查约束 |

**步骤拆解来源**: `challenge-templates.json` 的 `mode` 字段映射到步骤模板（新增 `steps` 扩展字段，或硬编码 mode→steps 映射）。

### 3.2 练习交互面板布局

```
┌─ CH-P001 聚焦核心场景 ─── 步骤 2/3 ─── [返回] [跳过] ─┐
│ ████████████████░░░░░░░░░░  进度条 66%                   │
│                                                           │
│ ✓ Step 1: 阅读你的原始文本 — 已完成                        │
│                                                           │
│ ┌─ Step 2: 聚焦一个场景，删除其余设定 ─────────────────┐  │
│ │ 约束：只能保留一个具体场景，其余全部删除               │  │
│ │                                                       │  │
│ │ ┌─ 你的原始文本 ─────────────────────────────────┐   │  │
│ │ │ "整个大陆被分为五个王国，每个王国都有独特的      │   │  │
│ │ │  魔法体系，北方的冰之国以霜咒闻名..."            │   │  │
│ │ └─────────────────────────────────────────────────┘   │  │
│ │                                                       │  │
│ │ ┌─ Challenge ────────────────────────────────────┐   │  │
│ │ │ 挑出其中一个具体的场景，把其他设定全部删掉       │   │  │
│ │ │ 提示：选一个你最有感觉的王国，写出那里发生的     │   │  │
│ │ │ 一件小事                                         │   │  │
│ │ └─────────────────────────────────────────────────┘   │  │
│ │                                                       │  │
│ │ ┌─ 写作区 ───────────────────────────────────────┐   │  │
│ │ │ 北方的冰之国，一间破旧的铁匠铺里，老铁匠用     │   │  │
│ │ │ 颤抖的手将最后一块霜铁放进熔炉。他的孙女站在   │   │  │
│ │ │ 门口，裹着母亲留下的旧斗篷...                    │   │  │
│ │ └─────────────────────────────────────────────────┘   │  │
│ └───────────────────────────────────────────────────────┘  │
│                                                           │
│ [存草稿]                              [提交练习]           │
└───────────────────────────────────────────────────────────┘
```

### 3.3 提交后的反馈

1. 用户提交 → 后端 `training:complete` IPC
2. AI 评估用户修改（是否满足约束、效果如何）
3. 评估结果显示在对话流中（自动切回 chat 模式）
4. 更新训练记录状态
5. 如果还有下一步骤，继续；否则显示完成总结

---

## 4. 组件架构

### 4.1 新增组件

#### `TrainingWorkshop.tsx`（训练工坊主面板）

位置：`src/renderer/components/training/TrainingWorkshop.tsx`

替代 V2.0 的 TrainingWorkspace（左侧栏小窗口），现在是中心面板全宽组件。

```typescript
interface TrainingWorkshopProps {
  /** 历史诊断聚合的错误卡片数据 */
  errorCards: ErrorCard[];
  /** 推荐的训练任务列表 */
  recommendations: TrainingRecommendation[];
  /** 当前活跃训练（进行中） */
  activeTraining: ActiveTrainingSession | null;
  /** 训练历史记录 */
  recentHistory: TrainingRecord[];
  /** 开始训练 */
  onStartTraining: (challengeId: string) => void;
  /** 返回对话 */
  onBackToChat: () => void;
}

interface ErrorCard {
  syndromeId: string;
  syndromeName: string;
  severity: SeverityLevel;
  diagnosisCount: number;
  lastQuote: string;          // 最近一次触发此症候的用户文本片段
  lastDiagnosedAt: string;    // ISO 8601
  matchedChallengeId?: string; // 匹配到的挑战模板ID
}

interface ActiveTrainingSession {
  challengeId: string;
  challengeName: string;
  steps: TrainingStep[];
  currentStepIndex: number;
  originalQuote: string;      // 触发训练的原始文本
  constraint: string;          // 挑战约束
  userDraft: string;           // 草稿内容
}

interface TrainingStep {
  id: string;
  title: string;
  description: string;
  status: 'completed' | 'active' | 'pending';
}
```

#### `TrainingBridgeCard.tsx`（对话流桥接卡片）

位置：`src/renderer/components/chat/TrainingBridgeCard.tsx`

替代 V2.0 的 TrainingCard，现在是**触发模式切换**而非打开侧边栏。

```typescript
interface TrainingBridgeCardProps {
  /** 推荐的训练信息 */
  recommendation: TrainingRecommendation;
  /** 点击"进入训练工坊" → 切换 centerMode 到 'training' */
  onEnterWorkshop: (challengeId: string) => void;
  /** 点击"下次再说" */
  onDismiss: () => void;
}
```

#### `TrainingHistoryBar.tsx`（训练历史栏）

位置：`src/renderer/components/training/TrainingHistoryBar.tsx`

嵌入 TrainingWorkshop 底部，展示最近训练记录。

```typescript
interface TrainingHistoryBarProps {
  records: TrainingRecord[];
  maxItems?: number;
}
```

### 4.2 新增类型

在 `src/renderer/shared/types.ts` 中新增：

```typescript
/** 训练推荐（与 V2.0 相同） */
export interface TrainingRecommendation {
  id: string;
  challengeId: string;
  syndromeId: string;
  syndromeName: string;
  challenge: string;
  constraint: string;
  difficulty: 'surface' | 'structural' | 'fatal';
  estimatedMinutes: number;
  source: 'proactive' | 'diagnosis' | 'ai_suggestion' | 'reflection_unlock';
}

/** 中心面板模式 */
export type CenterMode = 'chat' | 'training';

/** 错误卡片（训练工坊用） */
export interface ErrorCard {
  syndromeId: string;
  syndromeName: string;
  severity: SeverityLevel;
  diagnosisCount: number;
  lastQuote: string;
  lastDiagnosedAt: string;
  matchedChallengeId?: string;
}

/** 活跃训练会话 */
export interface ActiveTrainingSession {
  challengeId: string;
  challengeName: string;
  steps: TrainingStep[];
  currentStepIndex: number;
  originalQuote: string;
  constraint: string;
  userDraft: string;
}

/** 训练步骤 */
export interface TrainingStep {
  id: string;
  title: string;
  description: string;
  status: 'completed' | 'active' | 'pending';
}
```

### 4.3 新增 Store

`src/renderer/stores/training.store.ts`:

```typescript
interface TrainingStore {
  /** 中心面板模式 */
  centerMode: CenterMode;

  /** 错误卡片（从诊断历史聚合） */
  errorCards: ErrorCard[];

  /** 推荐的训练任务 */
  recommendations: TrainingRecommendation[];

  /** 当前活跃训练 */
  activeTraining: ActiveTrainingSession | null;

  /** 训练历史 */
  history: TrainingRecord[];

  /** 加载状态 */
  isLoading: boolean;

  /** 切换到训练工坊 */
  enterWorkshop: () => void;

  /** 返回对话 */
  backToChat: () => void;

  /** 从诊断结果刷新错误卡片和推荐 */
  refreshFromDiagnosis: () => void;

  /** 开始训练 */
  startTraining: (challengeId: string) => Promise<void>;

  /** 更新当前步骤的草稿 */
  updateDraft: (content: string) => void;

  /** 提交当前步骤 */
  submitStep: () => Promise<void>;

  /** 跳过训练 */
  skipTraining: () => Promise<void>;

  /** 加载训练历史 */
  loadHistory: (sessionId: string) => Promise<void>;
}
```

### 4.4 IPC 通道（与 V2.0 相同，5个）

| 通道 | 请求 | 响应 | 说明 |
|------|------|------|------|
| `training:recommend` | `{ sessionId, syndromeIds }` | `TrainingRecommendation[]` | 匹配挑战模板 |
| `training:assign` | `{ sessionId, challengeId, syndromeId }` | `TrainingRecord` | 分配训练 |
| `training:complete` | `{ trainingId, userResponse }` | `{ record, evaluation }` | 完成并获取评估 |
| `training:skip` | `{ trainingId }` | `TrainingRecord` | 跳过训练 |
| `training:getHistory` | `{ sessionId, limit? }` | `TrainingRecord[]` | 查询历史 |

---

## 5. 现有文件修改清单

### 5.1 需要修改的文件

| # | 文件 | 修改内容 | 影响范围 |
|---|------|---------|---------|
| 1 | `App.tsx` | 新增 `centerMode` 状态（替代 `sidebarPage`）；TrainingWorkshop 条件渲染；TrainingBridgeCard 嵌入对话流；training store 接入 | 高 |
| 2 | `AppSidebar.tsx` | 新增"训练工坊"按钮 + onClick 切换 centerMode | 中 |
| 3 | `AppShell.tsx` | 无需修改（children 已支持任意内容） | 无 |
| 4 | `RightPanel.tsx` | 无需修改（训练不在右侧栏） | 无 |
| 5 | `shared/types.ts` | 新增 CenterMode / ErrorCard / ActiveTrainingSession / TrainingStep | 低 |
| 6 | `main/index.ts` | 注册 training IPC handler | 低 |

### 5.2 App.tsx 改造细节

当前 App.tsx 使用 `sidebarPage: 'chat' | 'tasks'` 控制中心区域内容。

改造：
1. 将 `sidebarPage` 替换为 `centerMode: CenterMode`
2. `'chat'` → 渲染 MessageList + MessageInput（不变）
3. `'training'` → 渲染 TrainingWorkshop
4. 删除 `'tasks'` 模式（TasksPage 被 TrainingWorkshop 替代）
5. 新增 `useTrainingStore` 的接入和事件监听

```typescript
// 旧代码
type SidebarPage = 'chat' | 'tasks';
const [sidebarPage, setSidebarPage] = useState<SidebarPage>('chat');

// 新代码
const { centerMode, enterWorkshop, backToChat } = useTrainingStore();

// 渲染逻辑
{centerMode === 'chat' ? (
  <>
    <MessageList ... />
    <TrainingBridgeCard ... />  {/* 新增：对话流中的桥接卡片 */}
    <MessageInput ... />
  </>
) : (
  <TrainingWorkshop
    errorCards={errorCards}
    recommendations={recommendations}
    activeTraining={activeTraining}
    recentHistory={recentHistory}
    onStartTraining={handleStartTraining}
    onBackToChat={backToChat}
  />
)}
```

### 5.3 AppSidebar.tsx 改造细节

在"新建会话"按钮下方增加"训练工坊"按钮：

```typescript
// 在 header div 的 border-bottom 之后，section label 之前插入
<div style={{ padding: '8px 14px' }}>
  <button
    onClick={onEnterWorkshop}  // 新增 prop
    style={{
      width: collapsed ? 36 : '100%',
      padding: collapsed ? 0 : '8px 16px',
      border: '1px solid var(--accent)',
      borderRadius: 'var(--radius-md)',
      background: 'transparent',
      color: 'var(--accent)',
      fontSize: '0.85rem',
      cursor: 'pointer',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 6,
    }}
  >
    {collapsed ? '🎯' : '🎯 训练工坊'}
  </button>
</div>
```

新增 prop:
```typescript
interface AppSidebarProps {
  // ...existing props
  onEnterWorkshop: () => void;  // 新增
}
```

### 5.4 需要删除的代码

| 文件 | 删除内容 | 原因 |
|------|---------|------|
| `App.tsx` | `sidebarPage` 状态 + `TasksPage` 导入和渲染 | 被 centerMode + TrainingWorkshop 替代 |
| `App.tsx` | `TasksPage` 相关代码 | 不再需要独立任务页面 |
| `stores/task.store.ts` | 整个文件（只有3行注释） | 被 training.store.ts 替代 |

> 注意：`TasksPage.tsx` 组件文件暂时保留不删，因为其内部的 `generateTasksFromProblems` 和 `TaskCard` 逻辑可复用到 TrainingWorkshop。

---

## 6. 交互流程

### 6.1 主动训练流程

```
用户点击左侧栏"训练工坊"按钮
  → training.store.enterWorkshop()
  → centerMode = 'training'
  → 刷新 errorCards（从 diag.store.history 聚合）
  → 刷新 recommendations（从 challenge-templates 匹配）
  → 渲染 TrainingWorkshop
  → 用户浏览错误卡片 + 训练任务
  → 用户点击"开始练习"
  → training.store.startTraining(challengeId)
  → 后端 training:assign 分配训练
  → 渲染步骤式练习面板
  → 用户完成练习 → 提交
  → 后端 training:complete + AI 评估
  → 自动切回 centerMode='chat'
  → 对话流中显示 AI 评估反馈
```

### 6.2 被动推荐流程

```
AI 诊断返回 DiagnosisEntry
  → 前端接收 DIAGNOSIS_UPDATE 事件
  → 匹配 challenge-templates
  → 对话流中插入 TrainingBridgeCard
  → 用户点击"进入训练工坊"
  → 同 6.1 流程（从 enterWorkshop 开始）
```

### 6.3 优雅降级

- 无历史诊断 → 错误卡片为空 → TrainingWorkshop 显示空状态："开始对话后，你的常见写作问题会出现在这里"
- 有诊断但无匹配模板 → 只显示错误卡片，训练任务区显示"暂无匹配的练习"
- 训练工坊中返回对话 → 草稿保存到 localStorage，下次进入可恢复

---

## 7. AI 个性化训练系统（独立子系统，规划中）

用户提出的核心创新：不是从9个静态模板中挑选，而是基于用户的**具体错误**，由 AI **实时生成**个性化训练任务。

### 7.1 与静态模板的区别

| 维度 | 静态模板（当前） | AI 个性化训练（规划） |
|------|----------------|---------------------|
| 任务来源 | challenge-templates.json（9个固定模板） | AI 基于用户文本实时生成 |
| 任务内容 | 通用描述（"删掉情绪词"） | 针对用户具体文本定制（"你写了'他很紧张'，试试用手指敲桌面的动作替代"） |
| 步骤设计 | 固定2-3步 | AI 根据错误严重度动态拆解 |
| 评估 | 简单约束检查 | AI 多维度评估（约束满足度 + 效果提升度 + 创意度） |
| 依赖 | 无额外 API 调用 | 需要额外 LLM 调用 |

### 7.2 架构预留

在 T-021 实现中：
1. `TrainingRecommendation.source` 新增 `'ai_generated'` 值
2. `training:recommend` IPC 的响应中区分 `source: 'template' | 'ai_generated'`
3. 训练工坊 UI 中，AI 生成的任务卡片带有"AI定制"标签
4. 底部提示文字预留："AI 个性化训练（规划中）"

### 7.3 独立子系统规划

```
AI Personalized Training System (T-022, 规划中)
├── 训练生成器（AI Training Generator）
│   ├── 输入：用户历史诊断 + 错误模式 + 最近写作片段
│   ├── 输出：个性化训练任务（挑战描述 + 约束 + 步骤 + 评估标准）
│   └── LLM 调用：使用 DeepSeek V4
├── 训练评估器（AI Training Evaluator）
│   ├── 输入：训练约束 + 用户修改
│   ├── 输出：评估报告（满足度分数 + 改进建议 + 下一步推荐）
│   └── LLM 调用：使用 DeepSeek V4
└── 训练进化器（Training Evolver）
    ├── 输入：用户训练历史 + 能力画像变化
    ├── 输出：难度调整 + 新训练推荐
    └── 规则引擎：基于 BKT 模型（贝叶斯知识追踪）
```

---

## 8. 样式规范

遵循月下书房暖调水墨风，与现有 UI 一致：

| 元素 | 背景 | 边框 | 文字 |
|------|------|------|------|
| 训练工坊标题栏 | `var(--accent-subtle)` | `var(--accent)` | `var(--text-primary)` |
| 错误卡片 | `white` | 严重度色（coral/amber/red） | `var(--text-primary)` |
| 训练任务卡片 | `white` | teal/green | `var(--text-primary)` |
| 原始文本引用 | `coral-50` | `coral-200` 左侧竖条 | `var(--text-secondary)` |
| 挑战描述 | `teal-50` | `teal-200` | `teal-600` |
| 写作区 | `var(--bg-input)` | `var(--border)` | `var(--text-primary)` |
| 主按钮 | `teal-600` | none | `white` |
| 进度条 | `gray-100` (bg) | none | — |
| 进度条填充 | `teal-600` | none | — |

图标（lucide-react）：
- 训练工坊入口：`Dumbbell`
- 错误卡片：`AlertTriangle`
- 训练任务：`Target`
- 步骤完成：`CheckCircle`
- 训练历史：`Clock`

---

## 9. 与 V2.0 的完整差异

| 项目 | V2.0 | V3.0 |
|------|------|------|
| 训练入口位置 | 左侧栏小窗口 | **中心面板模式切换** |
| 主动训练 | 不支持 | **左侧栏按钮随时进入** |
| 被动推荐 | 对话流中展开练习 | **桥接卡片，点击切换模式** |
| 历史错误展示 | 无 | **错误卡片+内容引用** |
| 训练交互 | 简单输入框 | **步骤式练习+进度条** |
| 空间 | 280px × 260px | **全宽 flex:1** |
| TasksPage | 共存 | **被 TrainingWorkshop 替代** |
| AI 个性化 | 无 | **规划中（独立子系统）** |
| 新增组件 | TrainingWorkspace(侧栏) | TrainingWorkshop(中心面板) |
| 删除代码 | 无 | sidebarPage + TasksPage 渲染 |
| AppSidebar | 新增训练窗插槽 | 新增训练工坊按钮 |

---

## 10. 开放问题

1. **错误卡片的"最近引用"如何获取？** 当前 `DiagnosisEntry` 不包含触发诊断的用户原文。需要：a) 后端在诊断时附带用户文本片段，或 b) 前端从 chat.messages 中按时间戳匹配。倾向 a) 方案。
2. **步骤拆解的数据源？** challenge-templates.json 只有 `mode` 字段，没有步骤。需要：a) 扩展 JSON 增加 steps 数组，或 b) 前端硬编码 mode→steps 映射。倾向 a) 方案。
3. **训练草稿持久化？** 用户在训练中途返回对话，草稿是否保存？建议 localStorage 按 sessionId+challengeId 存储。
4. **AI 个性化训练的优先级？** 作为独立子系统（建议 T-022），是否在当前任务链中排序？如果排入，放在 T-017 之后还是 T-018 之后？
