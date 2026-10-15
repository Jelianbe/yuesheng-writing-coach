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
