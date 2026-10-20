// ─────────────────────────────────────────────────────────────
// intervention_value — 干预价值门槛的消费层（W-19-A）
//
// 设计稿：docs/designs/2026-10-15-W19-干预价值门槛-四步原则-设计稿.md
//
// 职责：把 LLM 评定的 intervention_value 档位落到**展示排序**上——
//   主序 severity（L3 > L2 > L1，既有口径不变），
//   同 severity 档内按干预价值降序（high > medium > low > null）。
//
// 边界（验收原文锁定）：
//   - 只影响卡片展示顺序，**不动落库集合与落库顺序**
//     （ADR-C67「识别到多少报多少 = 诊断须全量落库」不受影响）；
//   - 不做任何「文本好坏」判断（无硬否决白名单，R-009）；
//   - 纯函数：不改输入列表，无副作用。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// ★ 干预价值（S3）三判据 —— **唯一定义源**（2026-10-20 治理续批第二批 · 路 α · R-027 批准）。
///
/// 由来：W-19-B（2026-10-16）把 S3 三判据 + 正交性铁律写进 merge 链的
/// `_kMergeGuidanceBlock`（`progressive_diagnosis.dart`）；治理续批第二批的**路 α**
/// 要让**单次链**也输出 `intervention_value`（否则单次链 iv 恒 null ⇒ A3 评分端
/// 只能回填先验，iv 断供未从生产端根除）。
///
/// ★ 为什么抽成共享常量（不复制两份）：
///   两处 prompt 宿主（merge 链 / 单次链）必须**逐字同一套判据**——LLM 若在两条
///   链上看到措辞不同的 S3，同一文本会得到不同档位，跨链读数不可比。
///   复制两份 = 维护面 ×2 且必然漂移（W-19-B 报批稿已否决过一次 A 案复制方案）。
///   ⇒ 唯一定义 + 两宿主各插值引用 1 次（护栏 `w19_b_prompt_layer_guard_test.dart` ①
///   与治理续批批护栏共同守此不变量）。
///
/// ⚠️ 改动本常量 = 改 prompt ⇒ **必过 R-027**（舰长批准）。
const String kInterventionValueS3Criteria =
    '''干预价值（S3）三判据——对每条准备报出的症候依次自问，全「是」=high，两条「是」=medium，其余=low：
1. 可教：存在一个作者现在就能做的具体训练动作（改写练习/重写某段/自查清单），而非「需要全书级重构才解决」；
2. 可感：干预效果作者自己当章可感知（读得下去/看得懂的变化），不依赖后续章节验证；
3. 可测：有明确的复测口径（下轮诊断同一症候是否收敛），可进「诊断收敛」叙事。
铁律：intervention_value 与 severity 相互独立，不得互为别名或函数——L3 严重但本轮干预不动它（如全文视角混乱需重写架构）应为 low；L1 轻微但一次改写练习立竿见影（如三连排比的情绪标签）应为 high。不得因「这段文本写得好」而豁免或抬升任何条目；写得好的部分不因此获得任何加分。''';

/// ★ 形态字段评定段 —— **唯一定义源**（2026-10-20 治理续批第二批 · R-027 批准）。
///
/// 语义与 T-20261014-12 组合⑤判据**逐字同源**：成段多事实（≥3 条）+ 结构标记
/// = 倾泻成形；单句带过一律封顶 L1。
///
/// ★ 为什么必须是 LLM 显式输出的双要素（不得派生）：
///   W-23 数据实证（脚本实测 2026-10-20，报告见 `.ai/reports/2026-10-20-治理续批-形态字段与资格闸v2与路α-设计批.md` §2.2）：
///   P002 全库 154 次检出的 evidence 条数分布 L2 {1:7,2:50,3:58,4:2} vs
///   L1 {1:9,2:10,3:3} 高度重叠 ⇒ **证据条数分不开真假**；更硬的陷阱：
///   X01|t03|r2 与 X22|t03|r1 两锚点 P002 的 evidence **均为 3 条**而形态结论相反；
///   X01|t07|r1 更是「3 个事实旁白但无论文式结构」⇒ 连 fact_count 单值都分不开。
///   ⇒ 任何以 evidence.length / severity 派生的实现都在这些格上必错。
const String kFormFieldCriteria =
    '''对信息倾泻/量形式类症候（如 P002），在 JSON 中附带两个形态要素，其余症候省略：
- form_fact_count (int): 成段出现的设定/背景事实条数；单句带过 = 1
- form_structure (string): expository = 论文式/说明书结构（「原因有二：其一……」）；interruption = 读者关切时刻被打断；narrative = 嵌在叙事流中、无结构标记
两要素与严重度组合⑤判据同源：成段多事实（≥3 条）+ 结构标记 = 倾泻成形；单句带过一律封顶 L1。''';

/// 诊断卡展示排序：severity 主序降序 + 同档内干预价值降序（稳定排序）。
///
/// 输入顺序即解析顺序；返回新列表，输入不被修改。
/// severity 越界值按 L1 处理（Severity.fromString 缺省），与既有消费点一致。
List<Syndrome> sortSyndromesForDiagnosisCard(List<Syndrome> syndromes) {
  int severityRank(Severity s) => switch (s) {
    Severity.l3 => 2,
    Severity.l2 => 1,
    Severity.l1 => 0,
  };
  final sorted = List<Syndrome>.of(syndromes);
  sorted.sort((a, b) {
    final bySeverity = severityRank(b.severity) - severityRank(a.severity);
    if (bySeverity != 0) return bySeverity;
    return interventionValueRank(b.interventionValue) -
        interventionValueRank(a.interventionValue);
  });
  return sorted;
}
