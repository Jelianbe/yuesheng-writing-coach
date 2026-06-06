# 新用户引导流程设计 V1.0

> **背景**：V4.0 开放问题 #6 拆出。内容感知路由层设计了 `onboarding` 路由目标，但具体流程需要独立设计。
>
> **问题定义**：
> 1. **月笙不了解用户**——不知道ta写什么类型、什么水平、什么目标
> 2. **用户不了解月笙**——不知道这个工具能帮什么、怎么用
> 3. **内容路由没有基线**——不知道什么算"叙事"什么算"世界观"，因为还没见过用户的作品模式
>
> **设计文档**：本文档
> **关联任务**：T-019（从零构建引导流程）

---

## 一、流程总览

### 核心原则

1. **不替用户决定**——引导是提问和建议，不是替用户填答案
2. **最小化负担**——3 步以内完成，不让用户觉得在填表格
3. **边聊边引导**——不是死板的表单，是对话式交互
4. **成果可被诊断使用**——收集的信息存入 `AuthorProfile.initialBaseline`

### 流程图

```
用户首次进入（无历史会话）
    │
    ├─ Step 1：互相认识（双向介绍）
    │   ├─ 月笙自我介绍（我是谁，能帮你什么）
    │   └─ 问用户：你主要写什么类型？
    │      选项：玄幻/都市/科幻/现实/历史/其他/说不清
    │
    ├─ Step 2：设定基线（理解用户水平）
    │   ├─ "能不能发一段你最近写的文字？我帮你看看现在的情况"
    │   ├─ 用户发文本 → 内容路由判定为 onboarding
    │   ├─ 不做诊断，而是分析并回复：
    │   │   "我看了一下，你的文字特点是____。目前最明显的优点是____，可以提升的是____。"
    │   └─ 追问："你现在最想提升哪方面？"
    │      选项：角色塑造/情节节奏/世界观构建/文字表达/说不清
    │
    └─ Step 3：推荐起步路径
        ├─ 根据类型+目标，推荐第一个诊断/训练
        ├─ "我觉得你可以先从____开始，要不要试试？"
        └─ 用户确认 → 进入正常对话模式（teaching_status = 'IDLE'）
```

---

## 二、详细交互设计

### Step 1：互相认识

**交互形式**：对话式，非表单

```
┌─ 月笙（AI）───────────────────────┐
│ 你好！我是月笙，你的写作教练。      │
│                                         │
│ 我不是帮你写作文的工具，            │
│ 而是帮你**成为更好的写作者**。        │
│                                         │
│ 我会读你的文字，指出可以提升的地方， │
│ 但不会替你改写——因为**成长属于你**。 │
│                                         │
│ 先认识一下：你主要写什么类型？       │
│                                         │
│ [玄幻/都市] [科幻/现实]             │
│ [历史/其他] [说不清]                │
└───────────────────────────────────────┘
```

**数据记录**：

```typescript
// 存入 AuthorProfile.initialBaseline
interface OnboardingBaseline {
  writingType: 'fantasy' | 'urban' | 'sci-fi' | 'realistic' | 'historical' | 'other' | 'unknown';
  capturedAt: number;
}
```

**用户输入"说不清"时的降级**：

```
月笙："没关系～随便聊聊天也行。你最近有在写的东西吗？"
    → 引导用户发一段文字（进入 Step 2）
```

---

### Step 2：设定基线

**交互形式**：引导用户发一段文字，AI 分析后回复

```
┌─ 月笙（AI）───────────────────────┐
│ 好的，玄幻小说！我已经流口水了 🤤   │
│                                         │
│ 为了更好帮你，能不能发一段            │
│ 你最近写的文字？不用很长，            │
│ 三五句话也行。                       │
│                                         │
│ 我会看看你现在的写作特点，            │
│ 这样后面给你的建议会更准。             │
└───────────────────────────────────────┘

（用户输入区）

[发送] [跳过，直接开始]
```

**用户点"跳过"时的降级**：

```
月笙："好的，那我们直接开始。后面你发文字的时候我再慢慢了解你。"
    → 直接进入 Step 3，使用通用推荐
```

**用户发送文本后**：

```
（内容路由判定：onboarding → 不触发诊断）

┌─ 月笙（AI）───────────────────────┐
│ 我看了一下，你的文字有几个特点：       │
│                                         │
│ ✅ 画面感不错，场景描写很细腻          │
│ ✅ 对话自然，不僵硬                   │
│ ⚠️ 有些地方会"告知"情绪而不是"展示"  │
│    （比如"他很愤怒"而不是"他指节收紧"）│
│                                         │
│ 你现在最想提升哪方面？                │
│                                         │
│ [角色塑造] [情节节奏]                 │
│ [世界观构建] [文字表达]               │
│ [随便，你推荐]                       │
└───────────────────────────────────────┘
```

**数据记录**：

```typescript
interface OnboardingBaseline {
  writingType: string;
  sampleText?: string;          // 用户发的原文
  analysisSummary: string;       // AI 的回复（优点+可提升点）
  improvementGoal: string;       // 用户选择的目标
  capturedAt: number;
}
```

**特殊处理**：如果用户发的文本是世界观设定（内容路由判定为 `worldbuild_guide`），月笙的回复调整为：

```
月笙："我注意到你发的是世界观设定～这个我后面可以帮你梳理。
      不过我更擅长帮你改叙事文字。你有没有一段叙事文字（有角色、有场景）可以发给我看看？"
    → 引导用户发叙事文本
```

---

### Step 3：推荐起步路径

**交互形式**：基于前两步收集的信息，推荐具体行动

```
┌─ 月笙（AI）───────────────────────┐
│ 好的，想提升文字表达！                │
│                                         │
│ 根据你玄幻小说的特点，               │
│ 我觉得你可以先从一个具体的诊断开始：   │
│                                         │
│ 📍 **诊断：情绪展示 vs 告知**         │
│    "他感到害怕" → "他后退半步"       │
│                                         │
│ [开始诊断] [我自己有想问的]          │
└───────────────────────────────────────┘
```

**推荐逻辑**：

| 用户类型 | 改进目标 | 推荐第一个行动 |
|---------|---------|--------------|
| 玄幻/科幻 | 文字表达 | 诊断：情绪展示 vs 告知 |
| 玄幻/科幻 | 世界观构建 | 诊断：世界观膨胀 |
| 都市/现实 | 角色塑造 | 诊断：角色动机缺失 |
| 都市/现实 | 情节节奏 | 诊断：旁白介入过多 |
| 历史 | 文字表达 | 诊断：时代感错位 |
| 说不清 | 任意 | 诊断：自由文本分析 |

**用户点"开始诊断"后**：

```
→ teaching_status 设为 'ANALYZING'
→ 告诉用户："好的，发一段文字给我吧，我帮你看看～"
→ 等待用户发文本 → 触发诊断
```

**用户点"我自己有想问的"后**：

```
→ teaching_status 设为 'IDLE'
→ 告诉用户："好的，那我们随便聊～你有什么想问的或者想让我看的？"
→ 进入正常对话模式
```

---

## 三、数据流设计

### 新增/修改的接口

**1. `AuthorProfile.initialBaseline` 字段（新增）**

```typescript
interface AuthorProfile {
  // ...现有字段
  initialBaseline?: OnboardingBaseline;  // 新用户引导收集的信息
}
```

**2. 内容路由层新增 `onboarding` 目标**

```typescript
// ContentAwareRouter 的路由决策
interface RouteDecision {
  target: 'diagnosis' | 'worldbuild_guide' | 'clarify' | 'teaching_chat' | 'onboarding';
  confidence: number;
  reason: string;
}

// onboarding 路由不触发诊断，只做分析和引导
```

**3. 会话状态新增 `onboarding` 模式**

```typescript
// 在 useChatStore 或类似状态里
interface ChatState {
  mode: 'normal' | 'onboarding';
  onboardingStep: 0 | 1 | 2 | 3;  // 0=未开始, 1=Step1, 2=Step2, 3=Step3
  onboardingData: OnboardingBaseline | null;
}
```

### IPC 通道（无需新增，复用现有）

- `chat:sendMessage` —— 发送引导消息
- `chat:receiveMessage` —— 接收用户回复
- `profile:update` —— 更新 `AuthorProfile.initialBaseline`

---

## 四、前端组件设计

### 组件结构

```
OnboardingFlow（新用户引导主组件）
├── OnboardingStep1（互相认识）
│   ├── 月笙自我介绍（纯展示，固定文本）
│   └── 写作类型选择按钮（OnboardingOptionButton）
│
├── OnboardingStep2（设定基线）
│   ├── 引导文案（固定文本）
│   ├── 用户输入区（复用现有 MessageInput）
│   └── 跳过按钮
│
└── OnboardingStep3（推荐起步路径）
    ├── AI 分析回复（展示 analysisSummary）
    ├── 改进目标选择按钮
    └── 推荐行动卡片（OnboardingRecommendationCard）
```

### 关键组件接口

**OnboardingFlow.tsx**

```typescript
interface OnboardingFlowProps {
  onComplete: (baseline: OnboardingBaseline) => void;  // 引导完成回调
  onSkip: () => void;                                   // 用户跳过引导
}

interface OnboardingFlowState {
  step: 0 | 1 | 2 | 3;
  baseline: Partial<OnboardingBaseline>;
  isAnalyzing: boolean;                                   // Step 2 AI 分析进行中
}
```

**OnboardingOptionButton.tsx**

```typescript
interface OnboardingOptionButtonProps {
  label: string;
  value: string;
  icon?: string;            // 可选图标
  onClick: (value: string) => void;
}
```

**OnboardingRecommendationCard.tsx**

```typescript
interface OnboardingRecommendationCardProps {
  title: string;
  description: string;
  actionLabel: string;       // 按钮文字（"开始诊断" / "直接进入对话"）
  onAction: () => void;
}
```

---

## 五、后端服务设计

### 修改的文件

| 文件 | 改动内容 |
|------|---------|
| `src/main/services/session.service.ts` | 新增 `isNewUser(): boolean` 方法（检查是否有历史会话） |
| `src/main/services/author-profile.service.ts` | 新增 `updateBaseline(sessionId, baseline)` 方法 |
| `src/main/ipc/chat.handler.ts` | 新增 `onboarding` 路由处理（不触发诊断，只做分析） |
| `src/main/services/message-router.ts` | 新增 `onboarding` 路由目标（`ContentAwareRouter` 里实现） |

### 新增 Prompt 文件

**`resources/prompts/onboarding-analysis-prompt.md`**

```markdown
# 新用户引导分析 Prompt

你正在给一个新用户做写作基线分析。用户发来了一段文字，请你：

1. 指出 2 个优点（具体、有说服力）
2. 指出 1-2 个可以提升的点（温和、不打击）
3. 用教练口吻，不说教，不替用户决定

## 输出格式

```
✅ [优点1]
✅ [优点2]
⚠️ [可提升点1]
⚠️ [可提升点2（可选）]

你现在最想提升哪方面？
[等待用户选择]
```

## 注意事项

- 不触发正式诊断（不用 DiagnosisAgent）
- 不生成 DiagnosisEntry
- 只是暖身分析和引导
```

---

## 六、与内容路由层的集成

### ContentAwareRouter 扩展

```typescript
// src/main/services/content-aware-router.ts（新增文件）

export function routeContent(input: UserInput): RouteDecision {
  // ...现有路由逻辑

  // 新增：新用户检测
  if (isNewUser() && !hasBaseline()) {
    return {
      target: 'onboarding',
      confidence: 1.0,
      reason: '新用户，尚未完成引导流程',
    };
  }

  // ...其他路由逻辑
}
```

### 路由目标处理

| 路由目标 | 处理方式 |
|---------|---------|
| `onboarding` | 不触发 DiagnosisAgent，调用 OnboardingAnalyzer（轻量级分析） |
| `diagnosis` | 触发 DiagnosisAgent（现有逻辑） |
| `worldbuild_guide` | 触发世界观梳理引导（不诊断） |
| `clarify` | 触发澄清对话（不诊断） |
| `teaching_chat` | 正常教学对话（不诊断） |

---

## 七、边界 Case 处理

| Case | 处理方式 |
|------|---------|
| 用户中途退出（关闭应用） | `onboardingStep` 和 `onboardingData` 存入 localStorage，下次回来继续 |
| 用户点"跳过引导" | 直接设置 `teaching_status = 'IDLE'`，进入正常对话 |
| Step 2 用户发的是世界观设定 | 引导用户改发叙事文本（见 Step 2 特殊处理） |
| Step 2 AI 分析失败（API 错误） | 降级为通用回复："我看了一下你的文字，挺有潜力的！"，进入 Step 3 |
| 用户所有问题都选"说不清" | 使用通用推荐（诊断：自由文本分析） |

---

## 八、实施优先级

### Phase 1（MVP 必须）

- [ ] Step 1 实现（互相认识 + 写作类型选择）
- [ ] Step 2 实现（引导发文字 + AI 分析回复）
- [ ] Step 3 实现（推荐起步路径 + 进入正常对话）
- [ ] `OnboardingFlow.tsx` 主组件
- [ ] `ContentAwareRouter` 新增 `onboarding` 路由
- [ ] `isNewUser()` 检测逻辑

### Phase 2（体验优化）

- [ ] 中途退出恢复（localStorage 持久化）
- [ ] Step 2 特殊处理（用户发世界观设定时的引导）
- [ ] AI 分析失败降级
- [ ] 推荐逻辑细化（基于更多维度的匹配）

### Phase 3（数据驱动优化）

- [ ] 收集用户引导完成率数据
- [ ] A/B 测试不同推荐策略
- [ ] 根据数据优化引导流程

---

## 九、与现有任务的关联

| 关联任务 | 关联性 |
|---------|-------|
| T-021（训练入口与工坊） | 引导完成后推荐的"第一个诊断"可能衔接训练入口 |
| T-014（动态上下文装载） | 引导收集的信息（baseline）需要被上下文装载使用 |
| T-013（能力成长可视化） | 引导建立的 baseline 是成长可视化的起点（"从哪开始"） |

---

**文档版本**：V1.0（2026-06-05）  
**作者**：月笙如歌 + AI 协作  
**状态**：待评审  
**下一步**：提交给用户评审 → 创建 T-019 实施任务（如需要）
