// ─────────────────────────────────────────────────────────────
// training_evaluator 单元测试 — 批次1（O2）consolidating 毕业复核
//
// 覆盖路径（transitionTeachingState 纯函数）：
//   1. consolidating + 距最后一次观察 ≥14 天 + 历史达标率 ≥0.7 → mastered
//   2. consolidating + 距最后一次观察 <14 天 → 维持 consolidating
//   3. consolidating + 历史达标率 <0.7 → 维持 consolidating
//   4. 非 consolidating 状态不受毕业复核输入影响（in_progress 维持）
//   5. 毕业复核与既有代理路径（proxyReady）并存不冲突
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/training_evaluator.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 构造 FSM 输入（其余字段按不触发其他规则的安全值填充）
StateTransitionInput _input({
  TeachingState state = TeachingState.consolidating,
  int daysSinceLastObservation = 0,
  double passRate = 0.0,
  int consolidationObservations = 0,
  int consecutiveLowSeverity = 0,
  int consecutivePasses = 0,
  bool trainingStarted = false,
  bool relapseDetected = false,
}) {
  return StateTransitionInput(
    trainingStarted: trainingStarted,
    consecutiveLowSeverity: consecutiveLowSeverity,
    consecutivePasses: consecutivePasses,
    fsrsIntervalDays: 0,
    consolidationObservations: consolidationObservations,
    relapseDetected: relapseDetected,
    studentAbandoned: false,
    daysSinceLastObservation: daysSinceLastObservation,
    passRate: passRate,
  );
}

/// 批次 G：构造 buildEvaluationSummary 最小合法输入。
/// 默认值不触发恶化信号、数据充足（无表述约束）、教学状态维持 inProgress；
/// 各参数可覆盖以触达组装层的条件分支。
EvaluationSummaryInput _summaryInput({
  int passCount = 8,
  int totalCount = 10,
  Severity currentSeverity = Severity.l2,
  Severity previousSeverity = Severity.l2,
  bool wasResolvedToL1 = false,
  int minDiagnosisCount = 2,
  int minTrainingCount = 3,
  int minConsolidationObservations = 3,
}) {
  return EvaluationSummaryInput(
    severityInput: SeverityTrendInput(
      currentSeverity: currentSeverity,
      previousSeverity: previousSeverity,
      occurrenceCount: 1,
    ),
    passRateInput: PassRateInput(passCount: passCount, totalCount: totalCount),
    fsrsStability: const FsrsStabilityInput(
      currentStability: 2.0,
      previousStability: 1.0,
    ),
    deteriorationInput: DeteriorationCheckInput(
      syndromeId: 'test-syndrome',
      currentSeverity: currentSeverity,
      previousSeverity: previousSeverity,
      wasResolvedToL1: wasResolvedToL1,
      consecutiveFailures: 0,
      reboundPattern: false,
      gapDays: 0,
      newConcurrentSyndromes: 0,
    ),
    teachingState: TeachingState.inProgress,
    stateTransitionInput: const StateTransitionInput(
      trainingStarted: false,
      consecutiveLowSeverity: 0,
      consecutivePasses: 0,
      fsrsIntervalDays: 0,
      consolidationObservations: 0,
      relapseDetected: false,
      studentAbandoned: false,
    ),
    minDataInput: MinDataCheckInput(
      diagnosisCount: minDiagnosisCount,
      trainingCount: minTrainingCount,
      consolidationObservations: minConsolidationObservations,
    ),
  );
}

/// 批次 H：构造恶化检测输入（默认值不触发任何信号——五路全安全）。
DeteriorationCheckInput _detInput({
  Severity currentSeverity = Severity.l2,
  Severity previousSeverity = Severity.l2,
  bool wasResolvedToL1 = false,
  int consecutiveFailures = 0,
  bool reboundPattern = false,
  int gapDays = 0,
  int newConcurrentSyndromes = 0,
}) {
  return DeteriorationCheckInput(
    syndromeId: 'test-syndrome',
    currentSeverity: currentSeverity,
    previousSeverity: previousSeverity,
    wasResolvedToL1: wasResolvedToL1,
    consecutiveFailures: consecutiveFailures,
    reboundPattern: reboundPattern,
    gapDays: gapDays,
    newConcurrentSyndromes: newConcurrentSyndromes,
  );
}

void main() {
  group('批次1（O2）consolidating 毕业复核', () {
    test('#1 consolidating + 距末次观察≥14天 + 达标率≥0.7 → mastered', () {
      final result = transitionTeachingState(
        TeachingState.consolidating,
        _input(daysSinceLastObservation: 14, passRate: 0.8),
      );
      expect(result.newState, TeachingState.mastered);
    });

    test('#2 consolidating + 距末次观察 <14天 → 维持 consolidating（不提前毕业）', () {
      final result = transitionTeachingState(
        TeachingState.consolidating,
        _input(daysSinceLastObservation: 13, passRate: 0.9),
      );
      expect(result.newState, TeachingState.consolidating);
    });

    test('#3 consolidating + 历史达标率 <0.7 → 维持 consolidating（不虚报掌握）', () {
      final result = transitionTeachingState(
        TeachingState.consolidating,
        _input(daysSinceLastObservation: 20, passRate: 0.5),
      );
      expect(result.newState, TeachingState.consolidating);
    });

    test('#4 非 consolidating 状态不受毕业复核输入影响（in_progress 维持）', () {
      final result = transitionTeachingState(
        TeachingState.inProgress,
        _input(
          state: TeachingState.inProgress,
          daysSinceLastObservation: 30,
          passRate: 0.9,
        ),
      );
      expect(result.newState, TeachingState.inProgress);
    });

    test('#5 毕业复核与既有代理路径并存：无间隔但巩固观察达标 → 仍走代理路径毕业', () {
      final result = transitionTeachingState(
        TeachingState.consolidating,
        _input(
          daysSinceLastObservation: 0, // 毕业复核不触发
          consolidationObservations: 5,
          consecutiveLowSeverity: 3,
          consecutivePasses: 3,
        ),
      );
      expect(result.newState, TeachingState.mastered);
    });

    test('#6 复发优先：consolidating 恶化回退不受毕业复核掩盖', () {
      final result = transitionTeachingState(
        TeachingState.consolidating,
        _input(
          daysSinceLastObservation: 20,
          passRate: 0.9,
          relapseDetected: true,
        ),
      );
      expect(result.newState, TeachingState.inProgress);
    });
  });

  // ── 批次6（6.12 A5）：综合判断 first-match 顺序 ──

  group('综合判断 comprehensiveJudgment（批次6 A5）', () {
    ComprehensiveJudgment judge({
      required TrendJudgment severityTrend,
      required int passCount,
      required int totalCount,
      FsrsStabilityInput? stability,
    }) {
      return comprehensiveJudgment(
        ComprehensiveJudgmentInput(
          severityTrend: severityTrend,
          passRate: PassRateInput(passCount: passCount, totalCount: totalCount),
          fsrsStability: stability,
        ),
      );
    }

    test('#A1 严重度恶化 + 高达标率 → 无条件恶化（置顶短路，不输出改善）', () {
      final r = judge(
        severityTrend: TrendJudgment.worsening,
        passCount: 9,
        totalCount: 10,
        stability: const FsrsStabilityInput(
          currentStability: 2.0,
          previousStability: 1.0,
        ),
      );
      expect(
        r,
        ComprehensiveJudgment.worsening,
        reason: '恶化无条件恶化置顶，即使达标率/稳定度向好也不改判',
      );
    });

    test('#A2 严重度不变 + 很低达标率（pr<0.2）+ 稳定度下降 → 恶化趋势（规则7 可达）', () {
      final r = judge(
        severityTrend: TrendJudgment.stable,
        passCount: 1,
        totalCount: 10, // 0.1 < 0.2
        stability: const FsrsStabilityInput(
          currentStability: 1.0,
          previousStability: 2.0,
        ),
      );
      expect(
        r,
        ComprehensiveJudgment.worseningTrend,
        reason: '规则7（pr<0.2）必须先于规则8（pr<=0.4）命中，否则被遮蔽成死代码',
      );
    });

    test('#A3 严重度不变 + 低达标率（0.2<=pr<=0.4）+ 稳定度下降 → 可能恶化（规则8）', () {
      final r = judge(
        severityTrend: TrendJudgment.stable,
        passCount: 3,
        totalCount: 10, // 0.3
        stability: const FsrsStabilityInput(
          currentStability: 1.0,
          previousStability: 2.0,
        ),
      );
      expect(r, ComprehensiveJudgment.possibleWorsening);
    });

    test('#A4 严重度不变 + 中等达标率 → 稳定', () {
      final r = judge(
        severityTrend: TrendJudgment.stable,
        passCount: 5,
        totalCount: 10, // 0.5
        stability: const FsrsStabilityInput(
          currentStability: 1.0,
          previousStability: 1.0,
        ),
      );
      expect(r, ComprehensiveJudgment.stable);
    });

    test('#A5 严重度不变 + 达标率好 + 稳定度上升 → 改善', () {
      final r = judge(
        severityTrend: TrendJudgment.stable,
        passCount: 8,
        totalCount: 10, // 0.8
        stability: const FsrsStabilityInput(
          currentStability: 2.0,
          previousStability: 1.0,
        ),
      );
      expect(r, ComprehensiveJudgment.improving);
    });

    test('#A6 严重度下降 + 达标率好 + 稳定度上升 → 明显改善', () {
      final r = judge(
        severityTrend: TrendJudgment.improving,
        passCount: 8,
        totalCount: 10,
        stability: const FsrsStabilityInput(
          currentStability: 2.0,
          previousStability: 1.0,
        ),
      );
      expect(r, ComprehensiveJudgment.significantImprovement);
    });

    test('#A7 数据不足（无诊断无训练）→ insufficientData', () {
      final r = judge(
        severityTrend: TrendJudgment.insufficientData,
        passCount: 0,
        totalCount: 0,
      );
      expect(r, ComprehensiveJudgment.insufficientData);
    });

    test('#A8 恶化信号一致性：稳定度下降 + 低达标率但严重度不变 → 不出改善类结论', () {
      // 与 detectDeterioration 的 newConcurrent 场景同族：稳定度/达标率不佳时
      // 综合判断绝不输出 improving/significantImprovement（防与恶化信号矛盾）
      final r = judge(
        severityTrend: TrendJudgment.stable,
        passCount: 0,
        totalCount: 10, // 0.0
        stability: const FsrsStabilityInput(
          currentStability: 0.5,
          previousStability: 1.0,
        ),
      );
      expect(r, isNot(ComprehensiveJudgment.improving));
      expect(r, isNot(ComprehensiveJudgment.significantImprovement));
    });
  });

  // ── 批次 G：buildEvaluationSummary（组装层 + 除零保护）──
  // 此前 test/ 零直接引用（V4.20 真空函数），输出 contextInjection 直接入 prompt。
  // 子函数（comprehensiveJudgment / detectDeterioration / FSM / minData）已有各自
  // 测试，此处只锚组装契约与条件分支，不重复覆盖子函数内部规则。

  group('批次 G buildEvaluationSummary（组装 + 除零保护）', () {
    test('#S1 正常路径 → 头尾标记/症候/达标率/状态行齐全 + 子结果带出', () {
      final summary = buildEvaluationSummary('test-syndrome', _summaryInput());

      final injection = summary.contextInjection;
      expect(injection.startsWith('[训练评估（代码计算）]'), isTrue);
      expect(injection.endsWith('[/训练评估]'), isTrue);
      expect(injection.contains('症候: test-syndrome'), isTrue);
      expect(injection.contains('严重度变化: L2→L2'), isTrue);
      expect(injection.contains('趋势: stable'), isTrue);
      expect(injection.contains('综合判断: improving'), isTrue);
      expect(injection.contains('达标率: 8/10 (80%)'), isTrue);
      expect(injection.contains('教学状态: in_progress→in_progress'), isTrue);
      expect(injection.contains('恶化信号: 无'), isTrue);
      // 无恶化 / 数据充足 → 两个条件块不出现
      expect(injection.contains('干预建议:'), isFalse);
      expect(injection.contains('表述约束:'), isFalse);

      // 子计算结果带出（组合语义由 #A4/#A5 锚定，此处锚"组装层带出"契约）
      expect(summary.trend, TrendJudgment.stable);
      expect(summary.comprehensiveJudgment, ComprehensiveJudgment.improving);
      expect(summary.teachingState, TeachingState.inProgress);
      expect(summary.trainingCount, 10);
      expect(summary.passRate, 0.8);
      expect(summary.deteriorationSignal, isNull);
      expect(summary.minData.fallbackPhrases, isEmpty);
    });

    test('#S2 totalCount=0 → 除零保护：0% 且无 NaN 进 prompt', () {
      final summary = buildEvaluationSummary(
        'test-syndrome',
        _summaryInput(passCount: 0, totalCount: 0),
      );

      expect(summary.passRate, 0.0);
      expect(summary.contextInjection.contains('达标率: 0/0 (0%)'), isTrue);
      // 若拆掉 totalCount>0 保护：0/0=NaN → round() 抛 UnsupportedError
      expect(summary.contextInjection.contains('NaN'), isFalse);
    });

    test('#S3 恶化信号（relapse）→ 干预建议行出现 + 信号带出', () {
      // wasResolvedToL1 + 再现 L2 → relapse（对照 #S1 的"无干预建议行"）
      final summary = buildEvaluationSummary(
        'test-syndrome',
        _summaryInput(wasResolvedToL1: true),
      );

      expect(summary.deteriorationSignal, DeteriorationSignal.relapse);
      expect(summary.contextInjection.contains('恶化信号: relapse'), isTrue);
      expect(
        summary.contextInjection.contains('干预建议: 回到 Lv.1 训练，换一种教学方式'),
        isTrue,
      );
    });

    test('#S4 数据不足 → 表述约束块注入 fallback 短语', () {
      final summary = buildEvaluationSummary(
        'test-syndrome',
        _summaryInput(
          minDiagnosisCount: 1,
          minTrainingCount: 0,
          minConsolidationObservations: 0,
        ),
      );

      final injection = summary.contextInjection;
      expect(injection.contains('表述约束:'), isTrue);
      expect(injection.contains('不能说"你改善了"'), isTrue);
      expect(injection.contains('不能说"你掌握了"'), isTrue);
      expect(summary.minData.fallbackPhrases, isNotEmpty);
    });
  });

  // ── 批次 H：detectDeterioration（此前 test/ 零直接调用——V4.20 真空）──
  // 批次 G 的 #S3 仅经 buildEvaluationSummary 间接锚了 relapse 一条；
  // 本组按五路信号 + 无信号兜底 + 门槛边界逐分支直锚。

  group('批次 H detectDeterioration（五路信号 + 门槛边界）', () {
    test('#D1 五路全安全 → 无信号兜底', () {
      final r = detectDeterioration(_detInput());
      expect(r.signal, isNull);
      expect(r.intervention, '');
    });

    test('#D2 复发：L1 缓解后再现 L2 → relapse', () {
      final r = detectDeterioration(
        _detInput(wasResolvedToL1: true, currentSeverity: Severity.l2),
      );
      expect(r.signal, DeteriorationSignal.relapse);
      expect(r.intervention, '回到 Lv.1 训练，换一种教学方式');
    });

    test('#D3 恶化：严重度上升 + 连续失败 2 次 → worsening', () {
      final r = detectDeterioration(
        _detInput(
          currentSeverity: Severity.l2,
          previousSeverity: Severity.l1,
          consecutiveFailures: 2,
        ),
      );
      expect(r.signal, DeteriorationSignal.worsening);
      expect(r.intervention, '停止训练该症候。改为自然语言讨论，寻找根本原因');
    });

    test('#D4 边界：严重度上升但连续失败恰好 1 次 → 不触发 worsening', () {
      // 门槛是 >= 2：仅 1 次失败 + 其余安全 → 落无信号兜底
      final r = detectDeterioration(
        _detInput(
          currentSeverity: Severity.l2,
          previousSeverity: Severity.l1,
          consecutiveFailures: 1,
        ),
      );
      expect(r.signal, isNull);
    });

    test('#D5 新并发：新症候恰 3 个 → newConcurrent', () {
      final r = detectDeterioration(_detInput(newConcurrentSyndromes: 3));
      expect(r.signal, DeteriorationSignal.newConcurrent);
      expect(r.intervention, '回到诊断确认阶段，让学员挑一个最关心的先练');
    });

    test('#D6 反弹 → rebound', () {
      final r = detectDeterioration(_detInput(reboundPattern: true));
      expect(r.signal, DeteriorationSignal.rebound);
      expect(r.intervention, '检查是否跳过了难度。如果是→降回之前的难度。如果不是→检查学员状态');
    });

    test('#D7 巩固失败：间隔 8 天 + L2 → consolidationFail', () {
      final r = detectDeterioration(
        _detInput(gapDays: 8, currentSeverity: Severity.l2),
      );
      expect(r.signal, DeteriorationSignal.consolidationFail);
      expect(r.intervention, 'FSRS 稳定度不足。增加该症候的训练频率');
    });

    test('#D8 优先级：复发条件与恶化条件同时满足 → relapse 先于 worsening', () {
      final r = detectDeterioration(
        _detInput(
          wasResolvedToL1: true,
          currentSeverity: Severity.l3,
          previousSeverity: Severity.l1,
          consecutiveFailures: 5,
        ),
      );
      expect(r.signal, DeteriorationSignal.relapse);
    });
  });
}
