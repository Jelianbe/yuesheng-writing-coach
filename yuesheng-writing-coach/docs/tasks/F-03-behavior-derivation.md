# F-03: 角色行为推导模板

> **优先级**: P1 | **状态**: in_progress | **预估**: 3d
> **依赖**: 无 | **后续**: F-05 看点密度可视化
> **来源**: docs/design/ai-tool-features-report_V1.0.md → F-03（InkoS TP-019 角色行为推导法）

## 目标

训练用户"动笔前先想清楚角色动机"的习惯——通过三问推导法，让用户意识到"角色行为应由内在逻辑驱动，而非剧情需要"。

## 设计依据

- **F-03 定义**: docs/design/ai-tool-features-report_V1.0.md §F-03
  - 核心交互：用户选择角色 → 回答三问 → AI 推演行为预期 → 用户对比
  - 覆盖症候：P002（OOC）、P009（角色动机缺失）、P010（OC 平面化）
- **与现有功能的关系**：
  - 技法库（TQ-037/TQ-045）教"怎么写"，F-03 教"怎么想"
  - 诊断系统发现问题，F-03 提供针对性训练

## 改动方案

### 新增文件

| # | 文件 | 说明 |
|---|------|------|
| 1 | resources/prompts/behavior-derivation-prompt-v1.md | AI 角色行为推导引导 Prompt（约 30 行）|
| 2 | src/main/services/behavior-derivation.service.ts | 推导服务，调用 ApiProxy |
| 3 | src/renderer/components/training/BehaviorDerivationTool.tsx | 三问表单 + 推演结果展示 UI |

### 修改文件

| # | 文件 | 操作 | 说明 |
|---|------|:----:|------|
| 1 | src/shared/constants.ts | 修改 | 新增 IPC 通道常量 |
| 2 | src/main/ipc/training.handler.ts | 修改 | 新增 derive-behavior handler |
| 3 | src/renderer/components/training/TrainingWorkshop.tsx | 修改 | 集成推导工具入口 |
| 4 | src/main/core/ipc-registry.ts | 修改 | 注册新 handler |

### 核心逻辑

```
BehaviorDerivationService.deriveBehavior(input):
  1. 加载 Prompt（behavior-derivation-prompt-v1.md）
  2. 拼接用户三问回答 + 场景描述
  3. 调用 ApiProxy.chatStream() 获取推演结果
  4. 返回纯文本推演结果
```

### 输入/输出

**输入**：
- `characterName`：角色名
- `sceneDescription`：场景描述
- `question1`：过往经历让他怎么看待这件事？
- `question2`：他当前的利益诉求是什么？
- `question3`：他的性格底色驱使他怎么做？

**输出**：
- `derivedBehavior`：AI 推演的合理行为描述
- `analysis`：推演依据的简短解释

## DoD（完成标准）

- [ ] D1. 用户在训练工坊可以打开"角色行为推导"工具
- [ ] D2. 三问表单可以正确输入并提交
- [ ] D3. AI 能根据三问推导出合理的行为预期并展示
- [ ] D4. 显示推演依据的简短解释
- [ ] D5. tsc 无错误，现有测试不破坏

## 回退方案

1. 回退所有新增/修改文件
2. 移除 IPC 通道常量

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| resources/prompts/behavior-derivation-prompt-v1.md | 新建：角色行为推导 Prompt |
| src/main/services/behavior-derivation.service.ts | 新建：BehaviorDerivationService |
| src/renderer/components/training/BehaviorDerivationTool.tsx | 新建：三问表单 + 推演结果组件 |
| src/shared/constants.ts | 新增 IPC 通道常量 |
| src/main/ipc/training.handler.ts | 新增 derive-behavior handler |
| src/renderer/components/training/TrainingWorkshop.tsx | 集成推导工具入口 |
| src/preload/index.ts | 新增通道白名单 |

### 验证结果

- [x] tsc 无错误（0 错误）
- [x] 测试全部通过（455/455, 39 文件）
