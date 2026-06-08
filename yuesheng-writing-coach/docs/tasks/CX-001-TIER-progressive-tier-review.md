# CX-001-TIER: 渐进分层评审节点

> **优先级**: P2 | **状态**: in_progress | **预估**: 0.5d
> **依赖**: CX-001-PATH（三条路径原型已完成） | **后续**: CX-001-SPACE（间隔重复复习机制）

## 目标

为三条学习路径的每层定义完成标准（completion criteria）和跳级机制（skip/placement），输出到 `tier-review.json`。让系统能判断用户在每条路径的阶段位置——是应该从 L0 开始、跳级到 L2、还是已完成整条路径。

## 设计依据

- **调研报告**: docs/research/跨学科教学编排方法论调研_V1.0.md → 模式 3-1「渐进分层评审」
- **路径数据**: curriculum-path.json（3 条路径 × 3 阶段技法序列）
- **现有评分**: training-evaluator.service.ts（Evaluator Agent 评分机制）

## 评审模型

```
用户进入路径
    │
    ▼
[阶段预测试] ─── 分数 >= skipThreshold ───→ 跳过该阶段
    │                                            │
    │ 分数 < skipThreshold                       │
    ▼                                            ▼
[阶段学习] → [阶段后测试] ─── 分数 >= passThreshold → 进入下阶段
                              │
                              分数 < passThreshold → 复习重测
```

## 判定规则

| 规则 | 数值 | 说明 |
|------|:----:|------|
| passThreshold | 0.7 | 阶段完成后测试 ≥70% 视为通过 |
| skipThreshold | 0.85 | 预测试 ≥85% 可跳过该阶段 |
| maxSkipsPerPath | 1 | 每条路径最多跳 1 个阶段（防止基础不牢） |
| minTechniquesForCompletion | 75% | 需完成阶段内至少 75% 的技法练习 |
| reviewRetryLimit | 2 | 未通过时最多重测 2 次 |

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 数据/配置 | 新增 tier-review.json（评审规则 + 路径阶段标准）| resources/config/tier-review.json |

纯数据配置任务，无代码变更。

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | resources/config/tier-review.json | 新增 | 评审规则 + 3 条路径每层完成标准 |
| 2 | docs/tasks/TASK-CHAIN.md | 修改 | 更新 CX-001-TIER 状态 |

## 输出格式

```json
{
  "version": "1.0",
  "globalRules": {
    "passThreshold": 0.7,
    "skipThreshold": 0.85,
    "maxSkipsPerPath": 1,
    "minTechniquesRatio": 0.75,
    "reviewRetryLimit": 2
  },
  "pathReviews": [
    {
      "pathId": "character-craft",
      "stages": [
        {
          "level": "L0",
          "completionCriteria": {
            "requiredTechniques": 3,
            "requiredAssessments": 1
          },
          "skipCriteria": {
            "pretestTechniques": ["TQ-013", "TQ-027", ...],
            "pretestThreshold": 0.85
          },
          "nextStageReview": {
            "reviewType": "mixed",
            "techniques": [...]
          }
        }
      ]
    }
  ]
}
```

## 选择策略

- 每个阶段的 `completionCriteria.requiredTechniques` = ceil(阶段技法数 × minTechniquesRatio)
- 每个阶段的 `skipCriteria.pretestTechniques` = 取该阶段最难的 2 条技法作为预测试样本
- `nextStageReview.techniques` = 从前序阶段取 1-2 条代表性技法

## DoD（完成标准）

- [x] D1. tier-review.json 包含全部 3 条路径 9 个阶段的评审标准
- [x] D2. 全局规则合理（pass=0.7 < skip=0.85，maxSkips=1 防跳过多）
- [x] D3. 每个阶段的完成条件（requiredTechniques）和跳级条件（pretestTechniques + threshold）可被程序化判定

## 回退方案

1. 删除 `resources/config/tier-review.json`
2. 无数据库变更

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| resources/config/tier-review.json | 新增，3 路径 × 3 阶段评审规则 |
| docs/tasks/TASK-CHAIN.md | 更新 CX-001-TIER 状态 |

### 验证结果

- [x] JSON 合法
- [x] 所有路径阶段覆盖
- [x] 全局规则数值合理

### 路径评审一览

#### 角色塑造

| 阶段 | 需完成技法 | 预测试样本 | 阶段间复习 |
|:----:|:----------:|:----------:|:---------:|
| L0 | 3/4 | TQ-013, TQ-027 | show-dont-tell 核心 |
| L1 | 3/4 | TQ-008, TQ-032 | dialogue + pov 交叉 |
| L2 | 3/4 | TC-003, TC-004 | 角色立体化综合 |

#### 世界观构建

| 阶段 | 需完成技法 | 预测试样本 | 阶段间复习 |
|:----:|:----------:|:----------:|:---------:|
| L0 | 3/3 | TQ-012, TQ-013 | show-dont-tell 核心 |
| L2 | 3/4 | AIP-007, AIP-020 | 设定融入+节奏交叉 |
| L3 | 3/4 | AIP-016, TC-012 | 悬念+设定综合 |

#### 大纲规划

| 阶段 | 需完成技法 | 预测试样本 | 阶段间复习 |
|:----:|:----------:|:----------:|:---------:|
| L0 | 3/4 | TC-008, TE-014 | 开篇技巧巩固 |
| L1 | 3/4 | TQ-041, TQ-057 | 节奏控制+开篇交叉 |
| L2 | 1/1 | TE-018 | 结构创新综合 |

## 下个任务建议

完成后建议启动 CX-001-SPACE「间隔重复复习机制」——基于遗忘曲线为已学技法安排周期性复习推送。
