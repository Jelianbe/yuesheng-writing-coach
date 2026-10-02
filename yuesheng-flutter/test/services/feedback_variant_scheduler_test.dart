// feedback_variant_scheduler_test — 软风格层调度（ADR-C132 批2）
//
// 覆盖：资格过滤（提问类限高稳定）/ 近轮去重 / 功能偏好 / 缺变体回退 /
// 模板占位符填充。数据源 = feedback_variant_pool 试点池
// （P018 / P005 / P021，各 4 条：directJudgment / metalanguage /
// guidedQuestion / observation）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/feedback_variant_pool.dart';
import 'package:writingcoach/services/feedback_variant_scheduler.dart';

void main() {
  group('selectVariant · 资格过滤', () {
    test('#1 低稳定资格（all）→ 提问类被过滤，仍可选直给类', () {
      final v = selectVariant('P018', eligibility: FeedbackEligibility.all);
      expect(v, isNotNull);
      expect(v!.function, isNot(FeedbackFunction.guidedQuestion));
      expect(v.eligibility, FeedbackEligibility.all);
    });

    test('#2 高稳定资格 → 可选中提问类（优先偏好）', () {
      final v = selectVariant(
        'P018',
        eligibility: FeedbackEligibility.highStableOnly,
        preferFunction: FeedbackFunction.guidedQuestion,
      );
      expect(v, isNotNull);
      expect(v!.function, FeedbackFunction.guidedQuestion);
      expect(v.eligibility, FeedbackEligibility.highStableOnly);
    });

    test('#3 高稳定资格不偏好 → 不越权（不自动挑提问类，返回池首条）', () {
      final v = selectVariant(
        'P018',
        eligibility: FeedbackEligibility.highStableOnly,
      );
      expect(v, isNotNull);
      // 不偏好时无功能过滤：候选集首条 = 池内第一条（P018 首条为 all 类直给）
      expect(v!.id, variantsForSyndrome('P018').first.id);
      expect(v.eligibility, isNot(FeedbackEligibility.highStableOnly));
    });
  });

  group('selectVariant · 近轮去重与偏好', () {
    test('#4 排除近轮已用 → 换一条（excludeIds 生效）', () {
      final first = selectVariant('P018', eligibility: FeedbackEligibility.all);
      final second = selectVariant(
        'P018',
        eligibility: FeedbackEligibility.all,
        excludeIds: {first!.id},
      );
      expect(second, isNotNull);
      expect(second!.id, isNot(first.id));
    });

    test('#5 全部排除 → 返回 null（调用方回退默认话术路径）', () {
      final all = variantsForSyndrome('P018');
      final v = selectVariant(
        'P018',
        eligibility: FeedbackEligibility.all,
        excludeIds: {for (final x in all) x.id},
      );
      expect(v, isNull);
    });

    test('#6 不存在的症候 → null', () {
      final v = selectVariant('P999', eligibility: FeedbackEligibility.all);
      expect(v, isNull);
    });
  });

  group('fillVariantTemplate · 占位符填充', () {
    test('#7 填 {anchor} 与 {word} → 模板替换完成', () {
      final v = variantsForSyndrome(
        'P018',
      ).firstWhere((v) => v.function == FeedbackFunction.directJudgment);
      final text = fillVariantTemplate(v, {'anchor': '他笑了笑', 'word': '笑了笑'});
      expect(text, contains('他笑了笑'));
      expect(text, isNot(contains('{anchor}')));
    });

    test('#8 缺参占位符保持原样（不抛错，降级输出）', () {
      final v = variantsForSyndrome(
        'P018',
      ).firstWhere((v) => v.function == FeedbackFunction.metalanguage);
      final text = fillVariantTemplate(v, {});
      expect(text, contains('{anchor}'));
    });
  });

  group('调度与数据层一致性', () {
    test('#9 池内每条变体都能被调度选中（资格自洽）', () {
      // 高稳定资格下，all + highStableOnly 全池候选都能被选到
      // （排除法逐条验证：不会出现「候选为空但池里有货」的死区）。
      final all = variantsForSyndrome('P021');
      final picked = <String>{};
      for (var i = 0; i < all.length; i++) {
        final v = selectVariant(
          'P021',
          eligibility: FeedbackEligibility.highStableOnly,
          excludeIds: picked,
        );
        expect(v, isNotNull, reason: '第 $i 轮应能选中一条（池内 $i/${all.length} 已用）');
        picked.add(v!.id);
      }
      expect(picked, hasLength(all.length));
    });
  });
}
