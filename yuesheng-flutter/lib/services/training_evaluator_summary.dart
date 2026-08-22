// ─────────────────────────────────────────────────────────────
// training_evaluator 主题分组拆分：training_evaluator_summary.dart（R-019 ≤300 行）
// 评估摘要聚合：EvaluationSummary/EvaluationSummaryInput/buildEvaluationSummary。逐字迁移自 training_evaluator.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'training_evaluator.dart';

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
