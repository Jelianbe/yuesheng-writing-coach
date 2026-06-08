# CX-001-DAG: 技法知识依赖图标注

> **优先级**: P1 | **状态**: ready | **预估**: 1d
> **依赖**: T-036（话术生效化完成）| **后续**: CX-001-PATH（三条路径原型）
> **来源**: 跨学科教学编排方法论调研 — docs/research/跨学科教学编排方法论调研_V1.0.md

## 目标

为 technique-library.json 中 128 条技法逐条标注 `prerequisites` 前置依赖字段，形成完整的有向无环图（DAG）。让 TeachingStrategyRouter 在选择技法时能过滤"用户尚未掌握前置条件"的技法，实现知识依赖驱动的教学推荐。

## 设计依据

- **调研报告**: docs/research/跨学科教学编排方法论调研_V1.0.md → 模式 1-1「知识依赖图（DAG）」、B 章共通原则#1「知识依赖图」
- **DAG 设计**: 已确定的 10 核心模式 4 层依赖关系（详见 task-chain.md V8.0 §一）
- **现有数据**: technique-library.json（128条技法，含 difficulty/difficultyOrder/coreId/applicableSyndromes）
- **路径规划**: 三条独立路径——角色塑造、世界观构建、大纲规划

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 数据/配置 | 128 条技法逐条新增 prerequisites 字段 | resources/config/technique-library.json |

纯数据标注任务，无代码变更。

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | resources/config/technique-library.json | 修改 | 128 条技法新增 prerequisites 字段 |

## DAG 设计（10 核心模式 4 层依赖）

```
分层   核心模式                   前置依赖              所属路径
───   ────────                  ────────              ──────
L0    show-dont-tell            (无)                  角色/世界观
L0    opening-hook              (无)                  大纲

L1    dialogue-depth            show-dont-tell         角色
L1    pov-control               show-dont-tell         角色
L1    rhythm-control            opening-hook           大纲

L2    character-depth           show-dont-tell         角色
                               + dialogue-depth
L2    worldbuilding-embed       show-dont-tell         世界观
                               + rhythm-control

L3    suspense-engine           rhythm-control         综合
                               + worldbuilding-embed
                               + character-depth
L3    structure-innovation      opening-hook           大纲
                               + rhythm-control
                               + character-depth

(特殊) negative-example         show-dont-tell         辅助
                               (先知道"好"长什么样)
```

## 标注规则

### 字段格式
每条技法新增 `prerequisites` 字段，值为前置技法 ID 数组：
```json
{
  "id": "TQ-004",
  "name": "证据链式悬念",
  "prerequisites": ["TQ-011", "TQ-002"],
  ...
}
```

### 同 coreId 内依赖
| difficultyOrder | 前置规则 |
|:--------------:|---------|
| 1 (beginner) | 一般无同模式内前置（作为该模式的入口）|
| 2 (intermediate) | 依赖该模式下 1-2 条 difficultyOrder=1 的技法 |
| 3 (advanced) | 依赖 1-2 条 difficultyOrder=2 的技法 |

### 跨 coreId 依赖
按顶层 DAG 映射。例如 suspense-engine 的技法至少依赖一条 rhythm-control 技法 + 一条 worldbuilding-embed 技法。

### 前置选择原则
- 选择在内容上最基础的、逻辑上应该先掌握的技法作为前置
- 不要为了填充而添加无关前置
- 无前置的情况设为空数组 `[]`

## DoD（完成标准）

- [x] D1. 全部 128 条技法已标注 prerequisites 字段，JSON 格式合法
- [x] D2. 依赖图无回路（可拓扑排序），128/128 节点可达
- [x] D3. 统计产出：有前置 112 条 / 平均 2.4 个 / 最长链 6 层 / 各 coreId 平均前置数已输出

## 回退方案

1. `git checkout resources/config/technique-library.json` 恢复原文件
2. 无数据库变更

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| resources/config/technique-library.json | 128 条技法新增 prerequisites 字段 |

### 验证结果

- [x] JSON 格式合法
- [x] 依赖图无回路
- [x] 无孤立节点
- [x] 输出统计结果

### 统计结果

```
总技法数：128
有前置的技法数：112（16 条 L0 技法无前置）
平均前置数：2.4
最长依赖链长度：6（从 L0 → L3 的路径节点数）
各 coreId 平均前置数：
  show-dont-tell: 1.3
  opening-hook: 0.0
  dialogue-depth: 2.3
  pov-control: 2.0
  rhythm-control: 2.0
  character-depth: 2.9
  worldbuilding-embed: 2.9
  suspense-engine: 3.1
  structure-innovation: 4.1
  negative-example: 1.0
```

### 执行方式

通过 Python 脚本 [scripts/annotate_prerequisites.py](../../scripts/annotate_prerequisites.py) 自动标注，规则如下：
1. **同 coreId 内部依赖**：difficultyOrder=2 依赖 1-2 条 order=1 技法；order=3 依赖 1-2 条 order=2 技法
2. **跨 coreId 依赖**：按 10 核心模式 4 层 DAG 映射，从依赖 coreId 选取最简单的技法
3. **去重**：同 coreId 内部 + 跨 coreId 合并后去重

## 下个任务建议

完成后建议启动 CX-001-PATH「三条独立路径原型」——依据 DAG 为世界观构建、大纲规划、角色塑造各设计一条 L1→L2→L3 的学习路径，输出到 curriculum-path.json。
