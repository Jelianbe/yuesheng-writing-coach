// ─────────────────────────────────────────────────────────────
// feedback_tier_test — M2→M3 fading 支架渐退（ADR-C134 批2）
//
// 验收判据②：同一症候 prior=N 时注入块递减（指认+示范 → 根因+方向 → 引导提问）；
// scheduler 生产接线 selectVariantForRecurrence 的资格过滤 / 功能偏好 / 试点外回退。
//
// N 口径：prior = countConfirmedDiagnosesBySyndrome 在本轮落库前的 confirmed 计数
// （不含本轮）。c=0→N=1（默认路径，不注入）；c=1→N=2（根因+方向）；c≥2→N≥3（提问）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/feedback_tier.dart';
import 'package:writingcoach/services/feedback_variant_pool.dart';
import 'package:writingcoach/services/feedback_variant_scheduler.dart';

void main() {
  group('tierForPriorCount · 层级映射', () {
    test('c=0 → firstTouch（N=1 默认教学路径）', () {
      expect(tierForPriorCount(0), FeedbackTier.firstTouch);
    });
    test('c=1 → rootCauseOnly（N=2 只指根因+方向）', () {
      expect(tierForPriorCount(1), FeedbackTier.rootCauseOnly);
    });
    test('c=2 → guidedRecall（N≥3 引导自主指认）', () {
      expect(tierForPriorCount(2), FeedbackTier.guidedRecall);
    });
    test('c≥3 仍为 guidedRecall', () {
      expect(tierForPriorCount(5), FeedbackTier.guidedRecall);
    });
  });

  group('buildFadingBlock · 注入块按层级递减', () {
    test('无复发（空表 / 全部 c<1）→ null（不注入，走默认路径）', () {
      expect(buildFadingBlock({}, FeedbackEligibility.all), isNull);
      expect(buildFadingBlock({'P018': 0}, FeedbackEligibility.all), isNull);
    });

    test('N=2（c=1）→ 根因+方向块，无引导提问', () {
      final block = buildFadingBlock({'P018': 1}, FeedbackEligibility.all);
      expect(block, isNotNull);
      expect(block, contains('[P018]'));
      expect(block, contains('只指根因与方向'));
      // N=2 不得出现 N≥3 的引导提问句
      expect(block, isNot(contains('你发现这一处的问题了吗')));
    });

    test('N≥3（c≥2）+ highStable → 引导提问「你发现了吗」且不提示答案', () {
      final block = buildFadingBlock({
        'P021': 2,
      }, FeedbackEligibility.highStableOnly);
      expect(block, isNotNull);
      expect(block, contains('你发现这一处的问题了吗'));
      expect(block, contains('不要提示答案'));
    });

    test('N≥3 + 低稳定资格 → 安全降级为根因+方向（不用提问类）', () {
      final block = buildFadingBlock(
        {'P021': 3},
        FeedbackEligibility.all, // 低水平/消沉
      );
      expect(block, isNotNull);
      expect(block, isNot(contains('你发现这一处的问题了吗')));
      expect(block, contains('只指根因与方向'));
    });

    test('多症候混合：c=1 根因 / c≥2 提问 各自成线', () {
      final block = buildFadingBlock({
        'P018': 1,
        'P005': 3,
      }, FeedbackEligibility.highStableOnly);
      expect(block, isNotNull);
      expect(block, contains('[P018]'));
      expect(block, contains('[P005]'));
      expect(block, contains('只指根因与方向')); // P018 c=1
      expect(block, contains('你发现这一处的问题了吗')); // P005 c=3
    });
  });

  group('scheduler 生产接线 · selectVariantForRecurrence', () {
    test('prior=1 → 直给判断类（指根因方向，非提问）', () {
      final v = selectVariantForRecurrence('P018', 1, FeedbackEligibility.all);
      expect(v, isNotNull);
      expect(v!.function, FeedbackFunction.directJudgment);
    });

    test('prior≥2 + highStable → 引导提问类', () {
      final v = selectVariantForRecurrence(
        'P018',
        2,
        FeedbackEligibility.highStableOnly,
      );
      expect(v, isNotNull);
      expect(v!.function, FeedbackFunction.guidedQuestion);
    });

    test('prior≥2 + 低稳定 → 降级直给（不越权选提问）', () {
      final v = selectVariantForRecurrence('P018', 2, FeedbackEligibility.all);
      expect(v, isNotNull);
      expect(v!.function, isNot(FeedbackFunction.guidedQuestion));
    });

    test('试点外症候（无池内变体）→ null（回退纯层级指令）', () {
      expect(
        selectVariantForRecurrence(
          'P999',
          2,
          FeedbackEligibility.highStableOnly,
        ),
        isNull,
      );
    });
  });

  group('R-009 形态审计 · 注入块文本', () {
    test('块内不打分、提问不提示答案', () {
      final block = buildFadingBlock({
        'P018': 1,
        'P021': 2,
      }, FeedbackEligibility.highStableOnly)!;
      // 无评分词
      expect(block.contains('分'), isFalse, reason: '注入块不得出现评分词');
      // 引导提问必须带「不提示答案」护栏
      expect(block, contains('不要提示答案'));
    });
  });
}
