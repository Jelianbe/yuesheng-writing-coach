# 训练入口 UI 设计方案 V2.0

> **状态**: 提案 | **日期**: 2026-06-05  
> **设计依据**: T-021 任务文档 + 现有代码分析 + 用户参考设计图  
> **核心变更**: 训练入口从右侧栏迁移至左侧栏训练窗

## 1. 设计决策记录

### 1.1 训练入口位置：左侧栏 > 右侧栏

| 维度 | 左侧栏训练窗 | 右侧栏训练入口 |
|------|-------------|--------------|
| 语境连贯性 | 强——训练是对话的延伸 | 弱——视线离开对话流 |
| 空间充裕度 | 适中（280px，需可折叠） | 充裕（320px） |
| 信息密度 | 低——只放当前训练 | 高——已有诊断+进度+趋势 |
| 教练感 | 强——"边聊边练" | 弱——"去看那边练" |
| 用户心智 | "我要做什么"（行动层） | "我的问题是什么"（观察层） |

**结论**: 采用**左侧栏训练窗**方案，右侧栏专注于诊断和趋势观察。

### 1.2 展示模式：可折叠小窗口 > 独立界面

| 维度 | 可折叠小窗口 | 独立界面 |
|------|------------|---------|
| 教练哲学一致性 | 高——教练在对话中引导 | 低——"你去那边练" |
| 上下文连续性 | 高——始终看到对话流 | 低——切页丢失上下文 |
| 空间弹性 | 高——三态折叠适应空间 | 低——固定占位 |
| 渐进式展开 | 支持——折叠→预览→激活 | 不支持 |

**结论**: 采用**可折叠小窗口**模式，三态交互（折叠态→预览态→激活态）。

---

## 2. 三层职责分离

| 区域 | 职责层 | 用户心智 | 包含组件 |
|------|--------|---------|---------|
| **左侧栏上方** | 行动层 | "我要做什么" | TrainingWorkspace（训练窗）+ 会话切换 |
| **对话流** | 触发层 | "教练建议我练什么" | TrainingCard（桥接卡片）+ AI自然推荐 |
| **右侧栏** | 观察层 | "我的问题是什么" | 对话焦点 + 教学进度 + 诊断发现 + 能力成长 |

---

## 3. 组件架构

### 3.1 新增组件

#### `TrainingWorkspace.tsx`（左侧栏训练工作台）

位置：`src/renderer/components/training/TrainingWorkspace.tsx`

```typescript
interface TrainingWorkspaceProps {
  /** 当前推荐的训练列表（来自 TrainingRecommendationService） */
  recommendations: TrainingRecommendation[];
  /** 当前活跃的训练记录 */
  activeTraining: TrainingRecord | null;
  /** 训练工作台状态 */
  workspaceState: 'collapsed' | 'preview' | 'active';
  /** 开始训练 */
  onStartTraining: (recommendationId: string) => void;
  /** 提交训练结果 */
  onSubmitResponse: (trainingId: string, response: string) => void;
  /** 跳过训练 */
  onSkipTraining: (trainingId: string) => void;
  /** 折叠/展开训练窗 */
  onToggleWorkspace: () => void;
  /** 训练历史记录（最近3条） */
  recentHistory: TrainingRecord[];
}
```

**三态设计**:

- **折叠态**（collapsed）: 训练窗区域完全不渲染，会话列表占满左侧栏
- **预览态**（preview）: 紧凑卡片——训练名称 + 针对病症 + 预估时长 + "开始练习"按钮，高度约 80px
- **激活态**（active）: 完整工作台——挑战描述 + 输入区 + 提交/跳过按钮，高度约 200-260px

**空间策略**:
- 训练窗在左侧栏顶部，会话列表在其下方
- 预览态时训练窗高 80px，会话列表失去约 2 行空间（可接受）
- 激活态时训练窗高 200px+，会话列表压缩但仍有滚动空间
- 折叠态时训练窗高度为 0，无空间损失

#### `TrainingCard.tsx`（聊天流桥接卡片）

位置：`src/renderer/components/chat/TrainingCard.tsx`

```typescript
interface TrainingCardProps {
  /** 推荐的训练信息 */
  recommendation: TrainingRecommendation;
  /** 点击"开始练习"后的回调 —— 触发左侧栏训练窗打开 */
  onStart: () => void;
  /** 点击"下次再说" */
  onDismiss: () => void;
}
```

**桥接设计**: TrainingCard 不在聊天流中直接展开练习，而是作为"桥接"——点击"在左侧打开"按钮后，左侧栏训练窗进入预览/激活态。这保证了：
1. 训练始终在左侧栏完成，用户体验一致
2. 对话流不被长表单打断
3. 用户可以一边看对话，一边做练习

#### `TrainingHistory.tsx`（训练历史迷你列表）

位置：`src/renderer/components/training/TrainingHistory.tsx`

```typescript
interface TrainingHistoryProps {
  /** 最近训练记录 */
  records: TrainingRecord[];
  /** 最大显示条数 */
  maxItems?: number;
}
```

**位置**: 嵌入在 TrainingWorkspace 激活态底部，展示最近 3 条训练记录。

### 3.2 新增类型

在 `src/renderer/shared/types.ts` 中新增：

```typescript
/** 训练推荐 */
export interface TrainingRecommendation {
  /** 推荐ID */
  id: string;
  /** 匹配的挑战模板ID（如 CH-P003） */
  challengeId: string;
  /** 匹配的病症ID */
  syndromeId: string;
  /** 病症名称 */
  syndromeName: string;
  /** 挑战描述（来自 challenge-templates.json） */
  challenge: string;
  /** 约束条件 */
  constraint: string;
  /** 难度等级 */
  difficulty: 'surface' | 'structural' | 'fatal';
  /** 预估时长 */
  estimatedMinutes: number;
  /** 推荐来源（诊断触发 / AI推荐 / 反思过关） */
  source: 'diagnosis' | 'ai_suggestion' | 'reflection_unlock';
}

/** 训练工作台状态 */
export type TrainingWorkspaceState = 'collapsed' | 'preview' | 'active';
```

### 3.3 新增 Store

`src/renderer/stores/training.store.ts`:

```typescript
interface TrainingStore {
  /** 当前推荐的训练 */
  recommendations: TrainingRecommendation[];
  /** 当前活跃训练记录 */
  activeTraining: TrainingRecord | null;
  /** 工作台状态 */
  workspaceState: TrainingWorkspaceState;
  /** 训练历史 */
  history: TrainingRecord[];
  /** 加载状态 */
  isLoading: boolean;

  /** 从诊断结果触发推荐 */
  triggerFromDiagnosis: (syndromes: SyndromeResult[]) => void;
  /** 从AI建议触发推荐 */
  triggerFromAISuggestion: (syndromeId: string) => void;
  /** 开始训练 */
  startTraining: (recommendationId: string) => Promise<void>;
  /** 提交训练结果 */
  submitResponse: (response: string) => Promise<void>;
  /** 跳过训练 */
  skipTraining: () => Promise<void>;
  /** 切换工作台状态 */
  toggleWorkspace: () => void;
  /** 加载训练历史 */
  loadHistory: (sessionId: string) => Promise<void>;
}
```

### 3.4 新增 IPC 通道

在 `src/shared/constants.ts` 和 `src/main/ipc/training.handler.ts` 中新增：

| 通道 | 请求类型 | 响应类型 | 说明 |
|------|---------|---------|------|
| `training:recommend` | `{ sessionId, syndromeIds }` | `TrainingRecommendation[]` | 根据病症ID匹配挑战模板 |
| `training:assign` | `{ sessionId, challengeId, syndromeId }` | `TrainingRecord` | 分配训练任务 |
| `training:complete` | `{ trainingId, userResponse }` | `{ record: TrainingRecord, evaluation: RewriteEvaluation }` | 完成训练并获取AI评估 |
| `training:skip` | `{ trainingId }` | `TrainingRecord` | 跳过训练 |
| `training:getHistory` | `{ sessionId, limit? }` | `TrainingRecord[]` | 查询训练历史 |

### 3.5 新增后端服务

`src/main/services/training-recommendation.service.ts`:

```typescript
class TrainingRecommendationService {
  /**
   * 根据病症ID列表匹配 challenge-templates.json 中的模板
   * 优先级：fatal > structural > surface
   * 同 tier 内按严重度排序
   */
  recommend(syndromeIds: string[]): TrainingRecommendation[];
}
```

---

## 4. 现有文件修改清单

### 4.1 需要修改的文件

| # | 文件 | 修改内容 | 影响范围 |
|---|------|---------|---------|
| 1 | `src/renderer/App.tsx` | 接入 training store；将 TrainingWorkspace 注入 AppSidebar；TrainingCard 嵌入聊天流 | 高 |
| 2 | `src/renderer/components/layout/AppSidebar.tsx` | 新增 TrainingWorkspace 插槽（children 或专用 prop）；调整 flex 布局适应训练窗空间 | 高 |
| 3 | `src/renderer/components/layout/AppShell.tsx` | 无需修改（已通过 children 传递） | 无 |
| 4 | `src/renderer/components/panels/RightPanel.tsx` | 移除训练相关入口（T-021 原计划的"试试练习"按钮改为跳转到左侧栏）；右侧栏纯观察层 | 中 |
| 5 | `src/renderer/shared/types.ts` | 新增 TrainingRecommendation / TrainingWorkspaceState 类型 | 低 |
| 6 | `src/main/index.ts` | 注册 training IPC handler | 低 |
| 7 | `docs/tasks/T-021-training-entry.md` | 更新设计方案和文件清单 | 文档 |
| 8 | `docs/tasks/TASK-CHAIN.md` | 更新组件架构描述 | 文档 |

### 4.2 AppSidebar.tsx 改造细节

当前 AppSidebar 结构：
```
AppSidebar
├── Toggle button
├── Header (新建会话按钮)
├── Section label ("最近会话")
└── Session list (flex:1, overflowY:auto)
```

改造后结构：
```
AppSidebar
├── Toggle button
├── Header (新建会话按钮)
├── TrainingWorkspace（新增，条件渲染）
│   ├── 预览态：紧凑训练卡片（~80px）
│   ├── 激活态：完整练习界面（~200px）
│   └── 折叠态：不渲染（0px）
├── Section label ("最近会话")
└── Session list (flex:1, overflowY:auto)
```

关键修改点：
1. 新增 `trainingWorkspace` prop（ReactNode）
2. 在 "最近会话" 标签之前插入 TrainingWorkspace
3. Session list 的 `flex: 1` 保持不变，训练窗挤压的是可视空间

### 4.3 App.tsx 改造细节

当前 App.tsx 中与训练相关的逻辑：
- 无（training 完全未接线）

需要新增：
1. `useTrainingStore` 导入和使用
2. `buildTrainingRecommendations` 函数：从 currentDiagnosis.syndromes 构建 TrainingRecommendation[]
3. `TrainingWorkspace` 组件实例化，作为 AppSidebar 的子组件
4. `TrainingCard` 在聊天流中的条件渲染（诊断卡片后）
5. IPC 事件监听：`training:recommended` / `training:completed`

### 4.4 RightPanel.tsx 改造细节

当前 RightPanel 包含四个区块：
1. 当前对话焦点
2. 教学进度
3. 诊断发现
4. 能力成长

T-021 原计划在诊断发现区块中为每个症候添加"试试练习"按钮。现在改为：
- 诊断发现区块的症候芯片保持原样（只显示名称+严重度+状态）
- 不添加"试试练习"按钮（训练入口在左侧栏）
- 可选：在诊断区块底部添加一行小字提示："有匹配的练习，查看左侧栏"

---

## 5. 交互流程

### 5.1 诊断触发训练

```
用户发送写作内容
  → 后端诊断引擎返回 DiagnosisEntry
  → 前端接收 DIAGNOSIS_UPDATE 事件
  → TrainingStore.triggerFromDiagnosis(syndromes)
  → 后端 training:recommend 匹配挑战模板
  → 前端更新 recommendations
  → TrainingWorkspace 从 collapsed → preview
  → 对话流中插入 TrainingCard（桥接）
```

### 5.2 用户开始训练

```
用户点击 TrainingCard "在左侧打开"
  或用户点击 TrainingWorkspace 预览态 "开始练习"
  → TrainingStore.startTraining(recommendationId)
  → 后端 training:assign 分配训练记录
  → TrainingWorkspace 从 preview → active
  → 用户在左侧栏看到挑战描述 + 输入区
```

### 5.3 用户完成训练

```
用户在训练窗输入区写修改
  → 点击"提交"
  → TrainingStore.submitResponse(response)
  → 后端 training:complete 记录结果 + AI 评估
  → 对话流中显示 AI 评估反馈
  → TrainingWorkspace 从 active → collapsed
  → 更新能力画像 / 教学状态
```

### 5.4 优雅降级

- 无诊断 → 无推荐 → TrainingWorkspace 保持 collapsed
- 诊断但无匹配模板 → 不显示训练入口
- 用户跳过训练 → 记录为 skipped → TrainingWorkspace 回到 collapsed

---

## 6. 样式规范

### 6.1 训练窗配色

遵循月下书房暖调水墨风：

| 元素 | 背景 | 边框 | 文字 |
|------|------|------|------|
| 训练窗容器 | `var(--accent-subtle)` #F5EAE8 | `var(--accent)` #C0766E 1px | `var(--text-primary)` #3D3229 |
| 挑战描述 | `var(--bg-card)` #FFFFFFF0 | `var(--border)` #E6DDD0 | `var(--text-secondary)` #7A6B5D |
| 输入区 | `var(--bg-input)` #FFFFFF | `var(--border)` #E6DDD0 focus: accent | `var(--text-primary)` #3D3229 |
| 主按钮 | `var(--accent)` #C0766E | none | `var(--text-on-accent)` #FFFFFF |
| 次按钮 | transparent | `var(--accent)` #C0766E | `var(--accent)` #C0766E |
| 进度条 | `var(--border-light)` #F0EAE0 (bg) | none | — |
| 进度条填充 | `var(--success)` #7A9E7E | none | — |

### 6.2 训练窗尺寸

| 状态 | 高度 | 宽度 | 过渡 |
|------|------|------|------|
| collapsed | 0px | 100% | 无 |
| preview | 80px | 100% | 400ms cubic-bezier(0.34, 1.56, 0.64, 1) |
| active | 200-260px | 100% | 400ms cubic-bezier(0.34, 1.56, 0.64, 1) |

### 6.3 训练窗图标

使用 lucide-react 图标库（与现有代码一致）：
- 训练窗标题：`Dumbbell`（与 TasksPage 一致）
- 开始按钮：`Play`
- 提交按钮：`Send`
- 跳过按钮：`SkipForward`
- 折叠按钮：`ChevronUp`

---

## 7. 与现有代码的集成点

### 7.1 后端已有资源（直接接线）

| 资源 | 路径 | 状态 | 说明 |
|------|------|------|------|
| 挑战模板 | `resources/config/challenge-templates.json` | 可用 | 9个微练模板，P001-P010 |
| 训练记录服务 | `src/main/services/training-record.service.ts` | 可用 | 完整 CRUD |
| 训练任务描述 | `resources/prompts/training-tasks.md` | 可用 | 任务描述 |

### 7.2 需要新增的后端代码

| 文件 | 说明 |
|------|------|
| `src/main/services/training-recommendation.service.ts` | 根据 syndromeId 匹配挑战模板 |
| `src/main/ipc/training.handler.ts` | 5个 IPC 通道处理 |

### 7.3 需要新增的前端代码

| 文件 | 说明 |
|------|------|
| `src/renderer/components/training/TrainingWorkspace.tsx` | 左侧栏训练工作台 |
| `src/renderer/components/chat/TrainingCard.tsx` | 聊天流桥接卡片 |
| `src/renderer/components/training/TrainingHistory.tsx` | 训练历史迷你列表 |
| `src/renderer/stores/training.store.ts` | 训练状态管理 |

### 7.4 需要修改的前端代码

| 文件 | 修改量 | 说明 |
|------|--------|------|
| `App.tsx` | ~50行 | 接入 training store，渲染 TrainingWorkspace + TrainingCard |
| `AppSidebar.tsx` | ~20行 | 新增 trainingWorkspace 插槽 |
| `RightPanel.tsx` | ~5行 | 可选：移除原计划的训练入口代码 |
| `shared/types.ts` | ~15行 | 新增训练相关类型 |

---

## 8. 与 T-021 原方案的差异

| 项目 | T-021 原方案 | 本方案 V2.0 |
|------|------------|------------|
| 训练入口位置 | 右侧栏症候卡片 | 左侧栏训练窗 |
| 展示模式 | 右侧栏内嵌展开 | 可折叠三态小窗口 |
| TrainingCard | 在对话流中直接展开练习 | 桥接卡片，点击跳转左侧栏 |
| TrainingHistory | 右侧栏独立区块 | 嵌入训练窗底部 |
| 右侧栏变化 | 增加"试试练习"按钮+训练历史 | 保持纯观察层，不变 |
| AppSidebar | 不变 | 新增训练窗插槽 |

---

## 9. 开放问题

1. **左侧栏 280px 是否够用？** 激活态训练窗需要展示挑战描述（可能 100+ 字）+ 输入区，280px 宽度下文字行数较多。备选方案：激活态时左侧栏临时扩展到 360px。
2. **训练窗与 sidebarPage='tasks' 的关系？** 当前 App.tsx 有 `sidebarPage` 状态控制 Chat/Tasks 切换。训练窗是否替代 TasksPage，还是共存？
3. **多推荐排序**：当诊断到多个症候同时匹配到多个挑战模板时，排序策略（严重度优先？tier 优先？）
