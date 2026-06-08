# T-021: 训练入口与工坊

> **优先级**: P1 | **状态**: ▶️ in_progress | **预估**: 4d  
> **依赖**: T-013 | **后续**: T-016  
> **设计方案**: [training-entry-ui_V4.0.md](../design/training-entry-ui_V4.0.md)
> **废弃方案**: ~~V2.0（左侧栏小窗口，只支持被动推荐）~~ / ~~V3.0（遗漏对话内训练+诊断强绑定）~~

## 目标

将后端已有的训练资源接线到前端，构建**双路径训练架构**：路径 A（对话内训练，已完成 M-2/M-3/M-4）+ 路径 B（训练工坊，待实现）。核心变更：从 V3.0 的"单一训练工坊"升级为"双路径+内容感知路由"，解决诊断-训练强绑定问题。

## 设计依据

- **UI 设计方案**: [training-entry-ui_V4.0.md](../design/training-entry-ui_V4.0.md) — 双路径训练架构 + 内容感知路由层 + 对话内训练 + 训练工坊
- **设计依据文档**: [challenge-unlock-reflection_V1.0.md](../design/challenge-unlock-reflection_V1.0.md) §反思过关后推荐训练
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现2 四层架构坍缩（Layer 4 训练层完全未实现）
- **来源任务**: T-013（能力成长可视化完成后，用户看到"这个症候还在"→ 自然而然想改进 → 训练入口承接）
- **V2.0→V3.0 转折**: 用户反馈 V2.0 只考虑被动推荐，忽略了主动训练需求；左侧栏空间不足以支撑真正的练习交互
- **V3.0→V4.0 转折**: V3.0 遗漏对话内训练路径（代码中已实现 M-2/M-3/M-4）；诊断-训练强绑定，世界观/碎片/新用户内容不应触发诊断
- **已完成部分（路径 A）**: DiagnosisCard→EditPanel→EvaluationCard→GrowthCard 链路已接线
- **已有资源**:
  - `resources/config/challenge-templates.json` — 9 个挑战微练模板
  - `src/main/services/training-record.service.ts` — 完整 CRUD（assign/complete/skip/getBySession/getAll）
  - `resources/prompts/training-tasks.md` — 训练任务描述

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 新增 IPC 通道：训练推荐 + 训练分配 + 训练完成 + 训练跳过 + 训练历史查询 | `src/main/ipc/training.handler.ts` |
| 后端 | 新增 TrainingRecommendationService：基于当前诊断结果推荐匹配的挑战 | `src/main/services/training-recommendation.service.ts` |
| 前端 | **训练工坊主面板（中心面板模式切换，含错误卡片+训练任务+步骤式练习）** | `src/renderer/components/training/TrainingWorkshop.tsx` |
| 前端 | 聊天流桥接卡片（点击切换到训练工坊模式） | `src/renderer/components/chat/TrainingBridgeCard.tsx` |
| 前端 | 训练历史栏（嵌入训练工坊底部） | `src/renderer/components/training/TrainingHistoryBar.tsx` |
| 前端 | 训练状态 Zustand store（含 centerMode） | `src/renderer/stores/training.store.ts` |
| 前端 | AppSidebar 新增"训练工坊"按钮 | `src/renderer/components/layout/AppSidebar.tsx` |
| 类型 | 训练相关前端类型定义 | `src/renderer/shared/types.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/ipc/training.handler.ts` | 新增 | 训练相关 IPC 通道（推荐/分配/完成/跳过/历史） |
| 2 | `src/main/services/training-recommendation.service.ts` | 新增 | 根据诊断结果匹配 challenge-templates 中的微练 |
| 3 | `src/renderer/components/training/TrainingWorkshop.tsx` | 新增 | 训练工坊主面板（核心新组件，替代 V2.0 的 TrainingWorkspace） |
| 4 | `src/renderer/components/chat/TrainingBridgeCard.tsx` | 新增 | 聊天流桥接卡片（替代 V2.0 的 TrainingCard） |
| 5 | `src/renderer/components/training/TrainingHistoryBar.tsx` | 新增 | 训练历史栏（替代 V2.0 的 TrainingHistory） |
| 6 | `src/renderer/stores/training.store.ts` | 新增 | 训练状态管理（含 centerMode 状态） |
| 7 | `src/renderer/components/layout/AppSidebar.tsx` | 修改 | 新增"训练工坊"按钮 + onEnterWorkshop prop |
| 8 | `src/renderer/App.tsx` | 修改 | sidebarPage→centerMode；TrainingWorkshop 条件渲染；删除 TasksPage |
| 9 | `src/renderer/shared/types.ts` | 修改 | 新增 CenterMode / ErrorCard / ActiveTrainingSession / TrainingStep |
| 10 | `src/main/index.ts` | 修改 | 注册 training handler |
| 11 | `src/renderer/stores/task.store.ts` | 删除 | 仅3行注释，被 training.store.ts 替代 |

## 交互设计

> 详细设计见 [training-entry-ui_V4.0.md](../design/training-entry-ui_V4.0.md)

### 路径 A：对话内训练（已实现 M-2/M-3/M-4）

```
DiagnosisCard → EditPanel → EvaluationCard → GrowthCard
（嵌入对话流，不改页面，不改上下文）
```

触发：用户发叙事文本 → 内容路由判定 narrative → 诊断 → DiagnosisCard 渲染 → 用户点"尝试修改"

### 路径 B：训练工坊（待实现）

**入口 1: 主动入口（左侧栏训练工坊按钮）**

```
┌─ AppSidebar ──────────────┐
│ + 新建会话                 │
│ 🎯 训练工坊  ← 新增按钮   │
│ ── 最近会话 ──             │
│ 当前会话 *                 │
└───────────────────────────┘
```

点击 → centerMode 切换到 'training' → 中心面板渲染 TrainingWorkshop

**入口 2: 被动入口（对话流 AI 推荐）**

```
┌─ TrainingBridgeCard ────────────┐
│ 🎯 匹配到练习                    │
│ 针对你的「世界观膨胀」问题，       │
│ 有一个聚焦核心场景的练习          │
│ [进入训练工坊]  [下次再说]       │
└──────────────────────────────────┘
```

点击"进入训练工坊" → centerMode 切换到 'training'

**入口 3: 反思过关后自然衔接**（T-018 门控通过后）

AI 在建议结尾自然推荐，用户确认后进入训练工坊。

### 训练工坊中心面板布局

```
┌─ 训练工坊 ──────────────── [返回对话] ─┐
│                                         │
│ ┌─ 你的常见问题（基于历史诊断）──────┐  │
│ │ [P001 世界观膨胀 L3|3次诊断]      │  │
│ │ "整个大陆被分为五个王国..."        │  │
│ │ [P003 情绪标签化 L2|2次诊断]      │  │
│ │ "他很紧张，心里充满了..."          │  │
│ └────────────────────────────────────┘  │
│                                         │
│ ┌─ 推荐训练任务 ────────────────────┐  │
│ │ CH-P001 聚焦核心场景 | structural │  │
│ │ 挑战描述...         [开始练习]    │  │
│ │ CH-P003 展示替代告知 | surface    │  │
│ │ 挑战描述...         [开始练习]    │  │
│ └────────────────────────────────────┘  │
│                                         │
│ ┌─ 近期训练记录 ────────────────────┐  │
│ │ ✓ CH-P003 已完成 ○ CH-P001 进行中│  │
│ └────────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 训练进行中

点击"开始练习"后，中心面板进入步骤式练习模式：

- 进度条 + 步骤列表
- 原始文本引用（触发诊断的用户原文片段）
- 挑战描述 + 约束条件
- 写作区（实时编辑）
- 提交/存草稿/跳过按钮

### 中心面板模式切换

| centerMode | 中心区域内容 | 切换触发 |
|-----------|-------------|---------|
| `'chat'`（默认） | MessageList + MessageInput | 初始状态 / 训练工坊"返回对话" |
| `'training'` | TrainingWorkshop | 左侧栏按钮 / TrainingBridgeCard |

## DoD（完成标准）

### 路径 A：对话内训练（M-2/M-3/M-4，已完成）

- [x] A1. DiagnosisCard 渲染条件正确（currentDiagnosis && !isStreaming）
- [x] A2. "尝试修改"按钮调用 onStartEditing → EditPanel 展开
- [x] A3. EditPanel 提交 → submitRewrite IPC → EvaluationCard 渲染
- [x] A4. GrowthCard 渲染成长记录
- [x] A5. useDiagnosisFlow 状态机完整（idle→editing→submitting→evaluated）

### 路径 B：训练工坊

- [x] B1. 左侧栏"训练工坊"按钮可触发中心面板模式切换
- [x] B2. TrainingWorkshop 正确渲染错误卡片（基于历史诊断聚合），并展示最近引用原文片段（sourceSnippets）
- [x] B3. TrainingWorkshop 正确渲染推荐训练任务（基于 challenge-templates 匹配）
- [x] B4. 聊天流 TrainingBridgeCard 可触发进入训练工坊
- [x] B5. TrainingRecommendationService 根据当前诊断的 syndromeId 匹配 challenge-templates
- [x] B6. 训练完成后调用 training-record.service 的 complete() 记录结果
- [x] B7. 步骤式练习交互正常（进度条+原始引用+写作区+提交）
- [x] B8. 训练历史栏展示最近训练记录
- [x] B9. 无历史诊断时显示空状态引导
- [x] B10. 无匹配挑战模板时训练任务区优雅降级
- [x] B11. 训练完成提交后，AI 评估反馈在对话流中显示（自动切回 chat 模式）

### Evidence Level 1（MVP 补丁，V1.5 前置）

- [ ] ~~E1. `DiagnosisEntry` 新增 `sourceSnippets: string[]` 字段~~→ T-027 覆盖
- [ ] ~~E2. 后端诊断时从触发诊断的用户消息中提取对应原文片段填入 sourceSnippets~~→ T-027 覆盖
- [ ] ~~E3. 修复当前 `evidence` 字段语义不一致~~→ T-027 覆盖
- [ ] ~~E4. TrainingWorkshop 错误卡片可正确展示 sourceSnippets（最近引用）~~→ T-027 覆盖

### 内容感知路由层

- [x] R1. ContentAwareRouter 替代 MessageRouter.shouldRunDiagnosis
- [x] R2. 叙事文本正确路由到 diagnosis
- [x] R3. 世界观/设定文本路由到 worldbuild_guide（不触发诊断）
- [x] R4. 碎片/杂项路由到 clarify（不触发诊断）
- [x] R5. 新用户/未初始化路由到 onboarding
- [x] R6. 低置信度时默认降级为 clarify

### 通用

- [x] G1. centerMode 切换时对话消息不丢失
- [x] G2. TypeScript 编译无错误
- [x] G3. 至少 8 个测试 ✅（实际 79 个）

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. 前端组件不删除但设为 feature flag 关闭
3. 后端 IPC 通道和 Service 保留（无副作用）

## 执行记录

### 已完成子任务

#### T-021.1: Evidence System Refactoring ✅

- **内容**: 诊断证据按症候分组，新增 `syndromeRef` 字段到 KeyPassage，诊断 Prompt 要求标记症候引用，证据分组逻辑含 fallback 策略
- **涉及文件**: `types.ts`, `chat.handler.ts`, `evidence-grouping.ts`
- **测试**: 15 个新测试通过，306 测试全部通过

#### T-021.2: Content-Aware Routing Layer ✅

- **内容**: 基于内容分类的路由引擎，替代 MessageRouter.shouldRunDiagnosis
- **涉及文件**: 新增 content-classifier.ts + route-engine.ts
- **测试**: 22 个测试通过

#### T-021.3: Center Panel Mode Switching ✅

- **内容**: 中心面板模式切换（chat/training），TrainingStore 新增 centerMode，App.tsx/AppSidebar.tsx 对接
- **涉及文件**: `training.store.ts`, `types.ts`, `App.tsx`, `AppSidebar.tsx`, 删除 `task.store.ts`
- **测试**: 编译通过，功能验证通过

### 待执行子任务

_（全部完成，无待执行）_

### 测试统计

| 测试文件 | 数量 | 说明 |
|---------|:----:|------|
| `src/renderer/stores/__tests__/training.store.test.ts` | 22 | 覆盖基础状态/模式切换/桥接卡片/updateDraft/skipTraining/startTraining/loadHistory/refreshFromDiagnosis/submitStep |
| `src/main/ipc/__tests__/training-flow.test.ts` | 14 | 覆盖 recommend/assign/complete/skip/history/submit 六个 IPC 通道 |
| `src/renderer/components/training/TrainingWorkshop.test.tsx` | 13 | 覆盖加载中/错误/活跃训练/三区块/ErrorCards/Recommendations/History 子系统 |
| `src/renderer/components/training/ActiveTrainingView.test.tsx` | 21 | 覆盖三步框架 Step 0/1/2/评估失败/加载状态 |
| `src/main/services/__tests__/training-recommendation.test.ts` | 9 | 已有（服务层） |
| **合计** | **79** | |

