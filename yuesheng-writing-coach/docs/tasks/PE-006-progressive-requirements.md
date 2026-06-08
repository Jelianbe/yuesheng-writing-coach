# PE-006: 渐进式提需求策略

> **优先级**: P1 | **状态**: in_progress | **预估**: 0.5d
> **依赖**: 无（纯前端 UI 改动） | **后续**: PE-008 Knowledge 文件引用策略
> **来源**: pro-writing-tools-report_V1.0.md → PE-006（ChatGPT "Writing Coach" GPT）

## 目标

在训练工坊的"开始训练"流程中增加一个**关注点选择中间步骤**。用户在点击"开始练习"后，不是直接进入三步训练，而是先指定本次训练想聚焦的具体方面（如 POV 控制/对话层次/节奏变速），让训练更有针对性。

## 设计依据

- **PE-006 模式定义**: docs/research/pro-writing-tools-report_V1.0.md → PE-006
  - 核心结构: 第一步粘贴文本 -> 第二步选择需求类型 -> 第三步指定关注点
  - 月笙最小版本: "在训练 Workshop 的'开始训练'流程中增加'先指定关注点（POV/节奏/角色）'的中间步骤"
- **现有基础**: PE-004（TrainingWorkshop 入口 2 个选择题）已完成
- **训练步骤框架**: ActiveTrainingView 三步框架（review → rewrite → submit）

## 改动方案

### 当前流程

```
用户点击「开始练习」 → startTraining(challengeId) → ActiveTrainingView（3 步）
```

### 目标流程

```
用户点击「开始练习」 → 关注点选择(PE-006) → startTraining(challengeId) → ActiveTrainingView（3 步）
```

### 关注点选项设计

从推荐任务的技法列表中提取关注点选项，如果没有技法信息，使用通用选项：

| 来源 | 选项 |
|------|------|
| 从 recommendation.techniques 提取 | 各技法 name（如"摄像机思维法""缺席式情感书写"） |
| 无技法信息时通用 | POV 控制 · 对话层次 · 节奏变速 · 细节展示 · 结构创新 |

### 交互设计

- 选择关注点使用 chip 按钮（与 PE-004 风格一致）
- 选择后点击"开始训练"按钮进入训练
- 可选"跳过，直接开始"（降低门槛）

## 核心改动

| # | 文件 | 操作 | 说明 |
|---|------|:----:|------|
| 1 | src/renderer/components/training/TrainingWorkshop.tsx | 修改 | 新增 pendingFocus 状态 + 关注点选择 UI |
| 2 | docs/tasks/TASK-CHAIN.md | 修改 | 更新 PE-006 状态 |

## DoD（完成标准）

- [x] D1. 点击「开始练习」后先显示关注点选择，不直接进入训练
- [x] D2. 关注点选项从推荐任务的技法中提取，无技法时使用通用选项
- [x] D3. 选择后点击确认才进入训练，可选"跳过直接开始"
- [x] D4. tsc 无错误，现有测试不破坏

## 回退方案

1. 回退 TrainingWorkshop.tsx 到旧版本

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| src/renderer/components/training/TrainingWorkshop.tsx | 新增 pendingFocus 状态 + 关注点选择 UI |
| docs/tasks/TASK-CHAIN.md | 更新 PE-006 状态 |

### 验证结果

- [x] tsc 无错误
- [x] 测试全部通过（38 文件 / 439 tests）
