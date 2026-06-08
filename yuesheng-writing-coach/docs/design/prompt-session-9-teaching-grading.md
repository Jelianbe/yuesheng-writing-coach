# 会话9提示词：教学分级机制——技法筛选矩阵 + 学习路径

## 项目背景

月笙写作教练的技法库（technique-library.json）现在是 107 条技法（89 TQ/TC/TN + 18 TE），覆盖 10 个核心模式。每条技法都有 `difficulty`（beginner/intermediate/advanced）和 `difficultyOrder`（1/2/3）字段。

但系统目前**没有根据用户水平过滤技法的机制**。当 AI 决定教什么技法时，107 条全部可用，导致：
- 新手可能被推荐 advanced 技法（超出理解范围）
- 老手可能被推荐 beginner 技法（觉得无聊）
- 学习路径不清晰——没有"先学什么、再学什么"的引导

## 任务

创建两个配置文件，实现教学分级：

1. **technique-selection-matrix.json**：用户水平 × 核心模式 → 最大难度限制
2. **learning-path.json**：按用户水平定义核心模式的学习顺序和跳过规则

## 必须读取的文件

1. `resources/config/technique-library.json` — 107 条技法，含 difficulty/difficultyOrder/coreId
2. `docs/teaching/technique-library/index_V1.md` — 核心模式一览和各模式难度分布
3. `resources/config/user-type-map.json` — 用户类型定义（newbie/experienced）
4. `resources/config/education-theory-fragments.json` — 教育学规则 R-001~R-003（用户水平→教学方式）
5. `docs/design/teaching-strategy-notes.md` — 用户类型矩阵（新手/老手/理工型/感性型）
6. `src/renderer/shared/types.ts` — TechniqueInfo 接口定义

## 执行步骤

### Step 1：统计现有技法难度分布

先阅读 technique-library.json，统计各核心模式的难度分布：

```
核心模式         共计  B  I  A  B占  I占  A占
─────────────────────────────────────────────
show-dont-tell    8    2  4  2  25%  50%  25%
suspense-engine   18  10  7  1  56%  39%   6%
pov-control       5    2  2  1  40%  40%  20%
structure-innovation 7 1  4  2  14%  57%  29%
worldbuilding-embed  8  4  4  0  50%  50%   0%
character-depth   12   8  4  0  67%  33%   0%
dialogue-depth    14   5  7  2  36%  50%  14%
rhythm-control    14   9  4  1  64%  29%   7%
opening-hook      8    8  0  0 100%   0%   0%
negative-example  1    1  0  0 100%   0%   0%
─────────────────────────────────────────────
总计             107  50 36 21  47%  34%  20%
```

### Step 2：创建 technique-selection-matrix.json

基于统计，定义每个用户水平在每个核心模式下的 maxDifficultyOrder：

```json
{
  "version": "1.0",
  "updatedAt": "2026-06-06",
  "defaultMaxDifficulty": {
    "beginner": {
      "maxDifficultyOrder": 1,
      "override": {}
    },
    "intermediate": {
      "maxDifficultyOrder": 2,
      "override": {}
    },
    "advanced": {
      "maxDifficultyOrder": 3,
      "override": {}
    }
  }
}
```

**默认逻辑**：
- beginner：只推荐 difficultyOrder ≤ 1（beginner 技法）
- intermediate：推荐 difficultyOrder ≤ 2（beginner + intermediate）
- advanced：全量（difficultyOrder ≤ 3）

**特殊情况覆盖（override）**：某些核心模式对新手特别友好或不友好，需要手动调整。

例如：
- `opening-hook`：8 条全是 beginner，即使 beginner 也可以选多条
- `show-dont-tell`：beginner 只有 2 条，可能不够用，可以允许 beginner 接触部分 intermediate 技法
- `dialogue-depth`：beginner 只有 5 条，intermediate 有 7 条，但对话对新手难度较高——慎重

**判断标准**：

设置 override 时考虑：
1. 该模式 beginner 技法数量是否充足（≥3 条够用，否则考虑开放部分 intermediate）
2. 该模式对新手的重要性（开篇/节奏/人物重要，负面教材/视角/结构相对可以晚点）
3. 从 beginner→intermediate→advanced 的递进是否自然

### Step 3：创建 learning-path.json

定义每个用户水平的学习路径（核心模式的学习顺序）：

```json
{
  "version": "1.0",
  "updatedAt": "2026-06-06",
  "beginner": {
    "description": "新手期：核心目标是'能写、敢写'",
    "phases": [
      {
        "phase": 1,
        "name": "建立信心",
        "corePatterns": [
          {
            "id": "show-dont-tell",
            "reason": "展示而非告知是网文最基础、最重要的技能，上手快、见效明显"
          },
          {
            "id": "opening-hook",
            "reason": "开篇钩子是新人最需要掌握的开局技能，能快速看到效果"
          }
        ],
        "maxTechniquesPerPattern": 2
      },
      {
        "phase": 2,
        "name": "基础构建",
        "corePatterns": [
          {
            "id": "character-depth",
            "reason": "角色立体化是创作的核心，新手容易忽略"
          },
          {
            "id": "rhythm-control",
            "reason": "节奏呼吸帮助新人控制文脉流动"
          }
        ],
        "maxTechniquesPerPattern": 3
      },
      {
        "phase": 3,
        "name": "初步进阶",
        "corePatterns": [
          {
            "id": "suspense-engine",
            "reason": "悬念驱动略微抽象，放在基础之后"
          },
          {
            "id": "dialogue-depth",
            "reason": "对话涉及多角色，有一定复杂度"
          }
        ],
        "maxTechniquesPerPattern": 2
      }
    ],
    "skipPatterns": ["negative-example", "pov-control", "structure-innovation", "worldbuilding-embed"]
  },
  "intermediate": {
    "description": "进阶期：核心目标是'写得稳、写得巧'",
    "phases": [
      {
        "phase": 1,
        "name": "深化基础",
        "corePatterns": [
          {
            "id": "show-dont-tell",
            "reason": "从 beginner 变种过渡到 intermediate 变种"
          },
          {
            "id": "character-depth",
            "reason": "深化人物塑造，开始接触矛盾动机和弧光"
          }
        ],
        "maxTechniquesPerPattern": 3
      },
      {
        "phase": 2,
        "name": "结构控制",
        "corePatterns": [
          {
            "id": "pov-control",
            "reason": "视角控制在 intermediate 阶段更容易理解"
          },
          {
            "id": "rhythm-control",
            "reason": "深化节奏控制，学习更复杂的呼吸技巧"
          },
          {
            "id": "structure-innovation",
            "reason": "结构创新需要一定基础才能理解和应用"
          }
        ],
        "maxTechniquesPerPattern": 3
      },
      {
        "phase": 3,
        "name": "全面覆盖",
        "corePatterns": [
          {
            "id": "dialogue-depth",
            "reason": "对话层次到了需要系统掌握的阶段"
          },
          {
            "id": "worldbuilding-embed",
            "reason": "世界观融入对进阶作者很关键"
          },
          {
            "id": "suspense-engine",
            "reason": "开始学习更复杂的悬念设计"
          }
        ],
        "maxTechniquesPerPattern": 3
      }
    ],
    "skipPatterns": ["negative-example"]
  },
  "advanced": {
    "description": "高手期：核心目标是'突破瓶颈、建立风格'",
    "phases": [
      {
        "phase": 1,
        "name": "深度打磨",
        "corePatterns": [
          {
            "id": "show-dont-tell",
            "reason": "学习 advanced 变种，如沉默替代法、冰山情绪法"
          },
          {
            "id": "suspense-engine",
            "reason": "悬念驱动的 advanced 变种，如群体智商锚定法"
          }
        ],
        "maxTechniquesPerPattern": 2
      },
      {
        "phase": 2,
        "name": "突破创新",
        "corePatterns": [
          {
            "id": "structure-innovation",
            "reason": "结构创新的 advanced 变种"
          },
          {
            "id": "dialogue-depth",
            "reason": "对话层次的 advanced 变种"
          }
        ],
        "maxTechniquesPerPattern": 3
      }
    ],
    "skipPatterns": ["negative-example", "opening-hook"]
  },
  "syndromeOverride": {
    "description": "当用户特定症候突出时，优先推荐该症候对应的核心模式",
    "syndromePatternMap": {
      "P001": ["worldbuilding-embed"],
      "P002": ["character-depth"],
      "P003": ["show-dont-tell"],
      "P004": ["worldbuilding-embed"],
      "P005": ["pov-control"],
      "P006": ["rhythm-control"],
      "P007": ["structure-innovation", "suspense-engine"],
      "P009": ["character-depth"],
      "P010": ["character-depth", "dialogue-depth"]
    }
  }
}
```

**设计 learning-path 的参考原则**：

1. **beginner 阶段只保留 5-6 个核心模式**：新手一次面对 10 个模式会瘫痪。把 `pov-control`、`structure-innovation`、`negative-example`、`worldbuilding-embed` 留给进阶阶段
2. **每个阶段 2-3 个模式**：一次只专注 1-2 个模式，防止信息过载
3. **show-dont-tell 永远是第一**：这是最基础的技法，任何水平都应该先巩固
4. **opening-hook 只给新手**：老手已经不需要学了
5. **syndromeOverride**：如果用户被诊断出特定症候，优先推荐该症候对应的模式

**答案来源**：
- 这个 JSON 的结构设计参考了教育学蒸馏中的 R-001（beginner→案例驱动）、R-011~R-015（多症候优先级）以及 `user-type-map.json` 的用户类型定义
- 每个模式的难度分布来自 technique-library.json 的实际统计
- 模式之间的顺序参考了写作教学常识和你（月笙如歌）在 case-ayuan 中展示的教学直觉——"先建立信心，再深化基础，最后突破瓶颈"

### Step 4：验证

运行 `npx tsc --noEmit` 确认编译通过。

## 补充说明

### 为什么同时需要两个文件？

| 文件 | 控制 | 用途 |
|------|------|------|
| technique-selection-matrix.json | **宽度** | 哪些技法可用？→ 过滤 |
| learning-path.json | **顺序** | 先学哪个模式？→ 排序 |

两者配合：
```
userLevel = beginner
  → learning-path.json 选择 intermediate 的 phase 1
  → 对 phase 1 中的每个 corePattern
    → technique-selection-matrix.json 过滤出 beginner 可用技法
    → 按 difficultyOrder 排序推荐
```

### 第三个配置（前置依赖）为什么不做？

技法的前置依赖关系（如"双线蒙太奇依赖视角控制基础"）目前手动标注成本高且容易出错。建议 Phase 3 通过实际教学数据（用户学习轨迹）来自动推断前置关系，比手动标注更准确。

## 休止符条件

| 条件 | 说明 |
|:----:|------|
| ✅ technique-selection-matrix.json 已创建 | 含 3 级默认配置 + 合理的 override |
| ✅ learning-path.json 已创建 | 含 3 级详细路径 + syndromeOverride 映射 |
| ✅ 两个 JSON 的统计数据与 technique-library.json 一致 | 难度分布核实过 |
| ✅ npx tsc --noEmit 通过 | |

## 输出物

| 文件 | 操作 |
|------|------|
| `resources/config/technique-selection-matrix.json` | **新建** |
| `resources/config/learning-path.json` | **新建** |

## 核心原则

1. **数据驱动**：修改默认配置时引用统计数据支撑（"这个模式 beginner 只有 2 条，所以开放难度 2"）
2. **新手优先**：宁少勿多。新手一次面对超过 4 个模式就是信息轰炸
3. **可迭代**：配置是为 Phase 3 的 TeachingStrategyRouter 准备的，不需要一次完美，后续可以调整
