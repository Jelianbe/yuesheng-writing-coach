// ─────────────────────────────────────────────────────────────
// focus_card_builder_test — 教学线 P1-4「当前焦点」卡数据组装单测
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/repositories/training_result_repository.dart';
import 'package:writingcoach/services/focus_card_builder.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('P1-4 buildFocusCardData', () {
    test('#F1 有症候画像 → top1 成为焦点，返回完整卡数据', () {
      final profile = StudentProfile(
        proficiency: ProficiencyLevel.beginner,
        confidence: 0.8,
        syndromeProfile: {
          'P004': SyndromeAggregation(
            syndromeId: 'P004',
            syndromeName: '信息倾泻症',
            occurrenceCount: 3,
            severityHistory: const [Severity.l1, Severity.l2, Severity.l2],
            latestSeverity: Severity.l2,
            trend: Trend.worsening,
            lastSeenAt: 1000,
            sessionCount: 2,
            teachingState: TeachingState.inProgress,
          ),
        },
        totalSessions: 3,
      );

      final card = buildFocusCardData(
        profile: profile,
        trainingStats: const [],
      );

      expect(card, isNotNull);
      expect(card!.focusId, 'P004');
      expect(card.focusName, '信息倾泻症');
      expect(card.focusScore, greaterThan(0));
      // 为什么：只陈述既有字段，不编造
      expect(card.reason, contains('最新 L2'));
      expect(card.reason, contains('出现 3 次'));
      expect(card.reason, contains('在恶化'));
      // 介入级别：0 次训练 → I do（示范+引导）
      expect(card.intervention, InterventionLevel.iDo);
      expect(card.stagnated, isFalse);
    });

    test('#F2 无症候画像 → null（UI 隐藏整卡）', () {
      final profile = StudentProfile(
        proficiency: ProficiencyLevel.beginner,
        confidence: 0,
        syndromeProfile: const {},
        totalSessions: 0,
      );

      final card = buildFocusCardData(
        profile: profile,
        trainingStats: const [],
      );

      expect(card, isNull);
    });

    test('#F3 训练次数映射介入级别：2-3 次 → We do；≥4 次 → You do', () {
      final profile = StudentProfile(
        proficiency: ProficiencyLevel.beginner,
        confidence: 0.8,
        syndromeProfile: {
          'P004': SyndromeAggregation(
            syndromeId: 'P004',
            syndromeName: '信息倾泻症',
            occurrenceCount: 2,
            severityHistory: const [Severity.l2, Severity.l2],
            latestSeverity: Severity.l2,
            trend: Trend.stable,
            lastSeenAt: 1000,
            sessionCount: 2,
            teachingState: TeachingState.inProgress,
          ),
        },
        totalSessions: 2,
      );

      // 3 次训练 → We do
      final weDo = buildFocusCardData(
        profile: profile,
        trainingStats: const [
          SyndromeTrainingStats(
            syndromeId: 'P004',
            passed: 2,
            partial: 1,
            failed: 0,
          ),
        ],
      );
      expect(weDo!.intervention, InterventionLevel.weDo);

      // 4 次训练 → You do
      final youDo = buildFocusCardData(
        profile: profile,
        trainingStats: const [
          SyndromeTrainingStats(
            syndromeId: 'P004',
            passed: 3,
            partial: 1,
            failed: 0,
          ),
        ],
      );
      expect(youDo!.intervention, InterventionLevel.youDo);
    });

    test('#F4 当前严重度 L3 → 回退 I do（D3 规则，不因次数高而撤脚手架）', () {
      final profile = StudentProfile(
        proficiency: ProficiencyLevel.beginner,
        confidence: 0.8,
        syndromeProfile: {
          'P004': SyndromeAggregation(
            syndromeId: 'P004',
            syndromeName: '信息倾泻症',
            occurrenceCount: 4,
            severityHistory: const [Severity.l3, Severity.l3, Severity.l3],
            latestSeverity: Severity.l3,
            trend: Trend.worsening,
            lastSeenAt: 1000,
            sessionCount: 4,
            teachingState: TeachingState.inProgress,
          ),
        },
        totalSessions: 4,
      );

      final card = buildFocusCardData(
        profile: profile,
        trainingStats: const [
          SyndromeTrainingStats(
            syndromeId: 'P004',
            passed: 4,
            partial: 0,
            failed: 0,
          ),
        ],
      );

      expect(card!.intervention, InterventionLevel.iDo);
    });

    test('#F5 停滞信号：多次诊断无改善 → stagnated 透出（stagnation 语义来自既有计算）', () {
      // detectStagnation 门槛：≥3 会话 / ≥5 诊断 / ≥4 条严重度历史，
      // 且最近 2 次严重度不轻于此前 2 次（recentAvg >= earlierAvg）
      final profile = StudentProfile(
        proficiency: ProficiencyLevel.beginner,
        confidence: 0.8,
        syndromeProfile: {
          'P004': SyndromeAggregation(
            syndromeId: 'P004',
            syndromeName: '信息倾泻症',
            occurrenceCount: 4,
            severityHistory: const [
              Severity.l1,
              Severity.l2,
              Severity.l2,
              Severity.l3,
            ],
            latestSeverity: Severity.l3,
            trend: Trend.worsening,
            lastSeenAt: 1000,
            sessionCount: 2,
            teachingState: TeachingState.inProgress,
          ),
          'P008': SyndromeAggregation(
            syndromeId: 'P008',
            syndromeName: '同义反复',
            occurrenceCount: 1,
            severityHistory: const [Severity.l3],
            latestSeverity: Severity.l3,
            trend: Trend.stable,
            lastSeenAt: 900,
            sessionCount: 1,
            teachingState: TeachingState.identified,
          ),
        },
        totalSessions: 3,
      );

      final card = buildFocusCardData(
        profile: profile,
        trainingStats: const [],
      );

      expect(card, isNotNull);
      // 总诊断 5、会话 3、严重度历史 5 条、无 improving、末尾 2 条不轻于前 2 条 → 停滞
      expect(card!.stagnated, isTrue);
    });

    test('#F6 文案不含命令式强制（R-009：只陈述建议）', () {
      final profile = StudentProfile(
        proficiency: ProficiencyLevel.beginner,
        confidence: 0.8,
        syndromeProfile: {
          'P004': SyndromeAggregation(
            syndromeId: 'P004',
            syndromeName: '信息倾泻症',
            occurrenceCount: 1,
            severityHistory: const [Severity.l2],
            latestSeverity: Severity.l2,
            trend: Trend.stable,
            lastSeenAt: 1000,
            sessionCount: 1,
            teachingState: TeachingState.inProgress,
          ),
        },
        totalSessions: 1,
      );

      final card = buildFocusCardData(
        profile: profile,
        trainingStats: const [],
      );

      expect(card, isNotNull);
      // 「建议先关注」「可练」= 建议语气；不应出现「你必须/立即/快去」
      expect(card!.reason, isNot(contains('必须')));
      expect(card.reason, isNot(contains('立即')));
    });
  });
}
