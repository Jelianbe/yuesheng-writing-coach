// ─────────────────────────────────────────────────────────────
// merge_convergence — 长文合并机械收敛层（W-15-A，验收④）
//
// 设计稿：docs/designs/2026-10-15-W15-超上下文策略与合并收敛-设计稿v2.md §3.4
//
// 动因：merge prompt 的「数量原则（超过 5 条保留前 5）」是**纯 prompt 软约束**，
// 模型可违约（同章实测 25/16/25/19 条，_kMergeRelevanceGate 注释取证）。
// 本层把「去重 + 排序 + 条数上限」变为**代码侧机械执行**。
//
// 边界（ADR-C67 全量落库裁决不受影响）：
//   - 收敛只作用于**卡片展示集合**（诊断结果卡显示前 5 条）；
//   - 落库集合 = diagnosis.syndromes 全量，本层不参与 commit 链路；
//   - `syndromeCount` 仍报全量条数（用户可见「共诊断 N 条，卡片详列前 5」）；
//   - 溢出条目不丢弃：[ConvergenceReport.overflow] 携带全量，供后续
//     W-15-B 接「feedback_summary 概括」与日志。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../types/teaching_types.dart';
import 'intervention_value.dart';

/// 收敛执行报告（入日志/快照，W-15-B 接快照落库）。
class ConvergenceReport {
  /// 收敛前条数（= diagnosis.syndromes.length，全量）
  final int rawCount;

  /// 去重后条数（同 id + 证据交并比 ≥ 阈值者合并）
  final int dedupedCount;

  /// 展示条数（≤ kMergeDisplayCap）
  final int displayedCount;

  /// 溢出条目（排序在 [kMergeDisplayCap] 之后，未上卡，未丢弃）
  final List<Syndrome> overflow;

  const ConvergenceReport({
    required this.rawCount,
    required this.dedupedCount,
    required this.displayedCount,
    required this.overflow,
  });
}

/// 展示收敛上限（与 merge prompt「数量原则」的 5 条同口径）。
const int kMergeDisplayCap = 5;

/// 证据交并比阈值（设计稿 §3.4 待批项 ②，舰长批量批稿时一并放行）。
const double kEvidenceJaccardThreshold = 0.5;

/// 归一化单条证据（去空白 + 小写，用于集合比对）。
Set<String> _normalizedEvidence(List<String> evidence) => evidence
    .map((e) => e.replaceAll(RegExp(r'\s+'), '').toLowerCase())
    .where((e) => e.isNotEmpty)
    .toSet();

/// 两条症候的证据交并比（Jaccard；任一方为空集 → 0，不合并）。
double evidenceJaccard(List<String> a, List<String> b) {
  final sa = _normalizedEvidence(a);
  final sb = _normalizedEvidence(b);
  if (sa.isEmpty || sb.isEmpty) return 0;
  final inter = sa.intersection(sb).length;
  final union = sa.union(sb).length;
  return union == 0 ? 0 : inter / union;
}

/// 同 id 高重叠合并：severity 取最高，evidence 取并集，name/explanation
/// 取先出现者（首个非空）。
Syndrome _mergeTwo(Syndrome keep, Syndrome other) {
  return Syndrome(
    syndromeId: keep.syndromeId,
    name: keep.name,
    severity: keep.severity.index >= other.severity.index
        ? keep.severity
        : other.severity,
    evidence: {...keep.evidence, ...other.evidence}.toList(),
    explanation: keep.explanation,
    readerImpact: keep.readerImpact ?? other.readerImpact,
    interventionValue: _higherValue(
      keep.interventionValue,
      other.interventionValue,
    ),
  );
}

String? _higherValue(String? a, String? b) =>
    interventionValueRank(a) >= interventionValueRank(b) ? a : b;

/// 机械收敛：去重 → 排序（复用 W-19-A 展示排序）→ 截前 [kMergeDisplayCap] 条。
///
/// 纯函数：不改输入列表。返回（展示条目, 报告）。
({List<Syndrome> displayed, ConvergenceReport report}) mergeOutputConvergence(
  List<Syndrome> syndromes,
) {
  // 1. 去重：按 syndromeId 分组，组内贪心合并（证据重叠 ≥ 阈值）
  final byId = <String, List<Syndrome>>{};
  for (final s in syndromes) {
    byId.putIfAbsent(s.syndromeId, () => []).add(s);
  }
  final deduped = <Syndrome>[];
  for (final group in byId.values) {
    final kept = <Syndrome>[];
    for (final s in group) {
      final twin = kept.indexWhere(
        (k) =>
            evidenceJaccard(k.evidence, s.evidence) >=
            kEvidenceJaccardThreshold,
      );
      if (twin >= 0) {
        kept[twin] = _mergeTwo(kept[twin], s);
      } else {
        kept.add(s);
      }
    }
    deduped.addAll(kept);
  }

  // 2. 排序（severity 主序 + 同档内干预价值降序，复用 W-19-A）
  final sorted = sortSyndromesForDiagnosisCard(deduped);

  // 3. 截前 kMergeDisplayCap 条（溢出不丢弃，进报告）
  final displayed = sorted.take(kMergeDisplayCap).toList();
  final overflow = sorted.skip(kMergeDisplayCap).toList();

  final report = ConvergenceReport(
    rawCount: syndromes.length,
    dedupedCount: deduped.length,
    displayedCount: displayed.length,
    overflow: overflow,
  );
  debugPrint(
    '[W-15-A] merge 收敛: raw=${report.rawCount} deduped=${report.dedupedCount} '
    'displayed=${report.displayedCount} overflow=${report.overflow.length}',
  );
  return (displayed: displayed, report: report);
}
