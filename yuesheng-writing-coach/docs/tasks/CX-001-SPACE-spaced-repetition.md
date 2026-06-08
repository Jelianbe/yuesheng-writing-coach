# CX-001-SPACE: 间隔重复复习机制

> **优先级**: P2 | **状态**: done | **预估**: 0.5d
> **依赖**: CX-001-TIER（渐进分层评审已完成） | **后续**: PE/SF 系列
> **来源**: 跨学科教学编排方法论调研 — docs/research/跨学科教学编排方法论调研_V1.0.md → 模式 4-1「间隔重复」

## 目标

基于遗忘曲线（Ebbinghaus）为已学技法设计间隔重复复习机制，输出到 `spaced-repetition.json`。让系统能自动计算每条技法下次复习时间、安排复习任务，帮助用户对抗遗忘曲线。

## 设计依据

- **调研报告**: docs/research/跨学科教学编排方法论调研_V1.0.md → 模式 4-1「间隔重复」、B 章共通原则#4「复习机制」
- **路径数据**: curriculum-path.json（3 条路径 32 条技法）
- **评审数据**: tier-review.json（完成标准 + 跳级规则）

## 遗忘曲线模型

```
记忆留存率 vs 时间（无复习）
  100% ┤
       │
   70% ┤    ┌─ 1d 后 → 约 60%
       │    │
   50% ┤    │   ┌─ 3d 后 → 约 40%
       │    │   │
   30% ┤    │   │   ┌─ 7d 后 → 约 25%
       │    │   │   │
   10% ┤    │   │   │   ┌─ 30d 后 → 约 10%
       └────┴───┴───┴───┴─────────→ 时间
复习后：记忆留存率回升至 ~95%，遗忘曲线变缓
```

## 间隔策略

| 复习次数 | 间隔 | 说明 |
|:--------:|:----:|------|
| 第 1 次 | 1 天 | 学完后第 2 天首次复习 |
| 第 2 次 | 3 天 | 通过后间隔 3 天 |
| 第 3 次 | 7 天 | 间隔 7 天 |
| 第 4 次 | 14 天 | 间隔 14 天 |
| 第 5 次 | 30 天 | 间隔 1 个月 |
| 第 6 次 | 60 天 | 间隔 2 个月 |
| 第 7 次 | 120 天 | 间隔 4 个月（之后标记为"已固化"）|

## 判定规则

| 规则 | 值 | 说明 |
|:----|:--:|------|
| defaultIntervals | [1,3,7,14,30,60,120] | 7 级间隔，单位天 |
| reviewPassThreshold | 0.7 | 复习评分 ≥0.7 视为通过 |
| maxReviewsPerDay | 5 | 每天最多推送 5 条复习（防 overload）|
| masteryAfterReviews | 7 | 完成 7 次复习后标记为"已固化" |
| failedReviewPenalty | "reset" | 复习失败后重置到第 1 级间隔 |

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 数据/配置 | 新增 spaced-repetition.json（间隔参数 + 路径复习配置） | resources/config/spaced-repetition.json |

纯数据配置任务，无代码变更。

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | resources/config/spaced-repetition.json | 新增 | 间隔策略 + 3 条路径 32 条技法复习配置 |
| 2 | docs/tasks/TASK-CHAIN.md | 修改 | 更新 CX-001-SPACE 状态 |

## 输出格式

```json
{
  "version": "1.0",
  "spacingRules": {
    "defaultIntervals": [1, 3, 7, 14, 30, 60, 120],
    "reviewPassThreshold": 0.7,
    "maxReviewsPerDay": 5,
    "masteryAfterReviews": 7,
    "failedReviewPenalty": "reset"
  },
  "pathReviews": [
    {
      "pathId": "character-craft",
      "stageReviews": [
        {
          "level": "L0",
          "techniques": [
            {
              "id": "TE-013",
              "reviewMode": "mixed",
              "reviewPrompt": "练习用摄像机思维法描写一段角色情绪",
              "intervals": [1, 3, 7, 14, 30, 60, 120]
            }
          ]
        }
      ]
    }
  ]
}
```

## 选择策略

- 每条技法自动分配 `reviewMode`（根据技法类型：beginner 用 "recall"，intermediate 用 "practice"，advanced 用 "mixed"）
- `reviewPrompt` 基于技法 description 生成简短的复习提示
- 所有技法复用默认间隔策略，个别技法可覆盖

## DoD（完成标准）

- [x] D1. spaced-repetition.json 包含全部 3 条路径 32 条技法的复习配置
- [x] D2. 间隔策略基于遗忘曲线，7 级间隔严格递增
- [x] D3. 每技法有 reviewPrompt 可被程序化消费

## 回退方案

1. 删除 `resources/config/spaced-repetition.json`
2. 无数据库变更

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| resources/config/spaced-repetition.json | 新增，3 路径 32 条技法复习配置 |
| docs/tasks/TASK-CHAIN.md | 更新 CX-001-SPACE 状态 |

### 验证结果

- [x] JSON 合法（格式验证通过）
- [x] 3 路径全部覆盖（character-craft 12 / world-building 11 / outline-planning 9 = 32 条）
- [x] 间隔策略严格递增（[1, 3, 7, 14, 30, 60, 120]）
- [x] 全部技法有 reviewPrompt（32/32）
- [x] reviewMode 合法（按 beginner/intermediate/advanced 分配 recall/practice/mixed）

## 下个任务建议

CX-001 系列全部完成后，建议转向 PE-002「Codex 结构化知识注入」（P1）——将 Codex 写作知识结构化注入系统 Prompt，提升 AI 写作建议的专业度和覆盖度。
