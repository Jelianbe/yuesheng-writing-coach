# 训练入口 UI 设计方案 V4.0

> **状态**: 提案 | **日期**: 2026-06-05
> **前置版本**: V2.0（左侧栏小窗口，已废弃）、V3.0（中心面板模式切换，遗漏对话内训练）
> **核心变更**: 双路径训练架构 — 对话内训练（已实现）+ 训练工坊（待实现）；新增内容感知路由层

## 0. 版本演化

| 版本 | 核心方案 | 状态 | 废弃原因 |
|------|---------|------|---------|
| V2.0 | 左侧栏可折叠小窗口 | ❌ 废弃 | 只考虑被动推荐，忽略主动训练需求；280px 空间不够 |
| V3.0 | 中心面板模式切换（TrainingWorkshop） | ⚠️ 部分采纳 | 遗漏了对话内训练路径；诊断-训练强绑定问题未解决 |
| **V4.0** | **双路径 + 内容感知路由** | ✅ 当前 | 整合对话内训练（已实现）+ 训练工坊（V3.0 保留）+ 路由解耦 |

### V3.0 → V4.0 的关键转折

V3.0 的两个盲区：

1. **遗漏对话内训练**：代码中已有 DiagnosisCard→EditPanel→EvaluationCard→GrowthCard 的完整链路，嵌入在对话流中。V3.0 只设计了"跳转到训练工坊"的路径，没保留这条更轻量的对话内路径。
2. **诊断-训练强绑定**：当前 `MessageRouter.shouldRunDiagnosis` 只看字数（≥100）和"是不是提问"，不管内容类型。世界观设定、杂乱碎片、新用户首次灌入的内容，都会触发诊断，但文本改写对这些场景没有意义。

---

## 1. 设计核心：双路径 + 内容感知路由

### 1.1 整体架构

```
用户发文本
    │
    ├─ 内容感知路由层（新增）
    │   ├─ 新用户/未初始化？ → 新手引导模式
    │   ├─ 叙事文本？        → 诊断 → 对话内训练
    │   ├─ 世界观/设定？     → 梳理引导（不改写）
    │   ├─ 碎片/杂项？       → 澄清意图
    │   └─ 对话/提问？       → 纯教学对话
    │
    ├── 路径 A：对话内训练（轻量，已实现）
    │   DiagnosisCard → EditPanel → EvaluationCard → GrowthCard
    │   嵌入对话流，不改页面，不改上下文
    │
    └── 路径 B：训练工坊（沉浸，待实现，继承 V3.0）
        centerMode='training' → TrainingWorkshop
        中心面板切换，步骤式练习，主动训练
```

### 1.2 双路径定位

| 维度 | 路径 A：对话内训练 | 路径 B：训练工坊 |
|------|------------------|-----------------|
| **触发方式** | AI 诊断后用户点"尝试修改" | 用户主动点左侧栏按钮 / 对话流桥接卡片 |
| **空间** | 对话流内嵌展开 | 中心面板全宽替换 |
| **上下文** | 保持完整对话上下文 | 切换到独立练习界面，对话消息不丢失 |
| **交互深度** | 轻量——原文→改写→评估 | 沉浸——步骤式练习+进度条+约束检查 |
| **适用场景** | 诊断后的即时练习 | 用户主动想练某个技法 / 多步骤专项训练 |
| **用户心智** | "试试改一下这段" | "我要系统练这个" |
| **实现状态** | ✅ 已接线（M-2/M-3/M-4） | ❌ 待实现（T-021） |

### 1.3 三层职责分离（保留 V2.0 设计决策）

| 区域 | 职责层 | 用户心智 | 包含组件 |
|------|--------|---------|---------|
| **左侧栏** | 行动层 | "我要做什么" | 训练工坊入口按钮 + 会话列表 |
| **对话流** | 触发层 + 轻量执行层 | "教练建议我改这里" | DiagnosisCard / EditPanel / EvaluationCard / GrowthCard / TrainingBridgeCard |
| **右侧栏** | 观察层 | "我的问题是什么" | 对话焦点 + 教学进度 + 诊断发现 + 能力成长 |

---

## 2. 内容感知路由层（新增）

### 2.1 当前问题

`MessageRouter.shouldRunDiagnosis()` 的判断逻辑过于简单：

```typescript
// 当前实现：只看字数和提问特征
shouldRunDiagnosis(message: string): boolean {
  return this.isAnalyzeableText(message);
  // ≥100 字 + 非纯提问 → 触发诊断
}
```

**问题场景**：

| 用户发了什么 | 当前行为 | 应有行为 |
|------------|---------|---------|
| 叙事文本（小说段落） | ✅ 诊断合理 | 诊断 → 可选训练 |
| 世界观/设定资料 | ❌ 弹诊断，改写没意义 | 梳理引导，不是改写 |
| 新用户首次灌入大量内容 | ❌ 直接诊断，体验差 | 新手引导，了解意图 |
| 杂七杂八的碎片 | ❌ 硬诊断 | 澄清意图，帮助聚焦 |
| 纯对话/闲聊 | ✅ 跳过 | 继续跳过 |

### 2.2 路由逻辑设计

```typescript
type ContentType = 'narrative' | 'worldbuilding' | 'fragment' | 'dialogue' | 'question';
type RouteTarget = 'diagnosis' | 'worldbuild_guide' | 'clarify' | 'teaching_chat' | 'onboarding';

interface RouteDecision {
  contentType: ContentType;
  target: RouteTarget;
  confidence: number;  // 0-1，低置信度时降级为 clarify
}

class ContentAwareRouter {
  /**
   * 分析用户输入的内容类型和路由目标
   * 优先级：onboarding > content_type > fallback
   */
  route(message: string, userContext: UserContext): RouteDecision;

  /**
   * 判断是否为新用户/未初始化
   * 条件：无历史诊断 + 无能力画像 + 首次交互
   */
  isOnboarding(userContext: UserContext): boolean;

  /**
   * 分类内容类型
   * 叙事文本：有角色动作/对话/场景描写
   * 世界观：大量设定性描述、名词解释、体系说明
   * 碎片：混合内容、无明确焦点
   * 对话：纯交流
   * 提问：以问句为主
   */
  classifyContent(message: string): ContentType;
}
```

### 2.3 路由映射

| 内容类型 | 路由目标 | 月笙行为 | 是否触发诊断 |
|---------|---------|---------|:-----------:|
| `narrative` | `diagnosis` | 正常诊断 → 可选对话内训练/训练工坊 | ✅ |
| `worldbuilding` | `worldbuild_guide` | 引导梳理逻辑、检验内部一致性 | ❌ |
| `fragment` | `clarify` | 澄清意图："你想用这段做什么？" | ❌ |
| `dialogue` | `teaching_chat` | 纯教学对话 | ❌ |
| `question` | `teaching_chat` | 回答问题 | ❌ |
| — | `onboarding` | 新手引导：了解写作目标→设定基线→推荐起步路径 | ❌ |

### 2.4 实现策略

**Phase 1（MVP）**：规则引擎
- 基于关键词/模式匹配的内容分类（"王国/体系/设定"→worldbuilding，"他/她/说/走"→narrative）
- 用户状态判断（`student-context` 中的诊断历史是否为空）
- 低置信度时默认降级为 `clarify`

**Phase 2**：AI 辅助路由
- 调用 LLM 做内容分类（单次快速调用，不需要完整 DiagnosisAgent）
- 结合能力画像做更精准的 onboarding 判断

---

## 3. 路径 A：对话内训练（已实现）

### 3.1 链路概览

```
用户发叙事文本
    → 内容路由：narrative → diagnosis
    → DiagnosisAgent 分析
    → DiagnosisCard 渲染（对话流底部）
    → 用户点击"✏️ 尝试修改"
    → EditPanel 展开（DiagnosisCard 下方）
    → 用户写修改稿并提交
    → EvaluationCard 出现（AI 评估对比）
    → GrowthCard 出现（成长记录）
```

### 3.2 组件接口

#### DiagnosisCard

```typescript
interface DiagnosisCardProps {
  diagnosis: DiagnosisEntry;
  /** 点击"尝试修改"回调 → 触发路径 A */
  onStartEditing?: (syndromeId: string, evidence: string[], name: string, severity: string) => void;
}
```

渲染条件：`currentDiagnosis && !isStreaming`

每个症候卡片上的交互按钮：
- **"✏️ 尝试修改"** → 调用 `onStartEditing`，触发 EditPanel
- **"📖 查看建议"** → 展开建议动作列表

#### EditPanel

```typescript
interface EditPanelProps {
  originalTexts: string[];       // 原文段落（症候 evidence）
  syndromeName: string;          // 综合征名称
  onSubmit: (rewrittenText: string) => void;
  onCancel: () => void;
  isSubmitting: boolean;
}
```

在 DiagnosisCard 下方条件渲染：`editingSyndrome !== null`

#### EvaluationCard

```typescript
interface EvaluationCardProps {
  evaluation: RewriteEvaluation;
  originalText?: string;
  rewrittenText?: string;
}
```

在 EditPanel 下方条件渲染：`lastEvaluation !== null`

#### GrowthCard

```typescript
interface GrowthCardProps {
  summary: string;
  hasHistory: boolean;
  isLoading?: boolean;
}
```

### 3.3 状态编排：useDiagnosisFlow

```typescript
interface DiagnosisFlowState {
  editingSyndrome: EditingSyndrome | null;   // 当前编辑中的症候
  isSubmitting: boolean;                      // 提交中
  lastEvaluation: RewriteEvaluation | null;   // 最近评估
  lastRewrittenText: string | null;           // 最近修改稿
  lastOriginalText: string | null;            // 最近原文
  growthLoading: boolean;
  growthSummary: string | null;
  hasHistory: boolean;
}
```

状态机转换：

```
idle → editing   : startEditing(syndromeId, evidence, name, severity)
editing → submitting : submitRewrite(rewrittenText)
submitting → evaluated : 评估成功，设置 lastEvaluation
submitting → idle     : 评估失败，关闭编辑面板
evaluated → idle      : reset（新诊断到来时）
any → idle           : cancelEditing / reset
```

### 3.4 App.tsx 接线

```tsx
// DiagnosisCard + 对话内训练组件 在对话流底部
{currentDiagnosis && !isStreaming && (
  <div className="px-4 pb-2">
    <div className="max-w-3xl mx-auto space-y-3">
      <DiagnosisCard
        diagnosis={currentDiagnosis}
        onStartEditing={startEditing}
      />
      {editingSyndrome && (
        <EditPanel
          originalTexts={editingSyndrome.evidence}
          syndromeName={editingSyndrome.name}
          onSubmit={(rewrittenText) => submitRewrite(rewrittenText)}
          onCancel={cancelEditing}
          isSubmitting={isSubmitting}
        />
      )}
      {lastEvaluation && (
        <EvaluationCard
          evaluation={lastEvaluation}
          originalText={lastOriginalText ?? undefined}
          rewrittenText={lastRewrittenText ?? undefined}
        />
      )}
      {growthSummary && (
        <GrowthCard
          summary={growthSummary}
          hasHistory={hasHistory}
          isLoading={growthLoading}
        />
      )}
    </div>
  </div>
)}
```

### 3.5 IPC 通道（路径 A 使用）

| 通道 | 说明 |
|------|------|
| `diagnosis:update` | 后端推送诊断结果 → 渲染层设置 currentDiagnosis |
| `diagnosis:submitRewrite` | 提交修改 → 后端 AI 评估 → 返回 RewriteEvaluation |
| `diagnosis:getComparison` | 获取成长对比记录 → GrowthCard 数据源 |

### 3.6 诊断触发路径（两条并行）

| 路径 | 时机 | 机制 |
|------|------|------|
| **路径 A：DiagnosisAgent 主动分析** | 发送消息后，TeachingAgent 回复之前 | 单独 AI 调用（`diagnosis-agent-prompt-v1.md`），结果以 `🔍` 前缀流式推送 |
| **路径 B：从教学回复中解析** | TeachingAgent 回复完成后 | 解析 `---DIAGNOSIS_START---/END---` 标记，提取嵌入的诊断表 |

两条路径各自独立推送 `diagnosis:update` 事件，渲染层统一接收。

---

## 4. 路径 B：训练工坊（继承 V3.0，待实现）

### 4.1 中心面板双模式

```
┌─ AppShell ──────────────────────────────────────────────┐
│  Header                                                  │
├──────────┬───────────────────────────────┬───────────────┤
│          │                               │               │
│ Sidebar  │   中心区域 (flex:1)           │  RightPanel   │
│ (280px)  │                               │  (320px)      │
│          │   模式 A: 对话流 (默认)       │               │
│  会话列表│   模式 B: 训练工坊            │  诊断+趋势    │
│  训练按钮│                               │               │
└──────────┴───────────────────────────────┴───────────────┘
```

`centerMode: 'chat' | 'training'`
- 默认 `'chat'` — 正常对话流（含路径 A 的对话内训练）
- 切换到 `'training'` — 中心区域渲染 TrainingWorkshop 组件
- 切换回 `'chat'` — 对话流恢复，消息不丢失

### 4.2 双入口

**入口 1: 主动入口（左侧栏训练工坊按钮）**

```
┌─ AppSidebar ──────────────┐
│ + 新建会话                 │
│ 🎯 训练工坊  ← 新增按钮   │
│                            │
│ ── 最近会话 ──             │
│ 当前会话 *                 │
│ 旧会话 1                   │
└───────────────────────────┘
```

用户随时可点击，不需要等 AI 推荐。

**入口 2: 被动入口（对话流桥接卡片）**

在对话流中，AI 诊断后如果匹配到挑战模板，插入 TrainingBridgeCard：

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

点击"进入训练工坊" → centerMode 切换到 `'training'`。

### 4.3 训练工坊面板布局

三个区块，自上而下：

**区块一：你的常见问题（基于历史诊断）**

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
└───────────────────────────────────────────────────────┘
```

**区块二：推荐训练任务**

```
┌─ 推荐训练任务 ──────────────────────────────────┐
│                                                   │
│ ┌─ CH-P001 聚焦核心场景 ─────────────────────┐   │
│ │ structural | ~15min                         │   │
│ │ 你的开篇设定很宏大。挑出其中一个具体的场景， │   │
│ │ 把其他设定全部删掉，只留这个场景。           │   │
│ │ [P001] [A001]            [开始练习]         │   │
│ └─────────────────────────────────────────────┘   │
│                                                   │
│ ┌─ AI 个性化训练 ────────────────────────────┐   │
│ │ 基于你的错误模式，AI 可生成更精准的定制练习  │   │
│ │ （规划中）                                   │   │
│ └─────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────┘
```

**区块三：训练记录**

```
┌─ 近期训练记录 ──────────────────────────────┐
│ ✓ CH-P003 展示替代告知  已完成              │
│ ○ CH-P001 聚焦场景      进行中              │
│ — CH-P009 动机深掘      已跳过              │
└─────────────────────────────────────────────┘
```

### 4.4 训练进行中的交互

用户点击"开始练习"后，中心面板进入步骤式练习模式：

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
│ │ │ "整个大陆被分为五个王国..."                      │   │  │
│ │ └─────────────────────────────────────────────────┘   │  │
│ │                                                       │  │
│ │ ┌─ 写作区 ───────────────────────────────────────┐   │  │
│ │ │ 北方的冰之国，一间破旧的铁匠铺里...              │   │  │
│ │ └─────────────────────────────────────────────────┘   │  │
│ └───────────────────────────────────────────────────────┘  │
│                                                           │
│ [存草稿]                              [提交练习]           │
└───────────────────────────────────────────────────────────┘
```

提交后：
1. 后端 `training:complete` IPC → AI 评估
2. 自动切回 `centerMode='chat'`
3. 对话流中显示 AI 评估反馈

### 4.5 组件接口

#### TrainingWorkshop

```typescript
interface TrainingWorkshopProps {
  errorCards: ErrorCard[];
  recommendations: TrainingRecommendation[];
  activeTraining: ActiveTrainingSession | null;
  recentHistory: TrainingRecord[];
  onStartTraining: (challengeId: string) => void;
  onBackToChat: () => void;
}

interface ErrorCard {
  syndromeId: string;
  syndromeName: string;
  severity: SeverityLevel;
  diagnosisCount: number;
  lastQuote: string;
  lastDiagnosedAt: string;
  matchedChallengeId?: string;
}

interface ActiveTrainingSession {
  challengeId: string;
  challengeName: string;
  steps: TrainingStep[];
  currentStepIndex: number;
  originalQuote: string;
  constraint: string;
  userDraft: string;
}

interface TrainingStep {
  id: string;
  title: string;
  description: string;
  status: 'completed' | 'active' | 'pending';
}
```

#### TrainingBridgeCard

```typescript
interface TrainingBridgeCardProps {
  recommendation: TrainingRecommendation;
  onEnterWorkshop: (challengeId: string) => void;
  onDismiss: () => void;
}
```

### 4.6 训练工坊 Store

```typescript
interface TrainingStore {
  centerMode: CenterMode;
  errorCards: ErrorCard[];
  recommendations: TrainingRecommendation[];
  activeTraining: ActiveTrainingSession | null;
  history: TrainingRecord[];
  isLoading: boolean;

  enterWorkshop: () => void;
  backToChat: () => void;
  refreshFromDiagnosis: () => void;
  startTraining: (challengeId: string) => Promise<void>;
  updateDraft: (content: string) => void;
  submitStep: () => Promise<void>;
  skipTraining: () => Promise<void>;
  loadHistory: (sessionId: string) => Promise<void>;
}
```

### 4.7 IPC 通道（路径 B 使用）

| 通道 | 请求 | 响应 | 说明 |
|------|------|------|------|
| `training:recommend` | `{ sessionId, syndromeIds }` | `TrainingRecommendation[]` | 匹配挑战模板 |
| `training:assign` | `{ sessionId, challengeId, syndromeId }` | `TrainingRecord` | 分配训练 |
| `training:complete` | `{ trainingId, userResponse }` | `{ record, evaluation }` | 完成并获取评估 |
| `training:skip` | `{ trainingId }` | `TrainingRecord` | 跳过训练 |
| `training:getHistory` | `{ sessionId, limit? }` | `TrainingRecord[]` | 查询历史 |

---

## 5. 双路径的衔接

### 5.1 从路径 A 跳到路径 B

对话内训练（路径 A）完成后，如果 AI 评估发现"有更深层的结构性问题"，可以在 GrowthCard 下方追加：

```
┌─ 💡 更深层的练习 ──────────────────────────────────┐
│ 这个问题可能需要更系统的训练。训练工坊中有针对性的   │
│ 步骤式练习，想试试吗？                               │
│ [进入训练工坊]  [继续对话]                           │
└────────────────────────────────────────────────────┘
```

### 5.2 从路径 B 回到路径 A

训练工坊完成后切回对话，用户继续发文本，路径 A 正常触发。两条路径独立运作，不冲突。

### 5.3 数据共享

两条路径共享以下数据：
- **诊断历史**：`diag.store.history` — 训练工坊的错误卡片聚合来源
- **训练记录**：`training-record.service.ts` — 两条路径的训练完成/跳过都记录于此
- **能力画像**：`student-context.store` — 两条路径的评估结果都更新能力数据

---

## 6. 样式规范

遵循月下书房暖调水墨风：

### 6.1 对话内训练组件（路径 A）

| 元素 | 背景 | 边框 | 文字 |
|------|------|------|------|
| DiagnosisCard | `var(--bg-card)` | 严重度色左边框 | `var(--text-primary)` |
| EditPanel | `var(--accent-subtle)` | `var(--accent)` | `var(--text-primary)` |
| EvaluationCard | `white` | `var(--success)` 左边框 | `var(--text-primary)` |
| GrowthCard | `white` | `var(--border)` | `var(--text-primary)` |

### 6.2 训练工坊组件（路径 B）

| 元素 | 背景 | 边框 | 文字 |
|------|------|------|------|
| 训练工坊标题栏 | `var(--accent-subtle)` | `var(--accent)` | `var(--text-primary)` |
| 错误卡片 | `white` | 严重度色 | `var(--text-primary)` |
| 训练任务卡片 | `white` | teal/green | `var(--text-primary)` |
| 原始文本引用 | `coral-50` | `coral-200` 左侧竖条 | `var(--text-secondary)` |
| 挑战描述 | `teal-50` | `teal-200` | `teal-600` |
| 写作区 | `var(--bg-input)` | `var(--border)` | `var(--text-primary)` |
| 主按钮 | `teal-600` | none | `white` |
| 进度条填充 | `teal-600` | none | — |

图标（lucide-react）：
- 训练工坊入口：`Dumbbell`
- 错误卡片：`AlertTriangle`
- 训练任务：`Target`
- 步骤完成：`CheckCircle`
- 对话内编辑：`Pencil`
- 成长：`TrendingUp`

---

## 7. 涉及文件清单

### 7.1 路径 A（对话内训练，已完成）

| # | 文件 | 状态 | 说明 |
|---|------|:----:|------|
| 1 | `src/renderer/components/diagnosis/DiagnosisCard.tsx` | ✅ | 已添加 `onStartEditing` + "尝试修改"按钮 |
| 2 | `src/renderer/components/diagnosis/EditPanel.tsx` | ✅ | 已有，原始实现 |
| 3 | `src/renderer/components/diagnosis/EvaluationCard.tsx` | ✅ | 已有，原始实现 |
| 4 | `src/renderer/components/diagnosis/GrowthCard.tsx` | ✅ | 已有，原始实现 |
| 5 | `src/renderer/hooks/useDiagnosisFlow.ts` | ✅ | 已补全 lastRewrittenText/lastOriginalText |
| 6 | `src/renderer/App.tsx` | ✅ | 已接线 DiagnosisCard→EditPanel→EvaluationCard→GrowthCard |

### 7.2 路径 B（训练工坊，待实现）

| # | 文件 | 操作 | 说明 |
|---|------|:----:|------|
| 1 | `src/renderer/components/training/TrainingWorkshop.tsx` | 新增 | 训练工坊主面板 |
| 2 | `src/renderer/components/chat/TrainingBridgeCard.tsx` | 新增 | 对话流桥接卡片 |
| 3 | `src/renderer/components/training/TrainingHistoryBar.tsx` | 新增 | 训练历史栏 |
| 4 | `src/renderer/stores/training.store.ts` | 新增 | 训练状态管理（含 centerMode） |
| 5 | `src/renderer/components/layout/AppSidebar.tsx` | 修改 | 新增"训练工坊"按钮 |
| 6 | `src/renderer/App.tsx` | 修改 | sidebarPage→centerMode；TrainingWorkshop 条件渲染 |
| 7 | `src/renderer/shared/types.ts` | 修改 | 新增 CenterMode / ErrorCard / ActiveTrainingSession / TrainingStep |
| 8 | `src/main/ipc/training.handler.ts` | 新增 | 训练 IPC 通道 |
| 9 | `src/main/services/training-recommendation.service.ts` | 新增 | 根据诊断匹配挑战模板 |
| 10 | `src/main/index.ts` | 修改 | 注册 training handler |
| 11 | `src/renderer/stores/task.store.ts` | 删除 | 被 training.store.ts 替代 |

### 7.3 内容感知路由层（待实现）

| # | 文件 | 操作 | 说明 |
|---|------|:----:|------|
| 1 | `src/main/services/message-router.ts` | 重写 | 从 shouldRunDiagnosis 升级为 ContentAwareRouter |
| 2 | `src/main/services/content-classifier.ts` | 新增 | 内容类型分类（Phase 1: 规则引擎） |
| 3 | `src/main/ipc/chat.handler.ts` | 修改 | 接入 ContentAwareRouter 替代 MessageRouter.shouldRunDiagnosis |

---

## 8. 实现优先级

| 阶段 | 内容 | 优先级 | 说明 |
|------|------|:------:|------|
| **M-2** | 修改原文入口（路径 A） | ✅ 已完成 | DiagnosisCard→EditPanel→EvaluationCard→GrowthCard |
| **M-3** | AI 修改评估（路径 A） | ✅ 已完成 | submitRewrite IPC → RewriteEvaluation |
| **M-4** | 一句话成长记录（路径 A） | ✅ 已完成 | GrowthCard + diagnosis:getComparison |
| **下一步** | 内容感知路由层 | P0 | 解决诊断-训练强绑定问题，是训练入口可靠触发的前提 |
| **T-021** | 训练工坊（路径 B） | P1 | 中心面板模式切换 + 步骤式练习 |
| **T-022** | AI 个性化训练 | P2 | 基于用户错误模式实时生成定制练习（独立子系统） |

---

## 9. 开放问题

1. ~~**内容分类的准确度**~~ → **已决策：两阶段策略**
   - **Phase 1：规则引擎 + 置信度降级**（零额外 API 调用）
     - 规则引擎分类 → confidence ≥ 0.7 直接路由 → confidence < 0.7 降级为 `clarify`
     - 拿不准就多问一句，宁可不路由也不乱弹诊断
     - 规则引擎信号：代词密度/动词密度/对话引号 → 叙事；"是/分为/对应"+术语堆砌+陈述句 → 世界观
     - 边界 case（叙事嵌设定）：规则引擎通常给低置信度，降级为 clarify
     - 先上线收集低置信度 case 数据，为 Phase 2 提供训练样本
   - **Phase 2：AI 辅助分类**（当规则引擎不够用时）
     - 选项 A：小模型本地推理 / 低成本 API 做二次分类
     - 选项 B：合并到 TeachingAgent system prompt（"先判断内容类型再回复"），不额外加 API 调用
     - 触发条件：Phase 1 运行后，低置信度 case 占比 > 20% 或用户投诉分类错误
2. ~~**错误卡片的"最近引用"获取**~~ → **已决策：复活 Evidence Level 1 + 用户文档归档**
   - **历史脉络**：SPEC_Evidence_V1.md 设计了 Level 1 文本证据（含 `source.novelId/chapterId/paragraphIndex` + `content` 原文片段），第一性原理审计 V1.1 判定"保留 Level 1（原文引用）"但 MVP 未实现。当前 `SyndromeResult.evidence` 注释为"用户原文证据片段"但实际填的是 AI 描述而非用户原文。
   - **用户原始构想（V2 阶段）**：用户发内容 → 系统归档为"用户文档" → 诊断表引用该文档并标注错误位置。这比简单的"附带文本片段"更完整——用户输入有独立存在感，不只是诊断的附属。
   - **决策：两步走**
     - **Step 1：DiagnosisEntry 增加 sourceSnippets**（MVP 补丁）
       - `DiagnosisEntry` 新增 `sourceSnippets: string[]`，与 `SyndromeResult.evidence` 一一对应
       - 后端诊断时，从触发诊断的用户消息中提取对应原文片段填入
       - 修复当前 `evidence` 字段语义不一致的问题（注释说"原文"但实际是 AI 描述）
     - **Step 2：用户文档归档系统**（V2+）
       - 用户发送的文本自动归档为 UserDocument（带时间戳、内容类型标签、会话关联）
       - DiagnosisEntry 通过 `sourceDocumentId` + `sourceOffset` 引用 UserDocument
       - 支持文档级别的归类和检索（"这是我上个月发的世界观设定"）
       - 为 Level 4 对比证据（改前 vs 改后）提供数据基础
       - 复活 SPEC_Evidence_V1.md 的 Level 1 机制，但简化为：UserDocument + sourceSnippets，不搞四级分层
3. ~~**步骤拆解的数据源**~~ → **已决策：方案 c——通用步骤框架 + mode 定制内容**
   - **问题**：`challenge-templates.json` 只有 `mode` 字段没有 `steps`，但 V4.0 设计了步骤式练习
   - **分析**：步骤不是完全缺失——`challenge`（任务描述）+ `constraint`（约束条件）+ `mode`（交互模式）已经压缩在一个挑战里，只需展开为通用三步流程
   - **决策：通用三步框架 + mode 控制交互细节**
     - Step 1（review）：阅读原始文本——通用，所有 mode 相同
     - Step 2（rewrite）：约束改写——`title` 来自 `template.challenge`，`description` 来自 `template.constraint`，交互差异由 `mode` 控制
     - Step 3（submit）：提交评估——通用，所有 mode 相同
   - **mode 对 Step 2 的交互影响**（前端层面）：
     - `narrow_focus`：原文全展示，用户选择保留哪部分
     - `show_dont_tell`：写作区禁用情绪词（前端校验）
     - `perspective_lock`：只允许写主角视角，出现"他知道她心里想"时标红
     - `reading_task`：Step 2 变成读书笔记输入而非改写
     - `deepen_motivation`：写作区提示"写出内心恐惧"
     - `rewrite_constrained`：禁止说明性文字
     - `force_action`：要求前三段内有主动选择
   - **好处**：零数据膨胀，不改 JSON；模板自动获得三步流程；未来需要更多步骤时再给 JSON 加 `steps` 字段覆盖默认框架
4. ~~**训练草稿持久化**~~ → **已决策：内存暂存 + localStorage 兜底，分阶段实现**
   - **Phase 1：内存暂存（零额外代码）**
     - `ActiveTrainingSession.userDraft` 已有字段，`centerMode` 从 `training` 切回 `chat` 时不重置 state
     - 切回来草稿还在，只是切换不清理
   - **Phase 2：localStorage 兜底**
     - 组件 unmount 前（页面刷新等），把 `userDraft` 写入 localStorage，key = `draft:${sessionId}:${challengeId}`
     - mount 时检查是否有未提交草稿，提示用户恢复
     - 防止意外丢失
   - **不做后端存储**——训练草稿是临时性的，不是用户作品；完成后才走 `training:complete` IPC 正式存档
5. ~~**路径 A→路径 B 的过渡时机**~~ → **已决策：三层推荐逻辑，只推荐不自动跳转**
   - **判断信号**：
     - `RewriteEvaluation.improvement`：'明显改善' / '略有改善' / '无明显改善'
     - `SyndromeResult.severity`：'fatal' / 'structural' / 'surface'
     - `TrainingRecord.effectiveness`：0-1 数值
     - 历史诊断聚合：同一 syndromeId 重复出现次数
   - **三层推荐逻辑**：
     - `improvement === '明显改善'` → **不推荐**（已经会了，别打扰成就感）
     - `improvement === '略有改善'` 且 `severity ∈ {fatal, structural}` → **推荐**（"有进步但根子还没动，想系统练一下吗？"）
     - `improvement === '无明显改善'` → **强烈推荐**（"这个问题比较顽固，步骤式练习可能更有效"）
     - 同一 `syndromeId` 历史出现 ≥ 3 次 → **无论 improvement 都推荐**（"这个老毛病又犯了，要不要试试专项训练？"）
   - **关键原则**：只推荐不自动跳转——GrowthCard 底部出现"更深层的练习"卡片，用户自己选进不进
6. ~~**新用户引导流程细节**~~ → **已决策：拆出为独立设计文档**
   - onboarding 路由目标涉及独立子系统：教学状态机新增状态、新 UI 组件、对话脚本设计
   - 需要解决的问题：月笙不了解用户（写作类型/水平/目标）、用户不了解月笙（能帮什么/怎么用）、内容路由没有基线
   - 大致流程框架：了解写作目标 → 设定基线（发一段文字，不做诊断而是理解风格水平） → 推荐起步路径
   - **独立设计文档待创建**：`onboarding-flow-design_V1.0.md`
   - **任务链排序**：排在 T-021 之后，作为独立任务 T-023

---

## 10. 与旧版方案的差异

| 项目 | V2.0 | V3.0 | **V4.0** |
|------|------|------|---------|
| 对话内训练 | 不支持 | 不支持 | **✅ 路径 A，已实现** |
| 训练工坊 | 左侧栏小窗口 | 中心面板切换 | **中心面板切换（继承 V3.0）** |
| 主动训练 | 不支持 | 左侧栏按钮 | **左侧栏按钮（继承 V3.0）** |
| 被动推荐 | 左侧栏内展开 | 桥接卡片 | **路径 A（对话内）+ 桥接卡片（跳转工坊）** |
| 内容路由 | 无 | 无 | **✅ 内容感知路由层** |
| 新手引导 | 无 | 无 | **✅ onboarding 路由目标** |
| 世界观/碎片处理 | 统一诊断 | 统一诊断 | **按内容类型分别处理** |
| AI 个性化 | 无 | 规划中 | **规划中（独立子系统 T-022）** |
