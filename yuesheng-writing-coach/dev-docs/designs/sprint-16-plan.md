# Sprint 16 Plan: 五步通用训练流贯通

> Issue: https://github.com/Jelianbe/yuesheng-writing-coach/issues/25
> 依据: ADR-003 §五步流, RWR-MASTER-CHAIN.md §十二 BL-01/BL-02

## 现状分析

### 当前训练流程（绕过五步流）

```
TrainingWorkshop[推荐列表] → startTraining(challengeId)
    → LLM 生成指令（无结构）
    → 3 步框架（review → rewrite → submit）
    → AI 评估
```

### 当前 TrainingFlowService（孤立服务）

```
generateTrainingFlow({ syndromeId, techniqueName, userLevel })
    → 5 步结构（解说→例证→确认→尝试→反馈）
    → fillTemplate() 从 technique-library.json 取数据
    → 返回 TrainingFlow { steps: [], estimatedTotalMinutes }
    ← 从未被消费
```

### 差距

| 维度 | 当前（3 步） | 目标（5 步） |
|:----:|:------------:|:------------:|
| 步数 | 3（review/rewrite/submit） | 5（解说/例证/确认/尝试/反馈）|
| 技法数据 | LLM prompt 内全量注入 | `fillTemplate()` 精确注入 |
| 用户体验 | 一步到位改 → 缺教学感 | 分步引导 → 有教学层次 |
| 可评估性 | 只有最终评分 | 每步可独立评估 |

## 架构变更

### BL-01a: TrainingFlowService 贯通（核心变更）

```
startTraining(challengeId)
    │
    ├─ mapping.json[challengeId] → { syndromeId, techniqueName, userLevel }
    │
    ├─ generateTrainingFlow({ syndromeId, techniqueName, userLevel })
    │   → TrainingFlow { steps: [5], estimatedTotalMinutes }
    │
    └─ 创建 ActiveTrainingSession(flowId=trainingFlow, steps=5步, currentStep=0)
        → TrainingWorkshop 渲染 5 步 UI
```

**变更点：**
1. 新建 `training-flow-mapping.json`：challengeId → { syndromeId, techniqueName, userLevel, category }
2. 修改 `training.store.ts:startTraining()`：优先查 mapping → 调用 `generateTrainingFlow()` → 创建 5 步 session
3. 无 mapping 的 challengeId → fallback 到当前 3 步 LLM 流程

### BL-01b: fillTemplate() 技法动态加载（已有 + 增强）

`fillTemplate()` 已在 `training-flow.service.ts:144` 实现。需验证：
- 模板变量 `{techniqueName}` `{description}` `{example}` `{effect}` `{constraint}` 与 `technique-library.json` 字段对齐 ✅
- `example` 字段在部分技法中为空 → fallback 到通用提示

### BL-01c: 五步流 UI 状态切换

**ActiveTrainingView 扩展：**

```
current 3-step View (StepIndicatorList → Reading/Rewrite/Evaluation content)
    ↓
new 5-step View (StepIndicatorList → 5 content panels)
    ├─ Step 1: 解说展示 → InstructionPanel（纯阅读）
    ├─ Step 2: 例证展示 → ExamplePanel（展示示例 + 思考）
    ├─ Step 3: 确认理解 → VerifyPanel（用户输入框 + 提交）
    ├─ Step 4: 主动尝试 → PracticePanel（改写编辑框 + 提交）
    └─ Step 5: 修改反馈 → FeedbackPanel（评估 + 修改 + X-02 写回）
```

**UI 组件新增/修改：**
| 文件 | 操作 | 说明 |
|------|:----:|------|
| `ActiveTrainingView.tsx` | 修改 | 新增 `flowType` 分支：'five_step' vs 'three_step' |
| `FlowStepIndicator.tsx` | 新增 | 5 步状态指示器（替代 3 步 StepIndicatorList）|
| `FlowInstructionPanel.tsx` | 新增 | Step 1 解说展示 |
| `FlowExamplePanel.tsx` | 新增 | Step 2 例证展示 |
| `FlowVerifyPanel.tsx` | 新增 | Step 3 确认理解输入 |
| `FlowPracticePanel.tsx` | 重写 | Step 4 练习改写（复用 RewriteStepContent 逻辑）|
| `FlowFeedbackPanel.tsx` | 新增 | Step 5 评估反馈 + 修改 |
| `training.types.ts` | 修改 | ActiveTrainingSession 扩展 flowType 字段 |

### BL-02: 技法消费层过滤

**变更点：**
1. `injectTechniquePool()` 签名扩展：`(prompt, activeSyndromeIds?: string[])`
2. 当 `activeSyndromeIds` 传入时，过滤 `technique-library.json` 的 `applicableSyndromes` 字段
3. 未传 `activeSyndromeIds` 时行为不变（全量注入）

**消费方更新：**
- `training-evaluator-prompt-v1.md` 构建处的 `injectTechniquePool` 调用 → 传入活跃症候 ID 列表

## 边界定义

### 包括
- TrainingFlowService 贯通到 startTraining → ActiveTrainingView
- 5 步 UI 组件实现（纯展示 + 用户提交）
- fillTemplate 从技法库动态取数据
- injectTechniquePool 过滤参数 + 集成
- 基础步数指示器（当前步高亮 + 已完成步标记）
- 无 mapping 的 challengeId fallback 到 3 步流

### 不包括
- X-02 写回协议（Sprint 18）
- P011/P012 技法补全（Sprint 18）
- UX 批量修复 A3/B2/B3/B4/C2（Sprint 17）
- 训练效果数据持久化（已有）
- 非训练管道的前端改动

## 数据流

```
TrainingWorkshop(推荐列表)
  ↓ onStartTraining(challengeId)
training.store.startTraining()
  ↓
IPC: training:getChallengeDetail(challengeId)
  ├─ 有 mapping.json 条目
  │   → generateTrainingFlow({ syndromeId, techniqueName, userLevel })
  │   → 返回 TrainingFlow { steps: [{stepId:1,...},...5] }
  │   → set({ activeTraining: { flowType:'five_step', steps, currentStepIndex:0 } })
  │
  └─ 无 mapping 条目
      → 当前 3 步 LLM 流程（fallback）

ActiveTrainingView
  ├─ flowType === 'five_step'
  │   → FlowStepIndicator (5 步)
  │   → FlowInstructionPanel | FlowExamplePanel | FlowVerifyPanel | FlowPracticePanel | FlowFeedbackPanel
  │
  └─ flowType === 'three_step' (default)
      → StepIndicatorList (3 步)
      → ReadingStepContent | RewriteStepContent | EvaluationStepContent
```

## DoD 验证

1. 用户可在 TrainingWorkshop 完整走完五步训练流（解说→例证→确认→尝试→反馈）
2. fillTemplate() 从 technique-library.json 动态取数据，覆盖 P001-P007 至少 5 个症候
3. injectTechniquePool 不再全量注入~100 条，仅注入活跃症候相关技法
4. 无 mapping 的 challengeId 降级到 3 步流不崩溃
5. typecheck 0 / test 全绿 / lint 0 error / 安全 0 硬编码
6. 步数指示器显示当前步、已完成步、待完成步

## 文件清单

| 文件 | 操作 | 预估 |
|------|:----:|:----:|
| `resources/config/training-flow-mapping.json` | **新建** | 0.2d |
| `src/renderer/stores/training.types.ts` | 修改 | 0.1d |
| `src/renderer/stores/training.actions.ts` | 修改 (startTraining) | 0.3d |
| `src/renderer/components/training/ActiveTrainingView.tsx` | 修改 | 0.2d |
| `src/renderer/components/training/FlowStepIndicator.tsx` | **新建** | 0.2d |
| `src/renderer/components/training/FlowInstructionPanel.tsx` | **新建** | 0.1d |
| `src/renderer/components/training/FlowExamplePanel.tsx` | **新建** | 0.1d |
| `src/renderer/components/training/FlowVerifyPanel.tsx` | **新建** | 0.2d |
| `src/renderer/components/training/FlowPracticePanel.tsx` | **新建** | 0.2d |
| `src/renderer/components/training/FlowFeedbackPanel.tsx` | **新建** | 0.2d |
| `src/main/domains/03-teaching/prompt/` (injectTechniquePool) | 修改 | 0.2d |
| 单元测试 × 6 组件 | 新建 | 0.3d |
| 门禁(typecheck/test/lint) | 验证 | 0.1d |
| **合计** | | **~2.5d** |
