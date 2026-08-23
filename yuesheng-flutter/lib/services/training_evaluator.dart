/// P3-1 训练评估引擎
///
/// 将 training-evaluation skill 中的确定性规则从 LLM prompt 迁移到代码。
/// LLM 保留自然语言生成能力，决策逻辑由本模块完成。
///
/// 真源：yuesheng-android/src/services/training-evaluator.ts
///
/// 提供：
///   1. 严重度趋势 (A) — 数值比较
///   2. 达标率计算 (B) — 纯算术
///   3. FSRS 稳定性 (C) — 数值比较
///   4. 综合判断 — 三维度整合
///   5. 恶化检测 — 信号检测
///   6. 教学状态迁移 — FSM
///   7. 最小数据量检查
library;

import 'package:writingcoach/types/teaching_types.dart';

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

class DeteriorationCheckInput {
  final String syndromeId;
  final Severity currentSeverity;
  final Severity previousSeverity;
  final bool wasResolvedToL1;
  final int consecutiveFailures;
  final bool reboundPattern;
  final int gapDays;
  final int newConcurrentSyndromes;

  const DeteriorationCheckInput({
    required this.syndromeId,
    required this.currentSeverity,
    required this.previousSeverity,
    required this.wasResolvedToL1,
    required this.consecutiveFailures,
    required this.reboundPattern,
    required this.gapDays,
    required this.newConcurrentSyndromes,
  });
}

/// 恶化检测结果
class DeteriorationResult {
  final DeteriorationSignal? signal;
  final String intervention;

  const DeteriorationResult({this.signal, required this.intervention});
}

/// 教学状态迁移输入
// ─── 恶化检测 ────────────────────────────────────────────────

/// 检测恶化信号并返回干预建议。
DeteriorationResult detectDeterioration(DeteriorationCheckInput input) {
  final currentSeverity = input.currentSeverity;
  final previousSeverity = input.previousSeverity;
  final wasResolvedToL1 = input.wasResolvedToL1;
  final consecutiveFailures = input.consecutiveFailures;
  final reboundPattern = input.reboundPattern;
  final gapDays = input.gapDays;
  final newConcurrentSyndromes = input.newConcurrentSyndromes;

  // 复发：已降至 L1 后再次 L2/L3
  if (wasResolvedToL1 && _kSeverityOrder[currentSeverity]! >= 2) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.relapse,
      intervention: '回到 Lv.1 训练，换一种教学方式',
    );
  }

  // 恶化：连续 2 次 severity 上升
  if (_kSeverityOrder[currentSeverity]! > _kSeverityOrder[previousSeverity]! &&
      consecutiveFailures >= 2) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.worsening,
      intervention: '停止训练该症候。改为自然语言讨论，寻找根本原因',
    );
  }

  // 新并发：新出现 ≥3 个症候
  if (newConcurrentSyndromes >= 3) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.newConcurrent,
      intervention: '回到诊断确认阶段，让学员挑一个最关心的先练',
    );
  }

  // 反弹：连续 3 次达标后突然连续 2 次未达标
  if (reboundPattern) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.rebound,
      intervention: '检查是否跳过了难度。如果是→降回之前的难度。如果不是→检查学员状态',
    );
  }

  // 巩固失败：间隔 > 7 天后 L2+
  if (gapDays > 7 && _kSeverityOrder[currentSeverity]! >= 2) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.consolidationFail,
      intervention: 'FSRS 稳定度不足。增加该症候的训练频率',
    );
  }

  return const DeteriorationResult(signal: null, intervention: '');
}

class StateTransitionInput {
  final bool trainingStarted;
  final int consecutiveLowSeverity;
  final int consecutivePasses;
  final int fsrsIntervalDays;
  final int consolidationObservations;
  final bool relapseDetected;
  final bool studentAbandoned;

  /// 批次1（O2）：距最后一次观察（诊断/训练）的天数——毕业复核用。
  /// 学员改好后不再出现在诊断 → 无新观察数据 → 该值持续增大。
  final int daysSinceLastObservation;

  /// 批次1（O2）：历史训练达标率（pass/total）——毕业复核用。
  final double passRate;

  const StateTransitionInput({
    required this.trainingStarted,
    required this.consecutiveLowSeverity,
    required this.consecutivePasses,
    required this.fsrsIntervalDays,
    required this.consolidationObservations,
    required this.relapseDetected,
    required this.studentAbandoned,
    this.daysSinceLastObservation = 0,
    this.passRate = 0.0,
  });
}

/// 教学状态迁移结果
class StateTransitionResult {
  final TeachingState newState;
  final String reason;

  const StateTransitionResult({required this.newState, required this.reason});
}

/// 最小数据量检查输入
class MinDataCheckInput {
  final int diagnosisCount;
  final int trainingCount;
  final int consolidationObservations;

  const MinDataCheckInput({
    required this.diagnosisCount,
    required this.trainingCount,
    required this.consolidationObservations,
  });
}

/// 最小数据量检查结果
class MinDataResult {
  final bool canClaimImprovement;
  final bool canClaimStable;
  final bool canClaimWorsening;
  final bool canClaimMastered;
  final List<String> fallbackPhrases;

  const MinDataResult({
    required this.canClaimImprovement,
    required this.canClaimStable,
    required this.canClaimWorsening,
    required this.canClaimMastered,
    required this.fallbackPhrases,
  });
}

/// 评估结果摘要
// ─── 教学状态迁移 ────────────────────────────────────────────

/// 批次1（O2）：毕业复核阈值——距最后一次观察（诊断/训练）达该天数，
/// 且历史训练达标率 ≥ 该值 → consolidating 直接毕业为 mastered。
/// 对齐 FSRS 间隔 ≥14 天的概念；达标率与 M4-C 阶段迁移阈值一致（0.7）。
const int kGraduationReviewGapDays = 14;
const double kGraduationReviewPassRate = 0.7;

/// 教学状态迁移 FSM
StateTransitionResult transitionTeachingState(
  TeachingState currentState,
  StateTransitionInput input,
) {
  final s = currentState;

  // identified → in_progress
  if (s == TeachingState.identified && input.trainingStarted) {
    return const StateTransitionResult(
      newState: TeachingState.inProgress,
      reason: '第一次训练开始',
    );
  }

  // in_progress → consolidating
  if (s == TeachingState.inProgress) {
    if (input.consecutiveLowSeverity >= 3 || input.consecutivePasses >= 5) {
      return const StateTransitionResult(
        newState: TeachingState.consolidating,
        reason: '连续稳定表现，进入巩固期',
      );
    }
  }

  // consolidating → mastered
  if (s == TeachingState.consolidating) {
    // FSRS 路径（未来启用）：间隔达标 + 巩固观察充足
    final fsrsReady =
        input.fsrsIntervalDays >= 14 && input.consolidationObservations >= 3;
    // 非 FSRS 降级路径：FSRS 未启用时代理规则
    // 要求巩固观察 ≥5 + 连续低严重度 ≥3 + 连续通过 ≥3
    final proxyReady =
        input.consolidationObservations >= 5 &&
        input.consecutiveLowSeverity >= 3 &&
        input.consecutivePasses >= 3;
    // 批次1（O2）：毕业复核——长时间无新观察 + 历史达标率达标 → 直接确认掌握。
    // 修复：学员改好后不再出现在诊断 → 无观察数据 → 原规则永久卡 active 阻塞 M4-A。
    // 保守守卫：已检测到复发（relapseDetected）时不毕业，交给下方回退规则处理。
    final graduationReady =
        !input.relapseDetected &&
        input.daysSinceLastObservation >= kGraduationReviewGapDays &&
        input.passRate >= kGraduationReviewPassRate;
    if (fsrsReady || proxyReady || graduationReady) {
      return StateTransitionResult(
        newState: TeachingState.mastered,
        reason: graduationReady ? '长时间无复发且历史达标，毕业复核确认掌握' : '巩固期表现稳定，确认掌握',
      );
    }
  }

  // 回退规则
  // mastered → in_progress (复发)
  if (s == TeachingState.mastered && input.relapseDetected) {
    return const StateTransitionResult(
      newState: TeachingState.inProgress,
      reason: '复发L2/L3，回退到训练',
    );
  }

  // consolidating → in_progress (FSRS到期诊断= L3)
  if (s == TeachingState.consolidating &&
      input.relapseDetected &&
      input.consecutiveLowSeverity == 0) {
    return const StateTransitionResult(
      newState: TeachingState.inProgress,
      reason: '巩固期诊断恶化为L3，回退',
    );
  }

  // in_progress → identified (学员放弃)
  if (s == TeachingState.inProgress && input.studentAbandoned) {
    return const StateTransitionResult(
      newState: TeachingState.identified,
      reason: '学员主动放弃训练该症候',
    );
  }

  return StateTransitionResult(newState: currentState, reason: '维持当前状态');
}

// ─── 最小数据量检查 ─────────────────────────────────────────

/// 最小数据量检查
MinDataResult checkMinimumData(MinDataCheckInput input) {
  final canClaimImprovement = input.diagnosisCount >= 2;
  final canClaimStable = input.trainingCount >= 3;
  final canClaimWorsening = input.diagnosisCount >= 2;
  final canClaimMastered = input.consolidationObservations >= 3;

  final fallbackPhrases = <String>[];
  if (!canClaimImprovement) {
    fallbackPhrases.add('不能说"你改善了"，可以说"你在练习中做对了方向"');
  }
  if (!canClaimStable) {
    fallbackPhrases.add('不能说"你稳定了"，可以说"继续训练"');
  }
  if (!canClaimWorsening) {
    fallbackPhrases.add('不能说"你恶化了"，一次诊断不算趋势');
  }
  if (!canClaimMastered) {
    fallbackPhrases.add('不能说"你掌握了"，需要至少3轮巩固观察');
  }

  return MinDataResult(
    canClaimImprovement: canClaimImprovement,
    canClaimStable: canClaimStable,
    canClaimWorsening: canClaimWorsening,
    canClaimMastered: canClaimMastered,
    fallbackPhrases: fallbackPhrases,
  );
}

class EvaluationSummary {
  final String syndromeId;
  final Severity currentSeverity;
  final Severity? previousSeverity;
  final TrendJudgment trend;
  final ComprehensiveJudgment comprehensiveJudgment;
  final TeachingState teachingState;
  final int trainingCount;
  final double passRate;
  final DeteriorationSignal? deteriorationSignal;
  final MinDataResult minData;
  final String contextInjection;

  const EvaluationSummary({
    required this.syndromeId,
    required this.currentSeverity,
    this.previousSeverity,
    required this.trend,
    required this.comprehensiveJudgment,
    required this.teachingState,
    required this.trainingCount,
    required this.passRate,
    this.deteriorationSignal,
    required this.minData,
    required this.contextInjection,
  });
}

// ─── 维度A: 严重度趋势 ──────────────────────────────────────

// ─── 组合：生成评估结果摘要 ──────────────────────────────────

/// 评估摘要输入（构建完整评估的聚合输入）
class EvaluationSummaryInput {
  final SeverityTrendInput severityInput;
  final PassRateInput passRateInput;
  final FsrsStabilityInput? fsrsStability;
  final DeteriorationCheckInput deteriorationInput;
  final TeachingState teachingState;
  final StateTransitionInput stateTransitionInput;
  final MinDataCheckInput minDataInput;

  const EvaluationSummaryInput({
    required this.severityInput,
    required this.passRateInput,
    this.fsrsStability,
    required this.deteriorationInput,
    required this.teachingState,
    required this.stateTransitionInput,
    required this.minDataInput,
  });
}

/// 生成评估结果摘要（供 chat-service 注入 system prompt）
EvaluationSummary buildEvaluationSummary(
  String syndromeId,
  EvaluationSummaryInput inputs,
) {
  final severityTrend = classifySeverityTrend(inputs.severityInput);
  final comprehensiveResult = comprehensiveJudgment(
    ComprehensiveJudgmentInput(
      severityTrend: severityTrend,
      passRate: inputs.passRateInput,
      fsrsStability: inputs.fsrsStability,
    ),
  );
  final deterioration = detectDeterioration(inputs.deteriorationInput);
  final stateTransition = transitionTeachingState(
    inputs.teachingState,
    inputs.stateTransitionInput,
  );
  final minData = checkMinimumData(inputs.minDataInput);

  final passRate = inputs.passRateInput.totalCount > 0
      ? inputs.passRateInput.passCount / inputs.passRateInput.totalCount
      : 0.0;

  // 构建上下文注入文本
  final lines = <String>[
    '[训练评估（代码计算）]',
    '症候: $syndromeId',
    '严重度变化: ${inputs.severityInput.previousSeverity.value}→${inputs.severityInput.currentSeverity.value}',
    '趋势: ${severityTrend.value}',
    '综合判断: ${comprehensiveResult.value}',
    '达标率: ${inputs.passRateInput.passCount}/${inputs.passRateInput.totalCount} (${(passRate * 100).round()}%)',
    '教学状态: ${inputs.teachingState.value}→${stateTransition.newState.value}',
    '恶化信号: ${deterioration.signal?.value ?? '无'}',
  ];
  if (deterioration.signal != null) {
    lines.add('干预建议: ${deterioration.intervention}');
  }
  if (minData.fallbackPhrases.isNotEmpty) {
    lines.add('表述约束:');
    for (final p in minData.fallbackPhrases) {
      lines.add('  - $p');
    }
  }
  lines.add('[/训练评估]');

  return EvaluationSummary(
    syndromeId: syndromeId,
    currentSeverity: inputs.severityInput.currentSeverity,
    previousSeverity: inputs.severityInput.previousSeverity,
    trend: severityTrend,
    comprehensiveJudgment: comprehensiveResult,
    teachingState: stateTransition.newState,
    trainingCount: inputs.passRateInput.totalCount,
    passRate: passRate,
    deteriorationSignal: deterioration.signal,
    minData: minData,
    contextInjection: lines.join('\n'),
  );
}
