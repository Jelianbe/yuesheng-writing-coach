// I10：臂间预算对等闸（arm-arm budget parity）
//
// ─────────────────────────────────────────────────────────────────────────
// 这个闸拦的不是「降级了所以结果差」，是「**降级了就不该拿来比**」。
// 因此它进 `I`（能不能比）而不进 `G`（好不好）。
//
// ── 为什么必须立 ──────────────────────────────────────────────────────────
// 臂阶梯 `A0–A4` 里 `A3 = A2 + 关系声明`。若实测得 `A3 − A2 ≈ 0`，有两种解释：
//   ① 关系层确实没有增量；
//   ② 关系层的**输入被削了**，所以它施展不开。
// 没有本闸，② 会一直藏在 ① 后面 —— 而且两种解释给出**同一个建议**（"别做关系层"）。
// 同向的两种原因是实验设计里最难拆的一对，因为结论一致，没人会去分辨。
//
// 机制上这个风险是实在的：`planMergeBudget` 会在超预算时逐级降级，而级序 a裁的
// `structureProfile` **正是 `A3` 关系声明的载体** ⇒ `A3` 比 `A2` 更容易被降级。
// 被削掉的恰是它要测的能力。
//
// ── 为什么按「对比对」写，不按臂写 ────────────────────────────────────────
// 这是同一种病的第二次。若写成「`A2` 与 `A3` 的 droppedStages 须相等」，
// 判据只修这一次的洞；`A4` 一排期（`A0+S2`，`+1`，旁支），同一个洞原地重新长出来，
// 而没人会想起来扩判据。判据的对象是**关系**，不是具体的那两个东西。
//
// 本轮生效的对比对是 `(A2, A3)`；`A4` 排期时自动生效 `(A0, A4)`，不需要改判据。
//
// ── 与 I4 的分工 ──────────────────────────────────────────────────────────
// `I4` 查**定义时**的同构（两臂的定义是不是只差一层）；
// `I10` 查**运行时**的同构（落跑的时候两臂拿到的输入是不是一样）。
// 同构得查两次：一次在纸上，一次在跑的时候。两者不重叠也不冗余。
// 「定义同构而输入不同构」是本轮唯一一个真实的混淆源。
//
// ── 前置条件（已核实，非假设）────────────────────────────────────────────
// `budget_report` 早就在落：`buildMergePromptSnapshotPayload` 把它写进
// merge prompt 快照载荷，缺省落 `error_logs`（info 级 / api 类）。
// ⇒ 本闸不需要新增采集，只需要一个消费方。这也是「存在、不叫失败、一次没真跑」
// 的第四例：字段齐全、每天都在产，**可观测而没人拿它当判据**。

import '../llm_call_log_sink.dart' show MergePromptSnapshotWriter;

/// 样本在某个对比对上的可比性裁决。
enum ArmParityVerdict {
  /// 可比：两臂预算对等（`droppedStages` 相等且都为空）。
  comparable,

  /// 不可比·预算降级：任一臂降过级，或两臂降级不一致。
  incomparableBudgetDegraded,

  /// 不可比·拒发：任一侧抛 `ProgressiveMergeOverBudget`（穷尽降级仍超限）。
  incomparableRejected,
}

/// 一条臂在一个样本上的运行结果（**只取本闸需要的字段**，其余不引入）。
class ArmRun {
  /// 臂标识（如 `A2` / `A3`）。
  final String armId;

  /// 该样本 ID（同一 `sample_id` 上两臂才可比）。
  final String sampleId;

  /// 实际发生的降级级名序列（空 = 未降级）。
  final List<String> droppedStages;

  /// 该臂是否因超预算被拒发（未发出请求）。
  final bool rejectedOverBudget;

  const ArmRun({
    required this.armId,
    required this.sampleId,
    this.droppedStages = const [],
    this.rejectedOverBudget = false,
  });
}

/// 一个对比对在一个样本上的裁决结果。
class ArmParityResult {
  /// 对比标识（如 `(A2,A3)`）。
  final String pair;

  final String sampleId;

  final ArmParityVerdict verdict;

  /// 触发降级的臂（空 = 无降级）。用于剔除时说明「剔掉的是哪一类章」。
  final List<String> degradedArms;

  /// 不对等时给出可读的差异说明（供剔除记录引用）。
  final String? reason;

  const ArmParityResult({
    required this.pair,
    required this.sampleId,
    required this.verdict,
    this.degradedArms = const [],
    this.reason,
  });

  bool get isComparable => verdict == ArmParityVerdict.comparable;
}

/// 判据 1：任一臂拒发（超预算穷尽降级仍超限，未发出请求）。
ArmParityResult? _judgeRejected(String pairLabel, ArmRun x, ArmRun y) {
  if (!x.rejectedOverBudget && !y.rejectedOverBudget) return null;
  final which = <String>[
    if (x.rejectedOverBudget) x.armId,
    if (y.rejectedOverBudget) y.armId,
  ];
  return ArmParityResult(
    pair: pairLabel,
    sampleId: x.sampleId,
    verdict: ArmParityVerdict.incomparableRejected,
    degradedArms: which,
    reason: '${which.join('、')} 超预算拒发（未发出请求）',
  );
}

/// 判据 2：两臂降级级名不等。
ArmParityResult? _judgeUnequalDropped(
  String pairLabel,
  ArmRun x,
  ArmRun y,
  List<String> xDropped,
  List<String> yDropped,
) {
  final same =
      xDropped.length == yDropped.length &&
      xDropped.join('') == yDropped.join('');
  if (same) return null;
  final which = <String>[
    if (xDropped.isNotEmpty) '${x.armId}:${xDropped.join("+")}',
    if (yDropped.isNotEmpty) '${y.armId}:${yDropped.join("+")}',
  ];
  return ArmParityResult(
    pair: pairLabel,
    sampleId: x.sampleId,
    verdict: ArmParityVerdict.incomparableBudgetDegraded,
    degradedArms: which,
    reason: '降级级名不等（${which.join(' vs ')}）',
  );
}

/// 判据 3：两臂**齐降**（相等但都非空）。
///
/// 本闸最易漏的一格：判据若写成「须相等」而不写「须相等**且都为空**」，
/// 两臂齐降会静默通过—— 而「相等」在这里恰恰是坏消息：
/// 两臂输入同样被削，对比依然不成立。
ArmParityResult? _judgeBothDegraded(
  String pairLabel,
  ArmRun x,
  ArmRun y,
  List<String> xDropped,
) {
  if (xDropped.isEmpty) return null;
  return ArmParityResult(
    pair: pairLabel,
    sampleId: x.sampleId,
    verdict: ArmParityVerdict.incomparableBudgetDegraded,
    degradedArms: [x.armId, y.armId],
    reason: '两臂**齐降**（${xDropped.join('+')}）—— 相等不等于可用',
  );
}

/// 判一对臂在一个样本上是否可比（纯函数，不发请求、不落库）。
///
/// 判据（按对比对，不按臂）：
///   1. 任一臂 `rejectedOverBudget` ⇒ [ArmParityVerdict.incomparableRejected]；
///   2. 两臂 `droppedStages` **不等** ⇒ [ArmParityVerdict.incomparableBudgetDegraded]，
///      并给出是哪几臂降了级；
///   3. 两臂相等但**都非空** ⇒ 同上 verdict（**相等地降级仍然是降级**）；
///   4. 其余 ⇒ 可比。
ArmParityResult judgeArmParity({
  required String pair,
  required ArmRun x,
  required ArmRun y,
}) {
  assert(x.sampleId == y.sampleId, '臂间对比须落在同一 sample_id 上');

  final label = '($pair)';
  final rejected = _judgeRejected(label, x, y);
  if (rejected != null) return rejected;

  final xDropped = x.droppedStages.toList()..sort();
  final yDropped = y.droppedStages.toList()..sort();

  final unequal = _judgeUnequalDropped(label, x, y, xDropped, yDropped);
  if (unequal != null) return unequal;

  final bothDegraded = _judgeBothDegraded(label, x, y, xDropped);
  if (bothDegraded != null) return bothDegraded;

  return ArmParityResult(
    pair: label,
    sampleId: x.sampleId,
    verdict: ArmParityVerdict.comparable,
  );
}

/// 剔除非可比样本后的计数。**`n_excludedBudget` 必须与 `n` 并列报出**
/// —— 只报 `n` 会让「剔了多少」消失在读数里。
class ArmParitySummary {
  /// 生效的对比对（如 `(A2,A3)`）。
  final String pair;

  /// 送入判定的臂运行条数（= 样本数 × 2）。
  final int totalRuns;

  /// 可比样本数。
  final int comparable;

  /// 因预算降级剔除的样本数（`n_excluded_budget` 的一部分）。
  final int excludedBudget;

  /// 因拒发剔除的样本数。
  final int excludedRejected;

  /// 被剔除样本的裁决明细（供报告写「剔掉的是哪一类章」）。
  final List<ArmParityResult> excluded;

  const ArmParitySummary({
    required this.pair,
    required this.totalRuns,
    required this.comparable,
    required this.excludedBudget,
    required this.excludedRejected,
    required this.excluded,
  });

  /// 剔除比例。
  double get excludedRate =>
      totalRuns == 0 ? 0 : (excludedBudget + excludedRejected) / totalRuns;

  /// 占比 > 5% ⇒ 主对比结论**一律标「受限」**。
  ///
  /// 注意措辞：不是「结果不可用」，是「必须写清剔了多少、剔掉的是哪一类章」。
  bool get conclusionConstrained => excludedRate > 0.05;

  Map<String, dynamic> toJson() => {
    'pair': pair,
    'n_runs': totalRuns,
    'n_comparable': comparable,
    'n_excluded_budget': excludedBudget,
    'n_excluded_rejected': excludedRejected,
    'excluded_rate': excludedRate,
    'conclusion_constrained': conclusionConstrained,
    'excluded': [
      for (final e in excluded)
        {
          'sample_id': e.sampleId,
          'verdict': e.verdict.name,
          'arms': e.degradedArms,
          if (e.reason != null) 'reason': e.reason,
        },
    ],
  };
}

/// 批量判定并汇总（纯函数）。
///
/// [runs] 必须已按 `sample_id` 配好对：同一 `sample_id` 恰好两条（x / y）。
/// 配对缺失**不算降级**，本函数不猜 —— 抛 [ArgumentError]，
/// 因为「配错对」与「降级」是两个不同的病，混在一起会让剔除理由失真。
ArmParitySummary summarizeArmParity({
  required String pair,
  required List<ArmRun> runs,
}) {
  final bySample = <String, List<ArmRun>>{};
  for (final r in runs) {
    (bySample[r.sampleId] ??= <ArmRun>[]).add(r);
  }

  final results = <ArmParityResult>[];
  for (final entry in bySample.entries) {
    final list = entry.value;
    if (list.length != 2) {
      throw ArgumentError(
        'sample_id=${entry.key} 有 ${list.length} 条臂运行，'
        '本闸按对比对判定，须恰好 2 条。'
        '「配错对」与「预算降级」是两个不同的病，混在一起剔除理由会失真。',
      );
    }
    results.add(judgeArmParity(pair: pair, x: list[0], y: list[1]));
  }

  final excluded = results
      .where((r) => !r.isComparable)
      .toList(growable: false);
  return ArmParitySummary(
    pair: '($pair)',
    totalRuns: results.length,
    comparable: results.length - excluded.length,
    excludedBudget: excluded
        .where((r) => r.verdict == ArmParityVerdict.incomparableBudgetDegraded)
        .length,
    excludedRejected: excluded
        .where((r) => r.verdict == ArmParityVerdict.incomparableRejected)
        .length,
    excluded: excluded,
  );
}

/// 从 merge prompt 快照载荷还原一条臂运行（纯数据变换）。
///
/// 载荷形状由 `buildMergePromptSnapshotPayload` 产出：
/// `budget_report.levels[]` 每项含 `stage`；`budget_report.levels` 为空即未降级。
/// **拒发不进快照**（超预算拒发时不发送）⇒ `rejectedOverBudget` 只能由调用方
/// 从 `ProgressiveMergeOverBudget` 的捕获处传入，不由本函数推断。
ArmRun armRunFromSnapshot({
  required String armId,
  required String sampleId,
  required Map<String, dynamic> snapshotPayload,
  bool rejectedOverBudget = false,
}) {
  final levels = snapshotPayload['budget_report'] is Map
      ? (snapshotPayload['budget_report'] as Map)['levels']
      : null;
  final dropped = <String>[
    if (levels is List)
      for (final l in levels)
        if (l is Map && l['stage'] != null) l['stage'].toString(),
  ];
  return ArmRun(
    armId: armId,
    sampleId: sampleId,
    droppedStages: dropped,
    rejectedOverBudget: rejectedOverBudget,
  );
}

/// 快照收集器工厂（测试与离线分析用；不触碰 DB / 全局单例）。
MergePromptSnapshotWriter collectingSnapshotWriter(
  List<Map<String, dynamic>> sink,
) {
  return (Map<String, dynamic> payload) => sink.add(payload);
}
