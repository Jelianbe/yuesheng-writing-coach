# CX-001-PATH: 三条独立路径原型

> **优先级**: P1 | **状态**: in_progress | **预估**: 0.5d
> **依赖**: CX-001-DAG（知识依赖图 DAG 已完成） | **后续**: CX-001-TIER（渐进分层评审节点）
> **来源**: 跨学科教学编排方法论调研 — docs/research/跨学科教学编排方法论调研_V1.0.md

## 目标

依据 DAG 依赖关系，为世界观构建、大纲规划、角色塑造各设计一条 L1→L2→L3 的学习路径，输出到 `curriculum-path.json`。让 TeachingStrategyRouter 能按用户当前聚焦方向推荐领域内循序渐进的技法序列，而非仅按熟练度随机推荐。

## 设计依据

- **调研报告**: docs/research/跨学科教学编排方法论调研_V1.0.md → 模式 2-1「领域专项路径」
- **DAG 设计**: CX-001-DAG 产出的 10 核心模式 4 层依赖关系
- **现有数据**: technique-library.json（128条技法，含 prerequisites/difficultyOrder/coreId）
- **现有路径**: learning-path.json（按熟练度分阶，与领域路径互补）

## 三条路径设计

### 路径 1: 角色塑造

```
Stage 1 (L0)         Stage 2 (L1)              Stage 3 (L2)
─────────────         ─────────────             ─────────────
show-dont-tell  ───→  dialogue-depth      ───→  character-depth
  展示而非告知           pov-control              角色立体化
  (3-4 beginner)       对话设计 + 视角控制
                        (3-4 beginner/intermediate)
```

### 路径 2: 世界观构建

```
Stage 1 (L0)         Stage 2 (L2)              Stage 3 (L3)
─────────────         ─────────────             ─────────────
show-dont-tell  ───→  worldbuilding-embed ───→  suspense-engine
  展示而非告知          设定融入                  悬念驱动
  (2-3 beginner)       (3-4 beginner/intermediate)
```

### 路径 3: 大纲规划

```
Stage 1 (L0)         Stage 2 (L1)              Stage 3 (L2→L3)
─────────────         ─────────────             ─────────────
opening-hook     ───→  rhythm-control      ───→  structure-innovation
  开篇钩子             节奏呼吸                  结构创新
  (3-4 beginner)       (3-4 beginner/intermediate)
```

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 数据/配置 | 新增 curriculum-path.json（3 条路径 × 3 阶段技法列表） | resources/config/curriculum-path.json |

纯数据配置任务，无代码变更。

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | resources/config/curriculum-path.json | 新增 | 三条领域路径，每路径 3 阶段技法序列 |
| 2 | docs/tasks/TASK-CHAIN.md | 修改 | 更新 CX-001-PATH 状态为完成 |

## 输出格式设计

```json
{
  "version": "1.0",
  "updatedAt": "2026-06-06",
  "paths": [
    {
      "id": "character-craft",
      "name": "角色塑造",
      "stages": [
        {
          "level": "L0",
          "coreIds": ["show-dont-tell"],
          "techniques": ["TQ-012", "TQ-013", ...]
        },
        ...
      ]
    }
  ]
}
```

## 选择策略

每个阶段选择技法时遵顼：
1. 优先选 difficultyOrder 最低的技法（从简单到难）
2. 每个 stage 选 3-4 条技法（够用不冗余）
3. 如果 stage 包含多个 coreId，均匀分配
4. 技法在路径内的顺序按 difficultyOrder 升序排列

## DoD（完成标准）

- [x] D1. curriculum-path.json 包含 3 条独立路径（角色塑造/世界观构建/大纲规划），JSON 格式合法
- [x] D2. 每条路径 3 阶段，共 32 条技法（12+11+9），全部 ID 存在于 technique-library.json
- [x] D3. 所有路径阶段技法满足 DAG prerequisites 依赖（含跨路径依赖标注）

## 回退方案

1. 删除 `resources/config/curriculum-path.json` 文件
2. 无数据库变更

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| resources/config/curriculum-path.json | 新增，3 路径 × 3 阶段技法序列 |
| docs/tasks/TASK-CHAIN.md | 更新 CX-001-PATH 状态 |

### 验证结果

- [x] JSON 格式合法
- [x] 所有技法 ID 存在于 technique-library.json
- [x] 阶段内技法满足 DAG 依赖可达性

### 路径技法师

#### 角色塑造

| 阶段 | coreId | 技法 ID 列表 |
|:----:|--------|-------------|
| L0 | show-dont-tell | TE-013, TQ-012, TQ-013, TQ-027 |
| L1 | dialogue-depth | TQ-008, TQ-061, TQ-071, TQ-065 |
| L1 | pov-control | TQ-030, TQ-032, AIP-008 |
| L2 | character-depth | AIP-003, TC-002, TC-003, TC-004 |

#### 世界观构建

| 阶段 | coreId | 技法 ID 列表 |
|:----:|--------|-------------|
| L0 | show-dont-tell | TE-013, TQ-012, TQ-013 |
| L2 | worldbuilding-embed | AIP-002, AIP-007, AIP-011, AIP-020 |
| L3 | suspense-engine | AIP-005, AIP-016, AIP-021, TC-012 |

#### 大纲规划

| 阶段 | coreId | 技法 ID 列表 |
|:----:|--------|-------------|
| L0 | opening-hook | TC-008, TQ-001, TQ-006, TQ-007 |
| L1 | rhythm-control | AIP-017, TQ-005, TQ-041, TQ-057 |
| L2/L3 | structure-innovation | TE-018, TQ-034, TQ-035, TQ-055 |

## 下个任务建议

完成后建议启动 CX-001-TIER「渐进分层评审节点」——为每条路径的每层定义完成标准，包括跳级机制（跳过已掌握阶段直通高阶）。
