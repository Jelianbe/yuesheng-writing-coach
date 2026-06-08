# T-031：教育学规则接入

> **版本**: V1.0  
> **创建日期**: 2026-06-06  
> **阶段**: Phase 2.5  
> **优先级**: P0  
> **预估**: 1.5d  
> **依赖**: T-029（症候类型分类）  
> **设计依据**: education-theory-fragments.json, education-theory-distillation_V1.0.md

---

## 目标

让 `education-theory-fragments.json` 中的 15 条决策规则在月笙系统中生效。当前这些规则仅存在于配置文件中，没有任何代码读取它们。

## 规则接入映射

| 规则 | 条件 | 推荐模式 | 接入位置 |
|------|------|---------|---------|
| R-001 | userLevel=beginner | 案例驱动 | student-classifier.ts + training-recommendation.service.ts |
| R-002 | userLevel=intermediate | 分析驱动 | 同上 |
| R-003 | userLevel=advanced | 反思驱动 | 同上 |
| R-004 | syndromeType=expressive_deficit | 先案例再模仿 | training-recommendation.service.ts（依赖 T-029） |
| R-005 | syndromeType=structural_disorder | 先反思再练习 | 同上 |
| R-006 | syndromeType=motivation_deficit | 先提问激发再案例 | 同上 |
| R-007 | trainingSkipRate>0.5 | 微任务+自主选择 | training-recommendation.service.ts |
| R-008 | trainingScore>=7 | 撤除脚手架 | training-evaluator.service.ts（已部分实现降级） |
| R-009 | sameSyndromeCount=2 | 拆分训练+元认知自检 | teaching-state-machine.ts |
| R-010 | sameSyndromeCount>=3 | 降级训练+自有文本改写 | teaching-state-machine.ts |
| R-011 | activeSyndromeCount>=2 | 单症候聚焦 | ProblemPrioritizer（已有基础） |
| R-012 | P003+P006 同时出现 | 任务中心整合 | ProblemPrioritizer |
| R-013 | beginner+L1 | 案例驱动+分步引导 | student-classifier + training-recommendation.service.ts |
| R-014 | advanced+重复2次 | 反思驱动+自我诊断 | teaching-state-machine.ts |
| R-015 | 影响阅读体验 | 优先处理 | ProblemPrioritizer |

## 执行顺序

```
Step 1: 规则加载器 (0.3d)
  └── EducationRuleService: 加载 education-theory-fragments.json
       → 提供 getRules(condition) 查询接口
       → 在所有规则之上排序（P0 优先）

Step 2: student-classifier 接入 (0.3d)
  └── R-001/R-002/R-003/R-013: userLevel → teachingMode 映射
       → trainingRecommendation 的 trainingMode 字段据此赋值

Step 3: training-recommendation 接入 (0.4d)
  └── R-004/R-005/R-006: syndromeType → feedbackEntry（依赖 T-029）
  └── R-007: 跳过率检测 → trainingMode 切换

Step 4: teaching-state-machine 接入 (0.3d)
  └── R-009/R-010: 重复次数追踪 → 子阶段调整
  └── R-014: advanced+重复 → 自我诊断模式

Step 5: ProblemPrioritizer 增强 (0.2d)
  └── R-011/R-012/R-015: 多症候优先级逻辑补充
```

---

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/main/services/education-rule.service.ts` | **新建** | 规则加载器 + 查询接口 |
| `src/main/services/student-classifier.ts` | 修改 | 读取规则，影响分类输出 |
| `src/main/services/training-recommendation.service.ts` | 修改 | 根据规则选择 trainingMode |
| `src/main/services/teaching-state-machine.ts` | 修改 | 重复次数检测 → 子阶段调整 |
| `src/main/services/problem-prioritizer.ts` | 修改 | 多症候优先级增强 |

---

## DoD

| # | 标准 | 验证方式 |
|---|------|---------|
| S1 | education-rule.service.ts 加载 JSON 并能根据 condition 查询匹配规则 | 单元测试：userLevel=beginner → R-001 + R-013 |
| S2 | 至少 3 条 P0 规则在代码中生效 | 验证 R-001/R-002/R-003 影响 trainingMode 输出 |
| S3 | TypeScript 编译 0 错误 | `npx tsc --noEmit` 通过 |

---

## 变更记录

| 日期 | 版本 | 变更内容 |
|------|------|---------|
| 2026-06-06 | V1.0 | 创建 |
