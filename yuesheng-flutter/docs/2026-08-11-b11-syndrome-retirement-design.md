# 症候淘汰/合并机制设计（b9 注册表真源化适配 · O10 更新版）

> 状态：**设计稿，不实现**（预置规则，代码落地待后续排期）
> 对应清单：待办执行清单 6.6（O10）
> 前置设计：`docs/2026-08-11-b6-syndrome-id-lifecycle-design.md`（批次 6 初版，规则延续于此）
> 适配背景：b9 注册表真源化（批次 27-31）后，症候元数据唯一真源已从 `skill_layers.syndromeIds` 迁移到 `syndrome_registry.kSyndromeRegistry`，b6 的「对接点」已过时，需按新架构重写落地形态。当前活跃症候 32 个（P003-P034）。

## 1. 背景与现状

- **真源变化**：`lib/services/syndrome_registry.dart` 的 `kSyndromeRegistry`（`SyndromeRecord` × 32）是症候元数据唯一真源；表格行/计数/ID 列表/测试断言全部从它派生（b9）。
- **派生现状**（均从注册表派生，退役机制需要动的点）：
  - `kSyndromeIds`（注册表派生 → `skill_layers.syndromeIds` / `kTrainingSyndromeIds` / 四库测试权威集合）
  - 症候库索引表 / 类型速查表 / 技法映射表行渲染（`syndrome_knowledge_base.dart`）
  - 技法库 L2 症候→技法映射表行渲染（`technique_knowledge_base.dart` `_l2TechniqueMapRow`）
  - v1/v2 动作映射表行、maxAttempts 分组、training-templates-index 行（`skill_registry.dart`）
  - 提示文本 4 处（`$_syndromeIdRange` / `${kSyndromeRegistry.length}`）
- **已有退役/合并先例**（均无运行时代码映射表，仅历史留痕 + 测试白名单）：
  - `P001 → P004`（信息倾泻症合并，注册表从 P003 起，P001/P002 不在注册表内）
  - `P002 → P009`（角色空心化合并）
  - `H001 → P013`、`H002 → P013`（更早编号系统的合并，b6 记载）
  - 四库 #9 测试当前以硬编码 `retiredSyndromes = {'P001','P002'}` 放行历史说明中的退役 ID
- **消费方**：`countTrainingForSyndrome`（`training_input_builder.dart` L40）按 ID 聚合训练计数；`chat_service.dart` L898 有「次数+表现合并查询」替代路径；FSM 评估依赖 teaching_history 聚合。

## 2. 规则延续（b6 已定，本次不变）

1. **ID 永不复用**：症候/技法/动作 ID 一经分配永久保留，退役后不得重新分配；新 ID 从当前最大值 +1 连续递增。
2. **退役标记**：退役症候不进 L2 上下文加载、L3 检索、诊断输出与 Teacher 建议目标；**定义文本保留**供历史数据解释（不回删手册段/训练段）。
3. **合并映射表**：全局常量 `旧 ID → 新 ID`，读取聚合前归一 `effectiveId = mergeMap[id] ?? id`；写入方不归一（保留原始 ID 保证历史可追溯）。
4. **退役 ID 不允许出现在诊断 JSON 的 `syndrome_id`**。

## 3. b9 架构适配（核心变化）

### 3.1 退役字段落在注册表（而非知识库条目）

`SyndromeRecord` 新增 3 个可选字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `retired` | `bool?` | 默认 `null`（false）。true 表示已退役 |
| `retiredReason` | `SyndromeRetiredReason?` | 枚举：`merged`（并入其它症候）/ `removed`（删除，不再教学） |
| `mergedInto` | `String?` | 仅 `merged` 时有：并入的目标症候 ID（必须指向注册表内活跃症候） |

新增枚举 `SyndromeRetiredReason`（`merged` / `removed`）。

> 退役症候**保留在 `kSyndromeRegistry` 列表内**（含手册段/训练段文本），只是元数据标记退役——ID 语义、历史引用、定义可追溯三者都成立。

### 3.2 派生函数改造

| 函数 | 现状 | 改造后 |
|---|---|---|
| `kSyndromeIds` | 全量 ID 列表 | **活跃集合**（过滤 `retired == true`），保持「诊断/检索用集合」语义 |
| `kRetiredSyndromeIds` | 无 | 新增：退役 ID 列表（`retired == true` 的 id） |
| `kAllSyndromeIds` | 无 | 新增：`kSyndromeIds + kRetiredSyndromeIds`（保序，历史说明白名单用） |
| `kSyndromeMergeMap` | 无 | 新增：`Map<String, String>` 真源，预置 `'P001':'P004'`、`'P002':'P009'`、`'H001':'P013'`、`'H002':'P013'` |
| `effectiveSyndromeId(String id)` | 无 | 新增：`kSyndromeMergeMap[id] ?? id`（读取聚合归一） |

### 3.3 渲染层自动过滤退役

所有表格行渲染循环（`_syndromeIndexRow` / `_typeLookupTable` / 手册技法映射 / `_l2TechniqueMapRow` / v1/v2 动作映射 / maxAttempts / training-templates-index）改为只遍历**活跃**症候：

- 症候库索引表 / 类型速查表 / 技法映射表：遍历 `kSyndromeRegistry.where((s) => !s.retired)`
- 技法库 L2 映射表 / skill_registry 动作映射 / maxAttempts / templates-index：同上
- 头部计数「N 种」：`kSyndromeIds.length`（活跃数）
- 提示文本 `$_syndromeIdRange`：由 `kSyndromeIds` 首尾派生（自动跳过退役）

> 渲染函数若对活跃/退役共用同一循环，统一加 `.where((s) => s.retired != true)` 过滤，避免逐行特判。

### 3.4 四库测试改造

| 测试 | 改造 |
|---|---|
| #1 权威集合 | `validSyndromes` 仍 = `kSyndromeIds`（活跃）；「ID 升序连续」断言改为按注册表**原始顺序**检查（退役记录在列表中保持原位，不参与活跃连续性） |
| #2 / #3 存在性 | 活跃症候必须存在手册段 `### P0XX` / 训练段 `## P0XX`；退役症候**可选存在**（保留定义文本，不强制） |
| #9 悬空引用 | 白名单改为 `kSyndromeIds ∪ kRetiredSyndromeIds ∪ kSyndromeMergeMap.keys`（从注册表派生，删除测试内硬编码 `retiredSyndromes`）；正则 `\bP0(0\d|1\d|2\d|3\d)\b` 维持（覆盖到 P039，P040 时扩 `4\d`） |
| #12 双向逐字 | 渲染行断言循环遍历活跃；反向行数断言对齐 `kSyndromeIds`（活跃） |
| `syndrome_registry_test` 新增 | R8 退役字段自洽：`retired=true` 必须有 `retiredReason`；`merged` 必须有 `mergedInto` 且指向活跃 ID；`retired` 症候的 `mergedInto` 不得为退役 ID；活跃集合与退役集合无重叠 |
| 消费方测试 | 训练计数聚合：构造含旧 ID 的历史记录，断言 `effectiveSyndromeId` 归一后统计正确 |

### 3.5 消费方接入点（合并映射归一）

1. `countTrainingForSyndrome`（`training_input_builder.dart` L40）：按 `effectiveSyndromeId` 聚合
2. `chat_service.dart` L898 合并查询路径：同上
3. 学生模型复盘聚合（teaching_history 按症候统计处）：同上
4. 诊断输出校验（`diagnosis_validator.dart`）：退役 ID 不允许出现在诊断 JSON `syndrome_id`（补充规则，当前无退役症候不生效，预置校验逻辑）

### 3.6 内容型保留点清理策略（退役时）

| 内容 | 处理 |
|---|---|
| 手册重叠规则表 | 删除涉及退役症候的行（如该症候与其它症的优先级） |
| 类型分组表（skill_registry 手写） | 删除退役症候条目；如组内仅剩空则整组评估 |
| 技法索引表「适用症候」精选列 | 删除仅指向退役症候的引用；与活跃症候共用的保留 |
| 四库 #8 pairs | 删除涉及退役症候的对 |
| `_l2AltColumn` namedGroup | 移除退役症候 ID（无实际影响，保持整洁） |

> 手册段/训练段正文**保留**（历史解释用），与 §2 规则 2 一致。

## 4. 实施顺序（后续排期，本设计不落地）

1. **注册表**：`SyndromeRecord` 加 3 字段 + `SyndromeRetiredReason` 枚举 + `kRetiredSyndromeIds` / `kAllSyndromeIds` / `kSyndromeMergeMap` / `effectiveSyndromeId`
2. **渲染层过滤**：各库渲染循环加活跃过滤（§3.3），跑通 #12 双向断言
3. **测试改造**：§3.4 全量更新，注册表测试补 R8
4. **消费方归一**：§3.5 三处接入
5. **退役白名单派生**：四库 #9 白名单改从注册表派生
6. **验证**：`flutter analyze` 0 + 全量 `flutter test`；构造一个测试退役症候走通全链路后移除

## 5. 验收标准

- 退役症候不出现在 L2/L3 注入、诊断输出、Teacher 建议、类型速查/索引/动作映射/训练索引所有表格
- 历史记录按 `kSyndromeMergeMap` 归一后，训练计数/复盘统计与退役前一致
- 四库 #9 白名单完全派生（无硬编码退役 ID）
- 注册表自洽：活跃集合 + 退役集合 + 合并映射无冲突（R8 兜底）
- 新症候编号无复用（`kAllSyndromeIds` 不重叠）

## 6. 与 b6 的关系

- b6 规则一/二/三（ID 永不复用、退役标记、合并映射）**全部延续**，仅落地载体从「知识库条目字段」改为「注册表 `SyndromeRecord` 字段」。
- b6 对接点 1（`skill_layers.syndromeIds` 拆 active/retired）**废弃**——`skill_layers.syndromeIds` 已派生自 `kSyndromeIds`，退役过滤在注册表层完成即可。
- b6 对接点 5（阶段 7 扩容强制连续递增）**已达成**——四库 #1 已断言 ID 连续递增，b10 三症候（P032-P034）验证通过。
- 新增：退役白名单派生化（#9）、退役字段自洽测试（R8）、消费方归一测试。
