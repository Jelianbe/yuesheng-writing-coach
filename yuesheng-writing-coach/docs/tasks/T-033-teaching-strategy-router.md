# T-033 TeachingStrategyRouter 核心引擎

> **优先级**: P0 | **预估**: 1.5d | **状态**: 规划 | **标签**: Phase 3, core

## 任务描述

实现 TeachingStrategyRouter 服务，作为多条件教学决策层。消费 Phase 2.5 产出的全部配置文件，替代现有 `TeachingStrategyService.decide()` 的简单条件映射。

## 前置条件

- [x] education-theory-fragments.json（15 条决策规则）
- [x] learning-path.json（学习路径定义）
- [x] technique-selection-matrix.json（技法过滤矩阵）
- [x] coaching-templates.json（10 个话术模板）
- [x] user-type-map.json（4 种用户类型 + 8 种教学映射）
- [x] syndrome-type-map.json（症候类型分类）
- [x] teaching-state-machine.ts（状态机，消费 Router 输出）

## 设计概要

### 架构位置

```
StudentModel + DiagnosisResult + TrainingHistory
        ↓
TeachingStrategyRouter（新增独立服务）
        ↓ 决策输出
            ├── targetSyndrome: string         聚焦症候
            ├── teachingMode: TeachingMode     教学模式
            ├── stepSequence: StepConfig[]      教学步骤序列
            ├── toneProfile: ToneConfig         语气配置
            ├── practiceType: string            练习类型
            └── theoryReference: string[]       理论依据
        ↓
teaching-state-machine.ts → prompt-builder.ts → Agent
```

### 三层决策

```
第一层：聚焦症候选择
  - 教育规则 (R-011~R-015) 优先级
  - syndromePriorityMap (technique-selection-matrix)
  - 训练评分最低的症候优先

第二层：教学方式选择
  - userTypeMap.teachingStyleMap → coarse mode + tone
  - syndromeTypeMap → recommendedEntry
  - educationTheoryFragments → fine-grained rule match

第三层：参数细化
  - learning-path → phase + core patterns
  - coaching-templates → step sequence
  - trainingHistory → difficulty adjustment
```

## 验收标准 (DoD)

- [ ] Router 服务可独立加载 6 个配置文件
- [ ] 第一层决策：给定 syndrome 列表 + severity + trainingHistory，输出 targetSyndrome
- [ ] 第二层决策：给定 userLevel + syndromeType，输出 teachingMode
- [ ] 第三层决策：给定 userLevel + targetSyndrome，输出 stepSequence + toneProfile
- [ ] 输出包含 theoryReference（可追溯的教育学依据）
- [ ] 与现有 teaching-strategy.service.ts 的输出接口兼容
- [ ] npx tsc --noEmit 通过
- [ ] 所有现有测试通过

## 相关文件

| 文件 | 关系 |
|------|------|
| `src/main/services/teaching-strategy.service.ts` | 被替代的旧服务 |
| `src/main/services/teaching-state-machine.ts` | 消费 Router 输出 |
| `resources/config/education-theory-fragments.json` | 决策规则 |
| `resources/config/learning-path.json` | 学习路径 |
| `resources/config/technique-selection-matrix.json` | 技法的过滤矩阵 |
| `resources/config/coaching-templates.json` | 教学行动策略 |
| `resources/config/user-type-map.json` | 用户类型映射 |
| `resources/config/syndrome-type-map.json` | 症候类型映射 |
| `src/main/services/student-model.service.ts` | 学生模型 |
| `src/renderer/shared/types.ts` | 类型定义 |
