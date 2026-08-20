// ─────────────────────────────────────────────────────────────
// training_evaluator 主题分组拆分：training_evaluator_dimension.dart（R-019 ≤300 行）
// 维度判断：趋势/达标率/稳定性/综合判断（classifySeverityTrend/classifyStability/comprehensiveJudgment 及输入类型）。逐字迁移自 training_evaluator.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'training_evaluator.dart';
// ─── 输入类型 ─────────────────────────────────────────────────

/// 严重度趋势输入
class SeverityTrendInput {
  final Severity currentSeverity;
  final Severity previousSeverity;
  final int occurrenceCount;

  const SeverityTrendInput({
    required this.currentSeverity,
    required this.previousSeverity,
    required this.occurrenceCount,
  });
}

/// 达标率输入
class PassRateInput {
  final int passCount;
  final int totalCount;

  const PassRateInput({required this.passCount, required this.totalCount});
}

/// FSRS 稳定性输入
class FsrsStabilityInput {
  final double currentStability;
  final double? previousStability;

  const FsrsStabilityInput({
    required this.currentStability,
    this.previousStability,
  });
}

/// 综合判断输入
class ComprehensiveJudgmentInput {
  final TrendJudgment severityTrend;
  final PassRateInput passRate;
  final FsrsStabilityInput? fsrsStability;

  const ComprehensiveJudgmentInput({
    required this.severityTrend,
    required this.passRate,
    this.fsrsStability,
  });
}

/// 恶化检测输入
const Map<Severity, int> _kSeverityOrder = {
  Severity.l1: 1,
  Severity.l2: 2,
  Severity.l3: 3,
};

/// 比较两次诊断的严重度判断趋势。
TrendJudgment classifySeverityTrend(SeverityTrendInput input) {
  final cur = _kSeverityOrder[input.currentSeverity]!;
  final prev = _kSeverityOrder[input.previousSeverity]!;

  if (cur < prev) return TrendJudgment.improving; // L3→L2/L1, L2→L1
  if (cur > prev) return TrendJudgment.worsening; // L1→L2/L3, L2→L3
  if (cur == prev && input.occurrenceCount > 1) {
    return TrendJudgment.worsening; // 反复出现
  }
  return TrendJudgment.stable;
}

// ─── 维度C: FSRS 稳定性 ─────────────────────────────────────

/// 比较 FSRS stability 判断趋势。
TrendJudgment classifyStability(FsrsStabilityInput input) {
  if (input.previousStability == null) return TrendJudgment.insufficientData;

  if (input.currentStability > input.previousStability!) {
    return TrendJudgment.improving;
  }
  if (input.currentStability < input.previousStability!) {
    return TrendJudgment.worsening;
  }
  return TrendJudgment.stable;
}

// ─── 综合判断 ────────────────────────────────────────────────

/// 三维度综合判断（对应 training-evaluation 中的综合判断规则表）
///
/// 批次6（6.12 A5）：first-match 顺序文档化——
///   1. 数据不足（无诊断无训练）→ insufficientData
///   2. 严重度恶化 → 无条件恶化（置顶短路，后续改善/稳定规则不再评估）
///   3. 严重度下降 + 高达标率 + 稳定度上升 → 明显改善
///   4. 严重度下降 + 达标率好 → 改善
///   5. 严重度不变 + 达标率好 + 稳定度上升 → 改善
///   6. 严重度不变 + 中等达标率 → 稳定
///   7. 严重度不变 + 很低达标率 + 稳定度下降 → 恶化趋势（比规则8 更严重，
///      必须在前，否则被规则8（pr<=0.4）遮蔽成死代码）
///   8. 严重度不变 + 低达标率 + 稳定度下降 → 可能恶化
///   兜底 → 稳定
/// 与恶化信号一致性：规则2 置顶保证 severityTrend=worsening 时不会输出
/// 改善类结论；detectDeterioration 的 relapse/worsening 也由规则2 覆盖。
/// 注意：newConcurrent/rebound 恶化信号若启用，须复核与综合判断的一致性。
ComprehensiveJudgment comprehensiveJudgment(ComprehensiveJudgmentInput input) {
  final severityTrend = input.severityTrend;
  final passRate = input.passRate;
  final fsrsStability = input.fsrsStability;

  // 数据不足
  if (severityTrend == TrendJudgment.insufficientData &&
      passRate.totalCount == 0) {
    return ComprehensiveJudgment.insufficientData;
  }

  final passRateVal = passRate.totalCount > 0
      ? passRate.passCount / passRate.totalCount
      : 0.0;
  final stabilityTrend = fsrsStability != null
      ? classifyStability(fsrsStability)
      : TrendJudgment.insufficientData;

  // 严重度恶化 → 无条件恶化（置顶短路）
  if (severityTrend == TrendJudgment.worsening) {
    return ComprehensiveJudgment.worsening;
  }

  // 严重度下降 + 高达标率 + 稳定度上升 → 明显改善
  if (severityTrend == TrendJudgment.improving &&
      passRateVal >= 0.6 &&
      stabilityTrend == TrendJudgment.improving) {
    return ComprehensiveJudgment.significantImprovement;
  }

  // 严重度下降 + 达标率好 → 改善
  if (severityTrend == TrendJudgment.improving && passRateVal >= 0.6) {
    return ComprehensiveJudgment.improving;
  }

  // 严重度不变 + 达标率好 + 稳定度上升 → 改善
  if (severityTrend == TrendJudgment.stable &&
      passRateVal >= 0.6 &&
      stabilityTrend == TrendJudgment.improving) {
    return ComprehensiveJudgment.improving;
  }

  // 严重度不变 + 中等达标率 → 稳定
  if (severityTrend == TrendJudgment.stable &&
      passRateVal >= 0.4 &&
      passRateVal < 0.6) {
    return ComprehensiveJudgment.stable;
  }

  // 批次6（6.12 A5）：恶化趋势（pr<0.2）必须先于可能恶化（pr<=0.4）判定，
  // 否则被规则8 遮蔽为死代码（first-match 顺序修正）
  // 严重度不变 + 很低达标率 + 稳定度下降 → 恶化趋势
  if (severityTrend == TrendJudgment.stable &&
      passRateVal < 0.2 &&
      stabilityTrend == TrendJudgment.worsening) {
    return ComprehensiveJudgment.worseningTrend;
  }

  // 严重度不变 + 低达标率 + 稳定度下降 → 可能恶化
  if (severityTrend == TrendJudgment.stable &&
      passRateVal <= 0.4 &&
      stabilityTrend == TrendJudgment.worsening) {
    return ComprehensiveJudgment.possibleWorsening;
  }

  return ComprehensiveJudgment.stable;
}

