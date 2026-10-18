// growth_narrative_test — 「与上次相比」进步叙事装配纯函数测试
// （T-20261018-03 · B 议题 · 设计批 2026-10-18 已批）
//
// 覆盖（验收：三条句式各至少一测试 + 空态 + 无历史基准不出条目）：
//   #N1 能力行：两次带快照评估 ⇒ 均分对照（句式逐字）
//   #N2 能力行：仅一次评估 ⇒ 空叙事（不出卡）
//   #N3 能力行：快照缺维度 ⇒ 只取共有维度均值
//   #N4 能力行：评估乱序 ⇒ 按 generatedAt 排序后取末两条
//   #N5 症候行：occurrences≥2 且两次严重度已知 ⇒ 逐字句式
//   #N6 症候行：首次出现（occurrences=1）/ 无上次严重度 ⇒ 不出条目
//   #N7 症候行排序：occurrences 降序 + 症候名升序（确定性）
//   #N8 R-009 黑名单：条目文案不含评价词（进步/掌握/好转/提升/下降/达标/优秀/成功）
//   #N9 旧报告无快照 ⇒ 跳过不编造（与 AbilityProgressChart 同款纪律）

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/growth_narrative.dart';
import 'package:writingcoach/services/growth_service.dart';
import 'package:writingcoach/types/display_types.dart';
import 'package:writingcoach/types/teaching_types.dart';

EvaluationData _eval({
  required int generatedAt,
  required List<AbilityScore> abilityScores,
}) {
  return EvaluationData(
    round: 1,
    trend: EvaluationTrend.stable,
    trainingCount: 0,
    passRate: 0,
    summaryText: '',
    syndromeDetails: const [],
    abilityScores: abilityScores,
    generatedAt: generatedAt,
  );
}

AbilityScore _score(String dimension, int score) => AbilityScore(
  dimension: dimension,
  score: score,
  trend: Trend.stable,
  description: '',
);

SyndromeRecurrence _recurrence({
  required String name,
  required int occurrences,
  String? previousSeverity,
  String? currentSeverity,
}) {
  return SyndromeRecurrence(
    syndromeId: name,
    syndromeName: name,
    occurrences: occurrences,
    recovered: 0,
    recurrences: 0,
    rate: 0,
    previousSeverity: previousSeverity,
    currentSeverity: currentSeverity,
  );
}

void main() {
  group('buildGrowthNarrative — 能力行（主锚 = 上次评估）', () {
    test('#N1 两次带快照评估 ⇒ 均分对照（句式逐字）', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(
            generatedAt: 1000,
            abilityScores: [_score('情节构建', 40), _score('人物塑造', 44)],
          ),
          _eval(
            generatedAt: 2000,
            abilityScores: [_score('情节构建', 50), _score('人物塑造', 52)],
          ),
        ],
        recurrences: const [],
      );

      expect(narrative.isEmpty, isFalse);
      expect(narrative.anchorLabel, '对照 上次评估');
      expect(narrative.items, hasLength(1));
      expect(narrative.items.first.type, NarrativeItemType.ability);
      // 均分：(40+44)/2=42 → (50+52)/2=51
      expect(narrative.items.first.text, '能力评分 42 → 51');
    });

    test('#N2 仅一次评估 ⇒ 空叙事（无主锚不出卡）', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(generatedAt: 1000, abilityScores: [_score('情节构建', 40)]),
        ],
        recurrences: [
          _recurrence(
            name: '指代不清',
            occurrences: 3,
            previousSeverity: 'L3',
            currentSeverity: 'L2',
          ),
        ],
      );

      expect(narrative.isEmpty, isTrue);
      expect(narrative.items, isEmpty);
    });

    test('#N3 快照缺维度 ⇒ 只取共有维度均值', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(
            generatedAt: 1000,
            abilityScores: [_score('情节构建', 40), _score('人物塑造', 44)],
          ),
          _eval(
            generatedAt: 2000,
            abilityScores: [
              _score('情节构建', 50), // 人物塑造缺失 ⇒ 不计入
            ],
          ),
        ],
        recurrences: const [],
      );

      expect(narrative.items, hasLength(1));
      // 共有维度仅「情节构建」：40 → 50
      expect(narrative.items.first.text, '能力评分 40 → 50');
    });

    test('#N4 评估乱序 ⇒ 按 generatedAt 排序后取末两条', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(generatedAt: 3000, abilityScores: [_score('情节构建', 60)]),
          _eval(generatedAt: 1000, abilityScores: [_score('情节构建', 40)]),
          _eval(generatedAt: 2000, abilityScores: [_score('情节构建', 50)]),
        ],
        recurrences: const [],
      );

      // 末两条 = 2000(50) → 3000(60)
      expect(narrative.items.first.text, '能力评分 50 → 60');
    });

    test('#N9 旧报告无快照 ⇒ 跳过不编造', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(generatedAt: 1000, abilityScores: const []),
          _eval(generatedAt: 2000, abilityScores: const []),
        ],
        recurrences: const [],
      );

      expect(narrative.isEmpty, isTrue);
    });
  });

  group('buildGrowthNarrative — 症候复诊行（E-1 同型）', () {
    test('#N5 occurrences≥2 且两次严重度已知 ⇒ 逐字句式', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(generatedAt: 1000, abilityScores: [_score('情节构建', 40)]),
          _eval(generatedAt: 2000, abilityScores: [_score('情节构建', 50)]),
        ],
        recurrences: [
          _recurrence(
            name: '指代不清',
            occurrences: 3,
            previousSeverity: 'L3',
            currentSeverity: 'L2',
          ),
        ],
      );

      expect(narrative.items, hasLength(2));
      expect(narrative.items[1].type, NarrativeItemType.severity);
      expect(narrative.items[1].text, '指代不清 · 第 3 次出现 · 较上次 L3 → L2');
    });

    test('#N6 首次出现 / 无上次严重度 ⇒ 不出条目', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(generatedAt: 1000, abilityScores: [_score('情节构建', 40)]),
          _eval(generatedAt: 2000, abilityScores: [_score('情节构建', 50)]),
        ],
        recurrences: [
          _recurrence(name: '首次症候', occurrences: 1),
          _recurrence(
            name: '无上次严重度',
            occurrences: 4,
            previousSeverity: null,
            currentSeverity: 'L2',
          ),
        ],
      );

      // 只剩能力行（两条症候行都被逐条自判挡掉）
      expect(narrative.items, hasLength(1));
      expect(narrative.items.single.type, NarrativeItemType.ability);
    });

    test('#N7 排序确定性：occurrences 降序 + 症候名升序', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(generatedAt: 1000, abilityScores: [_score('情节构建', 40)]),
          _eval(generatedAt: 2000, abilityScores: [_score('情节构建', 50)]),
        ],
        recurrences: [
          _recurrence(
            name: '乙症候',
            occurrences: 2,
            previousSeverity: 'L2',
            currentSeverity: 'L1',
          ),
          _recurrence(
            name: '甲症候',
            occurrences: 5,
            previousSeverity: 'L3',
            currentSeverity: 'L2',
          ),
          _recurrence(
            name: '丙症候',
            occurrences: 2,
            previousSeverity: 'L1',
            currentSeverity: 'L2',
          ),
        ],
      );

      final severityTexts = narrative.items
          .where((i) => i.type == NarrativeItemType.severity)
          .map((i) => i.text)
          .toList();
      // occurrences 降序（甲 5 先）；同 occurrences 按症候名 compareTo 升序
      // （Dart String.compareTo = UTF-16 码元序：「丙」U4E19 < 「乙」U4E59 ⇒ 丙先）。
      expect(severityTexts, [
        '甲症候 · 第 5 次出现 · 较上次 L3 → L2',
        '丙症候 · 第 2 次出现 · 较上次 L1 → L2',
        '乙症候 · 第 2 次出现 · 较上次 L2 → L1',
      ]);
    });
  });

  group('buildGrowthNarrative — R-009 黑名单', () {
    test('#N8 条目文案不含评价词', () {
      final narrative = buildGrowthNarrative(
        evaluationHistory: [
          _eval(generatedAt: 1000, abilityScores: [_score('情节构建', 40)]),
          _eval(generatedAt: 2000, abilityScores: [_score('情节构建', 50)]),
        ],
        recurrences: [
          _recurrence(
            name: '指代不清',
            occurrences: 3,
            previousSeverity: 'L3',
            currentSeverity: 'L2',
          ),
        ],
      );

      for (final item in narrative.items) {
        for (final word in NarrativeText.bannedWords) {
          expect(
            item.text.contains(word),
            isFalse,
            reason: '条目含评价词「$word」：${item.text}',
          );
        }
      }
      expect(narrative.anchorLabel.contains('达标'), isFalse);
    });
  });
}
