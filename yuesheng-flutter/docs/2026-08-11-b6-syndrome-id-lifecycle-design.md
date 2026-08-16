# 症候 ID 淘汰/合并规则设计（批次6 6.6 · O10）

> 状态：**设计稿，不实现**（本批次仅预置规则，代码落地待阶段 7 或后续排期）
> 对应清单：待办执行清单 6.6（O10）

## 1. 背景与现状

- 症候 ID 采用 `P###` 编号（P003-P022 共 20 个活跃症候），`lib/services/skill_layers.dart` 的
  `syndromeIds` 是 L3 检索层唯一权威列表。
- 已有合并先例：**H001/H002 已合并至 P013**（迁移仅 git history 留痕，无运行时代码映射表）。
- 症候 ID 被多方持久引用：`teaching_history`（学生模型）、`teacher_suggestion`、`active_problems`、
  `diagnosis` 记录、统计/复盘逻辑（如 countTrainingForSyndrome）。**ID 复用会污染历史数据语义**。

## 2. 规则一：ID 永不复用

- 症候 ID 一经分配永久保留，**退役后不得重新分配给新症候**。
- 新症候编号从当前最大值 +1 连续递增（当前 P022 → 下一新症候 P023）。
- 理由：诊断/训练/建议的历史记录都以 ID 为键，复用会导致「旧记录被新症候错误解读」。
- 技法（T###）、动作（A###）ID 遵循同一原则。

## 3. 规则二：退役标记（淘汰）

- 症候知识库条目（`syndrome_knowledge_base.dart`）支持 `retired: true` + `retiredReason` 字段：
  - `retiredReason: 'merged'`（并入其它症候）或 `'removed'`（删除，不再教学）。
- 退役症候：
  - 不进 L2 上下文加载与 L3 检索（`syndromeIds` 移入 `retiredSyndromeIds`）；
  - 不再进入诊断输出与 Teacher 建议目标；
  - **保留定义文本**供历史数据解释（不回删知识库条目）。

## 4. 规则三：合并映射表

- 全局常量 `syndromeMergeMap: Map<String, String>`（旧 ID → 新 ID）。
- 首个条目（历史先例补录）：`'H001' -> 'P013'`、`'H002' -> 'P013'`。
- 消费方（统计/复盘/训练计数等读历史记录处）在按 ID 聚合前先归一：
  `effectiveId = syndromeMergeMap[id] ?? id`。
- 写入方不归一遍（保留原始 ID，保证历史可追溯）；仅读取聚合时归一。

## 5. 与现有代码的对接点（后续实施顺序）

1. `skill_layers.dart`：`syndromeIds` 拆分为 `activeSyndromeIds` + `retiredSyndromeIds`；
   新增 `syndromeMergeMap` 常量（H001/H002→P013）。
2. `syndrome_knowledge_base.dart`：知识条目增加退役元数据。
3. 消费方接入点（合并映射归一）：
   - 训练计数 `countTrainingForSyndrome` 及 student_model 复盘聚合；
   - 诊断历史统计（FSM 评估依赖的 teaching_history 聚合）。
4. 诊断输出校验：退役 ID 不允许出现在诊断 JSON 的 `syndrome_id`。
5. 阶段 7（P023-P027 扩容）启动时，扩容流程强制走「新 ID 连续递增」检查。

## 6. 验收标准（后续实施完成时）

- 退役症候不出现在 L2/L3 注入与诊断建议中；
- 历史记录按 `syndromeMergeMap` 归一后统计结果与退役前一致；
- 新症候编号无复用（`active ∪ retired` 编号不重叠）。
