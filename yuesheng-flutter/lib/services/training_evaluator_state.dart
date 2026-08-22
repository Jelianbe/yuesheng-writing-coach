// ─────────────────────────────────────────────────────────────
// training_evaluator 主题分组拆分：training_evaluator_state.dart（R-019 ≤300 行）
// 教学状态迁移 + 最小数据量检查（transitionTeachingState/checkMinimumData 及相关类型/常量）。逐字迁移自 training_evaluator.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'training_evaluator.dart';

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
