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
}
