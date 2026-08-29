# Skill 速查表（SKILLS-QUICKREF）

> 服务于 R-030 反馈处理工作流的 **Step 1（Skill 库遍历与选型）**。
> 用途：拿到一个任务后，快速判断「该挂哪个 / 哪几个 Skill」。

## 使用方式

1. 先看下方「场景反查表」粗定方向
2. 再到「分组清单」确认具体 Skill id
3. **最后必须回到源文件核对**：description 列是索引性归纳，
   **实际语义与激活条件以源文件内容为准**（尤其 content 首部的定位自述）

```bash
# 按 id 定位源文件与定义
grep -rn "id: '<skill-id>'" lib/services/skills_*.dart

# 查看该 Skill 的正文首部（定位 / 覆盖 / loadWhen）
grep -A20 "id: '<skill-id>'" lib/services/skills_*.dart
```

## 场景反查表

| 任务场景 | 优先查这些组 |
|:--|:--|
| 诊断用户文本、判定症候 | `diagnosis` |
| 教学介入、讲解、示范 | `teaching`、`coaching` |
| 训练闭环（出题 / 批改 / 评估） | `training` |
| 对话节奏、如何接住用户 | `coaching` |
| 语气 / 态度档位 | `attitude` |
| 产品定位与铁律约束 | `core` |
| 用户进入进阶阶段（P3/P4） | `advanced` |

---

## 分组清单（29 个，按 `SkillMeta.group`）

### `core`（3）— 产品定位与铁律

| id | 归纳 | 源文件 |
|:--|:--|:--|
| `core-product-identity` | 产品身份定位 | `skills_l1_core_p1.dart` |
| `core-iron-triangle` | 核心铁律（不可违背的约束） | `skills_l1_core_p1.dart` |
| `teaching-strategy` | 教学策略总纲 | `skills_l1_core_p1.dart` |

### `teaching`（6）— 教学引导

| id | 归纳 | 源文件 |
|:--|:--|:--|
| `beginner-path` | 新手引导路径（N0–N2） | `skills_beginner_p5.dart` |
| `narrative-design` | 叙事 / 世界观 / 角色构建引导 | `skills_beginner_p7.dart` |
| `writing-style` | 文笔风格 | `skills_beginner_p1.dart` |
| `reader-awareness` | 读者意识 | `skills_beginner_p1.dart` |
| `revision-methodology` | 修改方法论 | `skills_beginner_p1.dart` |
| `diagnosis-confirmation` | 诊断确认环节 | `skills_diagnosis_p1.dart` |

### `coaching`（7）— 教练行为

| id | 归纳 | 源文件 |
|:--|:--|:--|
| `coaching-rhythm` | 对话节奏引擎（何时问 / 何时收） | `skills_beginner_p3.dart` |
| `coaching-actions-v2` | 教练动作集 | `skills_diagnosis_p1.dart` |
| `teaching-modes` | 教学模式切换 | `skills_training_p1.dart` |
| `demonstration` | 示范（I do） | `skills_training_p1.dart` |
| `model-rewrite` | 改写示范 | `skills_training_p1.dart` |
| `timed-rewrite` | 限时改写训练 | `skills_training_p1.dart` |
| `writer-psychology` | 写作者心理 | `skills_attitude.dart` |

### `diagnosis`（4）— 诊断

| id | 归纳 | 源文件 |
|:--|:--|:--|
| `syndrome-diagnosis-index` | 症候库索引（L2/L3 检索入口） | `skill_registry.dart` |
| `outline-diagnosis` | 大纲结构诊断 | `skills_advanced_outline_p1.dart` |
| `gap-detector` | 差距检测 | `skills_diagnosis_p1.dart` |
| `feedback-cognition` | 反馈认知（⚠️ 与 `coaching-rhythm §五` 内容重叠，未决） | `skills_diagnosis_p3.dart` |

### `training`（5）— 训练闭环

| id | 归纳 | 源文件 |
|:--|:--|:--|
| `training-loop-v2` | 训练主循环 | `skills_training_p1.dart` |
| `training-templates-index` | 训练模板索引 | `skill_registry.dart` |
| `training-evaluation-v2` | 训练评估 | `skills_training_p1.dart` |
| `technique-library-index` | 技法库索引（L2/L3 检索入口） | `skill_registry.dart` |
| `text-surgery-v2` | 文本手术（针对性改写） | `skills_training_p1.dart` |

### `attitude`（3）— 态度档位

| id | 归纳 | 源文件 |
|:--|:--|:--|
| `attitude-doubao` | 豆包档（默认） | `skills_attitude.dart` |
| `attitude-yuesheng` | 月笙如歌档 | `skills_attitude.dart` |
| `attitude-sensei` | sensei 档 | `skills_attitude.dart` |

### `advanced`（1）— 进阶阶段

| id | 归纳 | 源文件 |
|:--|:--|:--|
| `advanced-phases` | P3/P4 进阶阶段指引（按教学阶段裁剪注入） | `skills_advanced_outline_p1.dart` |

---

## 注意事项

- **注入方式**：Skill 由 `skill_dispatcher.dart` 按上下文调度，
  不是全部注入。改 Skill 内容 = 改实际注入的 prompt，属**高风险**
  （R-027 门禁 4 需人工签字）。
- **Phase 3 裁剪**：`advanced-phases` 与 `coaching-rhythm` 已接入
  `contentForPhase`，按教学阶段裁剪注入内容。改这两处要先冻结行为锚点。
- **A 类豁免**：Skill 内容以 Dart 常量形式存在、用 part 拆分，
  属 R-019 的 A 类纯常量豁免范围，**不算伪拆分**，可放心按领域分区。
- **重叠未决**：`feedback-cognition` 与 `coaching-rhythm §五` 存在
  内容重叠，使用前确认是否会造成重复注入。

---

*建立：2026-08-29（原缺口：R-030 Step 1 引用的速查表原位于已归档的
Electron 目录，Flutter 侧此前不存在）。*
*数据基准：2026-08-29 从 `lib/services/skills_*.dart` 的
`SkillMeta(id, group)` 实测提取。*
