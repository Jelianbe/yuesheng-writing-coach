// ─────────────────────────────────────────────────────────────
// training_evaluator 判别性测试 —— 针对全量变异审计的 45 处未检出
//
// 背景（详 .ai/CHECKS.md §9.11）：182 变异点 / **45 未检出（24.73%）** / rating C，
// 且报告显示 **`Not covered by tests: 0`** ⇒ 不是「没跑到」，是「跑了但杀不死」。
//
// 逐条定性后根因高度一致（这才是重点）：
//   ① 现有用例只测「**恰好等于**阈值」（如 consecutivePasses=5），
//      从不测「**超过**阈值」（=6）⇒ 23 处 `>=`→`==` 全部杀不死；
//   ② `&&` 只测「两侧同真」，从不测「一真一假」⇒ `&&`→`||` 杀不死；
//   ③ 阈值只测正例、不测「低于阈值」⇒ 数字取负（`0.6`→`-0.6`）杀不死；
//   ④ 输出字段（`fallbackPhrases` 条目、`reason` 文案）无断言 ⇒ 删调用 / 改文案杀不死。
//
// ⇒ 本文件为**每处未检出**构造判别性输入（能区分原实现与变异体的输入）。
//   用例注释标注它针对的源码行与变异类型；`D-` 前缀 = discrimination。
//
// **已判为真等价、故不补用例**（论证见 §9.11）：
//   L199 `<=`→`<` —— pr 恰为 0.4 时上游 L187（`>=0.4 && <0.6`）必然先返回 stable，
//   L199 在该点不可达 ⇒ 单变异下结构性不可区分。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/training_evaluator.dart';
import 'package:writingcoach/types/teaching_types.dart';

// ─── 辅助构造 ────────────────────────────────────────────────

SeverityTrendInput _sev(Severity cur, Severity prev, {int occ = 1}) =>
    SeverityTrendInput(
      currentSeverity: cur,
      previousSeverity: prev,
      occurrenceCount: occ,
    );

/// FSRS 三态：上升 / 下降 / 数据不足（previousStability 为 null）
const FsrsStabilityInput kUp = FsrsStabilityInput(
  currentStability: 2.0,
  previousStability: 1.0,
);
const FsrsStabilityInput kDown = FsrsStabilityInput(
  currentStability: 1.0,
  previousStability: 2.0,
);
const FsrsStabilityInput kNoData = FsrsStabilityInput(currentStability: 1.0);

/// 达标率一律用 `n/10` 表达 —— 与源码 `passCount / totalCount` 同口径，
/// 且 `n/10` 与字面量 `0.n` 在 IEEE754 下位级相等（阈值边界才可精确命中）。
ComprehensiveJudgment _cj(
  TrendJudgment trend,
  int passCount,
  int totalCount,
  FsrsStabilityInput? stab,
) => comprehensiveJudgment(
  ComprehensiveJudgmentInput(
    severityTrend: trend,
    passRate: PassRateInput(passCount: passCount, totalCount: totalCount),
    fsrsStability: stab,
  ),
);

DeteriorationCheckInput _det({
  Severity cur = Severity.l2,
  Severity prev = Severity.l2,
  bool wasResolvedToL1 = false,
  int consecutiveFailures = 0,
  bool reboundPattern = false,
  int gapDays = 0,
  int newConcurrentSyndromes = 0,
}) => DeteriorationCheckInput(
  syndromeId: 'd-syndrome',
  currentSeverity: cur,
  previousSeverity: prev,
  wasResolvedToL1: wasResolvedToL1,
  consecutiveFailures: consecutiveFailures,
  reboundPattern: reboundPattern,
  gapDays: gapDays,
  newConcurrentSyndromes: newConcurrentSyndromes,
);

/// 默认值不触发任何附加路径（不开始、不复发、不放弃、无间隔、无观察）
StateTransitionInput _st({
  int consecutiveLowSeverity = 0,
  int consecutivePasses = 0,
  int fsrsIntervalDays = 0,
  int consolidationObservations = 0,
  bool relapseDetected = false,
  int daysSinceLastObservation = 0,
  double passRate = 0.0,
}) => StateTransitionInput(
  trainingStarted: false,
  consecutiveLowSeverity: consecutiveLowSeverity,
  consecutivePasses: consecutivePasses,
  fsrsIntervalDays: fsrsIntervalDays,
  consolidationObservations: consolidationObservations,
  relapseDetected: relapseDetected,
  studentAbandoned: false,
  daysSinceLastObservation: daysSinceLastObservation,
  passRate: passRate,
);

EvaluationSummaryInput _summaryInput({
  int passCount = 8,
  int totalCount = 10,
  Severity cur = Severity.l2,
  Severity prev = Severity.l2,
  int minDiagnosisCount = 2,
  int minTrainingCount = 3,
  int minConsolidationObservations = 3,
}) => EvaluationSummaryInput(
  severityInput: SeverityTrendInput(
    currentSeverity: cur,
    previousSeverity: prev,
    occurrenceCount: 1,
  ),
  passRateInput: PassRateInput(passCount: passCount, totalCount: totalCount),
  fsrsStability: kUp,
  deteriorationInput: _det(cur: cur, prev: prev),
  teachingState: TeachingState.inProgress,
  stateTransitionInput: _st(),
  minDataInput: MinDataCheckInput(
    diagnosisCount: minDiagnosisCount,
    trainingCount: minTrainingCount,
    consolidationObservations: minConsolidationObservations,
  ),
);

void main() {
  // ── 组1：classifySeverityTrend（L81 ×3 · 反复出现判定）────────
  group('D-组1 classifySeverityTrend（L81）', () {
    test('D-C1 同严重度 + occ=2 → worsening（杀 op.eq / and_chain2 / if.start）', () {
      expect(
        classifySeverityTrend(_sev(Severity.l2, Severity.l2, occ: 2)),
        TrendJudgment.worsening,
      );
    });

    test('D-C2 同严重度 + occ=1 → stable（对照：未反复）', () {
      expect(
        classifySeverityTrend(_sev(Severity.l2, Severity.l2, occ: 1)),
        TrendJudgment.stable,
      );
    });

    test('D-C3 同严重度 + occ=0 → stable（下边界）', () {
      expect(
        classifySeverityTrend(_sev(Severity.l3, Severity.l3, occ: 0)),
        TrendJudgment.stable,
      );
    });

    test('D-C4 l1→l1 + occ=2 → worsening（最小枚举值 + 反复）', () {
      expect(
        classifySeverityTrend(_sev(Severity.l1, Severity.l1, occ: 2)),
        TrendJudgment.worsening,
      );
    });

    test('D-C5 l3→l3 + occ=5 → worsening（最大枚举值 + 反复）', () {
      expect(
        classifySeverityTrend(_sev(Severity.l3, Severity.l3, occ: 5)),
        TrendJudgment.worsening,
      );
    });
  });

  // ── 组2：comprehensiveJudgment 数据不足短路（L126 ×1）────────
  group('D-组2 数据不足短路（L126）', () {
    test(
      'D-J1 insufficientData + totalCount>0 → 不短路，落到 [0.4,0.6) ⇒ stable',
      () {
        // 杀 && → ||：变异后任一为真即 insufficientData
        expect(
          _cj(TrendJudgment.insufficientData, 1, 2, null),
          ComprehensiveJudgment.stable,
        );
      },
    );

    test('D-J2 stable + totalCount=0 → 不短路（另一侧，同样杀 && → ||）', () {
      expect(
        _cj(TrendJudgment.stable, 0, 0, null),
        ComprehensiveJudgment.stable,
      );
    });

    test('D-J3 insufficientData + totalCount=0 → insufficientData（正例对照）', () {
      expect(
        _cj(TrendJudgment.insufficientData, 0, 0, null),
        ComprehensiveJudgment.insufficientData,
      );
    });
  });

  // ── 组3：严重度下降分支 _judgeImprovingTrend（L165/L170）─────
  group('D-组3 _judgeImprovingTrend（L165 / L170）', () {
    test('D-I1 improving + 0.7 + 非上升 ⇒ improving（杀 L165 || / L170 ==）', () {
      expect(
        _cj(TrendJudgment.improving, 7, 10, kDown),
        ComprehensiveJudgment.improving,
      );
    });

    test('D-I2 improving + 0.6 恰好 + 非上升 ⇒ improving（杀 L170 >）', () {
      expect(
        _cj(TrendJudgment.improving, 6, 10, kNoData),
        ComprehensiveJudgment.improving,
      );
    });

    test('D-I3 improving + 0.3 + 非上升 ⇒ stable（杀 L170 数字取负）', () {
      expect(
        _cj(TrendJudgment.improving, 3, 10, kDown),
        ComprehensiveJudgment.stable,
      );
    });

    test('D-I4 improving + 0.3 + 上升 ⇒ stable（杀 L165 数字取负）', () {
      expect(
        _cj(TrendJudgment.improving, 3, 10, kUp),
        ComprehensiveJudgment.stable,
      );
    });

    test('D-I5 improving + 0.6 恰好 + 上升 ⇒ significantImprovement（正例对照）', () {
      expect(
        _cj(TrendJudgment.improving, 6, 10, kUp),
        ComprehensiveJudgment.significantImprovement,
      );
    });
  });

  // ── 组4：严重度不变分支 _judgeStableTrend（L182/L187/L199）───
  group('D-组4 _judgeStableTrend（L182 / L187 / L199）', () {
    test('D-S1 stable + 0.5 + 下降 ⇒ stable（杀 L199 && → ||）', () {
      // 变异后 `0.5<=0.4 || worsening` 为真 ⇒ 误判 possibleWorsening
      expect(
        _cj(TrendJudgment.stable, 5, 10, kDown),
        ComprehensiveJudgment.stable,
      );
    });

    test(
      'D-S2 stable + 0.4 恰好 + 下降 ⇒ stable（杀 L187 > / and_chain2 / if.end / 取负）',
      () {
        expect(
          _cj(TrendJudgment.stable, 4, 10, kDown),
          ComprehensiveJudgment.stable,
        );
      },
    );

    test('D-S3 stable + 0.6 恰好 + 上升 ⇒ improving（杀 L182 >）', () {
      expect(
        _cj(TrendJudgment.stable, 6, 10, kUp),
        ComprehensiveJudgment.improving,
      );
    });

    test('D-S4 stable + 0.5 + 上升 ⇒ stable（杀 L182 数字取负）', () {
      expect(
        _cj(TrendJudgment.stable, 5, 10, kUp),
        ComprehensiveJudgment.stable,
      );
    });

    test('D-S5 stable + 0.7 + 数据不足 ⇒ stable（杀 L182 && → ||）', () {
      expect(
        _cj(TrendJudgment.stable, 7, 10, kNoData),
        ComprehensiveJudgment.stable,
      );
    });

    test('D-S6 stable + 0.7 + 上升 ⇒ improving（正例对照）', () {
      expect(
        _cj(TrendJudgment.stable, 7, 10, kUp),
        ComprehensiveJudgment.improving,
      );
    });

    test('D-S7 stable + 0.7 + 下降 ⇒ stable（>0.4 不落入可能恶化，反面对照）', () {
      expect(
        _cj(TrendJudgment.stable, 7, 10, kDown),
        ComprehensiveJudgment.stable,
      );
    });
  });

  // ── 组5：detectDeterioration 门槛（L250/L258/L274 ×3）───────
  group('D-组5 detectDeterioration 门槛超界（L250 / L258 / L274）', () {
    test('D-D1 严重度上升 + 连续失败 3 次 → worsening（杀 L250 ==）', () {
      final r = detectDeterioration(
        _det(cur: Severity.l3, prev: Severity.l2, consecutiveFailures: 3),
      );
      expect(r.signal, DeteriorationSignal.worsening);
    });

    test('D-D2 新并发症候 4 个 → newConcurrent（杀 L258 ==）', () {
      final r = detectDeterioration(_det(newConcurrentSyndromes: 4));
      expect(r.signal, DeteriorationSignal.newConcurrent);
    });

    test('D-D3 间隔 8 天 + L3 → consolidationFail（杀 L274 ==）', () {
      final r = detectDeterioration(
        _det(cur: Severity.l3, prev: Severity.l3, gapDays: 8),
      );
      expect(r.signal, DeteriorationSignal.consolidationFail);
    });
  });

  // ── 组6：in_progress 前进门槛（L386 ×2）────────────────────
  group('D-组6 in_progress 前进门槛超界（L386）', () {
    test('D-T1 连续低严重度 4 次（>3）→ consolidating（杀 L386 左 ==）', () {
      final r = transitionTeachingState(
        TeachingState.inProgress,
        _st(consecutiveLowSeverity: 4),
      );
      expect(r.newState, TeachingState.consolidating);
    });

    test('D-T2 连续通过 6 次（>5）→ consolidating（杀 L386 右 ==）', () {
      final r = transitionTeachingState(
        TeachingState.inProgress,
        _st(consecutivePasses: 6),
      );
      expect(r.newState, TeachingState.consolidating);
    });
  });

  // ── 组7：consolidating 三路径（L407–L418）───────────────────
  group(
    'D-组7 consolidating 三路径门槛超界（L407 / L410 / L411 / L412 / L417 / L418）',
    () {
      test('D-F1 interval=15（>14）+ obs=3 → mastered（杀 L407 interval ==）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(fsrsIntervalDays: 15, consolidationObservations: 3),
        );
        expect(r.newState, TeachingState.mastered);
      });

      test('D-F2 interval=14 恰好 + obs=3 恰好 → mastered（杀 L407 两个 >）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(fsrsIntervalDays: 14, consolidationObservations: 3),
        );
        expect(r.newState, TeachingState.mastered);
      });

      test('D-F3 interval=14 + obs=4（>3）→ mastered（杀 L407 obs ==）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(fsrsIntervalDays: 14, consolidationObservations: 4),
        );
        expect(r.newState, TeachingState.mastered);
      });

      test('D-F4 interval=0 + obs=3 → 维持 consolidating（杀 L407 || / 数字取负）', () {
        // 变异后 fsrsReady 变真 ⇒ 误判 mastered
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(fsrsIntervalDays: 0, consolidationObservations: 3),
        );
        expect(r.newState, TeachingState.consolidating);
      });

      test('D-F5 obs=6（>5）+ 代理路径其余达标 → mastered（杀 L410 ==）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(
            consolidationObservations: 6,
            consecutiveLowSeverity: 3,
            consecutivePasses: 3,
          ),
        );
        expect(r.newState, TeachingState.mastered);
      });

      test('D-F6 obs=1 + cls=3 + cp=3 → 维持 consolidating（杀 L410 && → ||）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(
            consolidationObservations: 1,
            consecutiveLowSeverity: 3,
            consecutivePasses: 3,
          ),
        );
        expect(r.newState, TeachingState.consolidating);
      });

      test('D-F7 obs=5 + cls=4（>3）+ cp=3 → mastered（杀 L411 ==）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(
            consolidationObservations: 5,
            consecutiveLowSeverity: 4,
            consecutivePasses: 3,
          ),
        );
        expect(r.newState, TeachingState.mastered);
      });

      test('D-F8 obs=5 + cls=0 + cp=3 → 维持 consolidating（杀 L411 && → ||）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(
            consolidationObservations: 5,
            consecutiveLowSeverity: 0,
            consecutivePasses: 3,
          ),
        );
        expect(r.newState, TeachingState.consolidating);
      });

      test('D-F9 obs=5 + cls=3 + cp=4（>3）→ mastered（杀 L412 ==）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(
            consolidationObservations: 5,
            consecutiveLowSeverity: 3,
            consecutivePasses: 4,
          ),
        );
        expect(r.newState, TeachingState.mastered);
      });

      test('D-F10 距末次观察 15 天（>14）+ 达标率 0.8 → mastered（杀 L417 ==）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(daysSinceLastObservation: 15, passRate: 0.8),
        );
        expect(r.newState, TeachingState.mastered);
      });

      test('D-F11 距末次观察 15 天 + 达标率 0.7 恰好 → mastered（杀 L418 >）', () {
        final r = transitionTeachingState(
          TeachingState.consolidating,
          _st(daysSinceLastObservation: 15, passRate: 0.7),
        );
        expect(r.newState, TeachingState.mastered);
      });
    },
  );

  // ── 组8：checkMinimumData（L447–L450 ×4 / L456 / L459）──────
  group('D-组8 checkMinimumData（L447–L450 / L456 / L459）', () {
    test('D-M1 三项均超界 → 四个 canClaim 全真（杀 L447–L450 的 ==）', () {
      final r = checkMinimumData(
        const MinDataCheckInput(
          diagnosisCount: 3,
          trainingCount: 4,
          consolidationObservations: 4,
        ),
      );
      expect(r.canClaimImprovement, isTrue);
      expect(r.canClaimStable, isTrue);
      expect(r.canClaimWorsening, isTrue);
      expect(r.canClaimMastered, isTrue);
      expect(r.fallbackPhrases, isEmpty);
    });

    test('D-M2 三项均不足 → 四条表述约束齐全（杀 L456 / L459 的删调用）', () {
      final r = checkMinimumData(
        const MinDataCheckInput(
          diagnosisCount: 1,
          trainingCount: 1,
          consolidationObservations: 1,
        ),
      );
      expect(r.fallbackPhrases, hasLength(4));
      expect(r.fallbackPhrases.any((p) => p.contains('你稳定了')), isTrue);
      expect(r.fallbackPhrases.any((p) => p.contains('你恶化了')), isTrue);
      expect(r.fallbackPhrases.any((p) => p.contains('你改善了')), isTrue);
      expect(r.fallbackPhrases.any((p) => p.contains('你掌握了')), isTrue);
    });
  });

  // ── 组9：输出文案（L439 / L605）────────────────────────────
  group('D-组9 输出文案断言（L439 / L605）', () {
    test('D-X1 mastered 复发回退 → reason 含 L2/L3（杀 L439 字符串内 / → *）', () {
      final r = transitionTeachingState(
        TeachingState.mastered,
        _st(relapseDetected: true),
      );
      expect(r.newState, TeachingState.inProgress);
      expect(r.reason, contains('L2/L3'));
    });

    test('D-X2 表述约束块 → 条目以「  - 」开头（杀 L605 字符串内 - → +）', () {
      final s = buildEvaluationSummary(
        'd-syndrome',
        _summaryInput(
          minDiagnosisCount: 1,
          minTrainingCount: 1,
          minConsolidationObservations: 1,
        ),
      );
      expect(s.contextInjection, contains('表述约束:'));
      expect(s.contextInjection, contains('  - 不能说'));
    });
  });
}
