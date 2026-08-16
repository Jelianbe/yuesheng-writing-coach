# 设计稿：症候增删耦合治理 — SyndromeRegistry 真源化（b9）

> 批次 27-31 · 2026-08-11 · 用户确认方向（注册表真源化）

## 一、背景与问题诊断

### 1.1 现状：新增/删减一个症候要触碰 ~30 处

扫描 P028（批次 23 最新接入症候）全部引用，触点分布：

| 类别 | 触点 | 处数 |
|---|---|---|
| 同一事实多处复制 | 症候名+一句话：索引表 / 类型分组表 / training-templates-index / 类型速查表 | 4-5 处 |
| 技法映射重复 | P028→T001/T002 同时写入 L2 映射表、L3 映射表、`kTechniquesBySyndrome`、手册内嵌表 | 4 处 |
| 动作映射重复 | `coaching-actions` 与 `coaching-actions-v2` 两张表 | 2 处 |
| ID 列表重复 | `skill_layers.syndromeIds` 与 `kTrainingSyndromeIds` | 2 处 |
| 计数硬编码 | 「29 种」「P003-P031」「仅含 29 条」散落 6+ 处 | 6 处 |
| 测试手写期望 | 数量断言 / ID 列表 / pairs 手抄进 4 个测试文件 | 6 处 |
| 文档同步 | 资产清单 / 待办清单 / 审查包 | 3 处 |

**根因**：症候**元数据**（id/名称/一句话/类型/层级/技法映射/动作映射/maxAttempts）本质是结构化数据，却被手写进 markdown 表格和多处计数，每次增删都要同步 30 个点 → 少改/漏改/多改。

**已有兜底**：四库一致性测试（four_libraries_consistency_test）已防「漏改」，但没有解决「重复劳动」本身。

### 1.2 目标

- 新增症候 = 注册表 +1 条元数据 + 手册段 + 训练段（内容型仍人工写）
- 删减症候 = 注册表 −1 条 + 删对应手册段 + 训练段
- 所有**表格行、计数、ID 列表、测试断言**从注册表派生，不再手抄
- **渲染输出与现有 markdown 逐字一致**（零行为回归，由测试快照兜底）

## 二、真源设计：SyndromeRecord

新建 `lib/services/syndrome_registry.dart`（独立文件，被五库 import）。

```dart
/// 症候元数据（增删症候的唯一入口；内容型段落不在此处）
class SyndromeRecord {
  final String id;            // 'P028'
  final String name;          // 全名（手册/类型速查/v1 动作映射用）：'画面感缺失症'
  final String shortName;     // 短名（索引关键词/精简处用）：'画面感缺失'
  final String keyword;       // 索引表「问题类型关键词」列（独立字段，非名称）：'通篇抽象概述'
  final String oneLine;       // 一句话描述（索引表/类型速查/training-templates-index 共用）
  final SyndromeType type;    // expressive_deficit / structural_disorder / motivation_deficit / commercial_appeal
  final SkillLevel level;     // l1-l5（复用 syndrome_skill_levels.dart 的 SkillLevel）
  final MaxAttemptsGroup group; // expression(≤3) / structure(≤5) / deep(≤5)
  final String position;      // chapter / serial / global
  final List<String> techniques; // 首选在首位：['T001','T002']
  final List<String> actions;    // 首选在首位：['A006','A004']
  final String? v1ActionName; // v1 动作映射专用名（含合并括号注释时用，如 '信息倾泻症（含原 P001 子类型）'）
}

/// 类型速查 / 类型分组（症候类型）
enum SyndromeType { motivationDeficit, expressiveDeficit, structuralDisorder, commercialAppeal }

/// maxAttempts 分组（对齐 skill_registry 训练轮次上限）
enum MaxAttemptsGroup { expression, structure, deep }

/// 注册表（真源）：29 条（P003-P031），按 ID 升序
const List<SyndromeRecord> kSyndromeRegistry = [ /* 全量数据 */ ];

/// 派生：ID 有序列表（替代 skill_layers.syndromeIds / kTrainingSyndromeIds）
List<String> get kSyndromeIds => kSyndromeRegistry.map((s) => s.id).toList();

/// 派生：技能层级映射（替代 syndrome_skill_levels.dart 手写 Map）
Map<String, SkillLevel> get kSyndromeSkillLevelsDerived => {for (final s in kSyndromeRegistry) s.id: s.level};
```

### 2.1 字段映射说明（每张表的取数规则）

| 表 | 位置 | 取数字段 |
|---|---|---|
| 症候库索引表 | syndrome_knowledge_base.dart `kSyndromeIndexContent` | id / keyword / oneLine |
| 症候库类型速查表 | syndrome_knowledge_base.dart「症候类型速查」 | type→中文 / name / oneLine |
| 症候库手册内嵌技法映射表 | syndrome_knowledge_base.dart「写作技巧提示」 | name / techniques[0]→技法名 |
| 技法库 L2 表 | technique_knowledge_base.dart「症候→技法映射（速查）」 | id / techniques 全量（斜杠格式特例保留） |
| 技法库 L3 表 | technique_knowledge_base.dart 全库映射表 | name / techniques |
| `kTechniquesBySyndrome` | technique_knowledge_base.dart | id → techniques |
| 注册表类型分组表 | skill_registry.dart「类型分组」 | type→中文 / id+name |
| v1 动作映射 | skill_registry.dart `coaching-actions` | v1ActionName ?? name / actions |
| v2 动作映射 | skill_registry.dart `coaching-actions-v2` | shortName ?? name / actions |
| maxAttempts 分组 | skill_registry.dart「轮次上限」 | group / id 列表 |
| training-templates-index | skill_registry.dart「教学知识索引」 | id / shortName / oneLine |

### 2.2 内容型段落（不真源化，保留人工编写）

- 手册正文段 `### P0XX`（核心问题/触发信号/判断原则/严重度/例外/few-shot/推荐教学动作）
- 训练知识段 `## P0XX`（核心本质/教学要点/常见误区/严重度参考/素材库）
- 重叠优先级规则表（语义内容，带解释文本，保留手写；仅校验涉及 ID 合法）
- 手册头部「分类句」（P003-P013 基础症候…批次描述）——叙述性文本，保留人工，仅计数派生

## 三、渲染函数（零回归约束）

每个知识库文件内新增**行渲染函数**，输出与该文件现有表格行**逐字一致**（含格式特例）：

```dart
// syndrome_knowledge_base.dart
String _syndromeIndexRow(SyndromeRecord s) =>
    '| ${s.id} | ${s.keyword} | ${s.oneLine} |';

String _typeLookupRow(SyndromeRecord s) =>
    '| ${_typeLabel(s.type)} | ${s.name} | ${s.oneLine} |';
```

**格式特例逐字保留**（从现有内容抄录为渲染规则）：
1. 技法 L2 表备选列斜杠：P006 `T017/T018/T022`、P023 `T018 欲扬先抑法`（首项带技法名，其余仅 ID）——渲染函数需逐症候复现现有字符串
2. 动作映射无备选：`| P005 视角漂移 | A002 回归主角 | — |`
3. 动作映射多备选：`| P006 节奏停滞 | A003 五问法 | A005 动作链 / A009 节奏变速 |`
4. v1 名称带合并注释：`P004 信息倾泻症（含原 P001 子类型）`，v2 精简为 `P004 信息倾泻`
5. 类型速查 name 与索引 keyword 不同（独立字段，已入 schema）

> 若某行因特例无法用通用函数表达，允许注册表加 `notes` 字段或渲染函数 switch 该 id，**优先保持逐字一致**而非强迫统一。

## 四、各文件改造方案

| 文件 | 改造 |
|---|---|
| `lib/services/syndrome_registry.dart` | 新建：SyndromeRecord + 29 条数据 + 派生函数 |
| `lib/services/syndrome_skill_levels.dart` | `kSyndromeSkillLevels` 改为派生（保留 `skillLevelOf`/`skillLevelForBeginner`/介入级别） |
| `lib/services/skill_layers.dart` | `syndromeIds` 改为派生 |
| `lib/services/training_knowledge_base.dart` | `kTrainingSyndromeIds` 改为派生 |
| `lib/services/syndrome_knowledge_base.dart` | 索引表/类型速查/技法映射表行改为渲染；头部计数派生 |
| `lib/services/technique_knowledge_base.dart` | L2/L3 表行改为渲染；`kTechniquesBySyndrome` 派生 |
| `lib/services/skill_registry.dart` | 类型分组/动作映射×2/maxAttempts 分组/training-templates-index 行改为渲染；提示文本计数派生（P003-P031 范围、全量 29） |
| 4 个测试文件 | 断言全部从注册表派生（见 §五） |
| 文档 3 份 | 最终批次同步 |

**提示文本 4 处**（skill_registry L468/L793/L1086/L1202）：`P003-P031` 改为派生范围 `${kSyndromeIds.first}-${kSyndromeIds.last}`；「全量 29」改为 `${kSyndromeRegistry.length}`。若未来 ID 跳号，提示改为「共 N 症候」。

## 五、测试改造

所有手写期望改从注册表派生，新增「渲染输出 == 内容」双向断言：

1. **four_libraries_consistency_test.dart**：
   - `validSyndromes` = `kSyndromeIds.toSet()`（替代 `kSyndromeSkillLevels.keys`）
   - #1 数量 = `kSyndromeRegistry.length`，循环上界 = 末位 ID（不硬编码 31）
   - #8 pairs 保留（语义关系），新增「pairs 引用 ID 均 ∈ 注册表」
   - 新增 #12「注册表行渲染一致性」：对每个症候，断言索引行/类型速查行/技法行实际出现在对应内容字符串中（双向：注册表→内容 且 内容→注册表）
2. **syndrome_skill_levels_test.dart**：#S1 数量派生 + `skillLevelOf` 断言改为遍历注册表
3. **syndrome_technique_knowledge_test.dart**：索引 ID 列表 = `kSyndromeIds`；新增「training-templates-index 行派生一致」
4. **skill_registry_l2_test.dart**：索引覆盖断言从注册表生成期望；「仅含 N 条」= 派生计数
5. 新增 **syndrome_registry_test.dart**：注册表自身合法性（ID 升序连续、name 非空、type/level/group 合法、techniques/actions 非空、技法/动作 ID 在对应库存在）

## 六、批次规划（保守分阶段，每批独立 commit + 四闸）

| 批次 | 内容 | 四闸要求 |
|---|---|---|
| 27 | **基础设施**：新建 syndrome_registry.dart（全量 29 条数据）+ syndrome_registry_test；skill_layers / training_knowledge_base / syndrome_skill_levels 三处 ID/层级改派生；四库一致性测试 validSyndromes 改从注册表 | analyze 0 + 全量 test |
| 28 | **症候库行渲染**：kSyndromeIndexContent 索引表行、类型速查表行、技法映射表行改渲染；头部计数派生 | analyze 0 + 全量 test |
| 29 | **技法库行渲染**：L2/L3 表行 + kTechniquesBySyndrome 派生 | analyze 0 + 全量 test |
| 30 | **注册表行渲染**：类型分组/动作映射×2/maxAttempts/training-templates-index 行改渲染；提示文本 4 处计数派生 | analyze 0 + 全量 test |
| 31 | **测试全面派生化 + 文档同步**：4 个测试断言改注册表派生；资产清单/待办清单/审查包同步 | analyze 0 + 全量 test |

> 每批四闸全绿后独立 commit 带批次号；批次 27 先落地真源与派生基础，避免后续批次脱离防漂移保护。

## 七、风险与边界

- **行为回归**（最高风险）：渲染函数必须逐字复现现有 markdown → 每批四闸 + 渲染一致性断言兜底；如某行特例无法复现，宁可保留手写行 + 注册表校验其 ID 合法，不强行生成
- **内容型段落不受影响**：手册正文/训练段/重叠规则仍人工编写，真源只管元数据
- **token 影响**：渲染输出与现状逐字一致 → 各库体积估算不变；注册表文件本身不进 prompt（仅构建期消费）
- **不触碰**：P001/P002 历史、退役机制（b6）、技法/动作库本体定义
- **ID 顺序**：注册表按 ID 升序；派生计数/范围依赖该顺序（批次 27 测试断言升序）
