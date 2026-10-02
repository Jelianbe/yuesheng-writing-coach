// ─────────────────────────────────────────────────────────────
// feedback_variant_pool_test — 变体池完整性（ADR-C132 §8 验收①⑥ 数据面）
//
// 断言（研讨报告 §4 + ADR-C132 §4）：
//   1. 试点症候（P018/P005/P021）每症候 ≥3 变体
//   2. 每变体模板含 {anchor} 锚定占位符
//   3. 引导提问类必须声明 highStableOnly 资格（资格门）
//   4. 声明的占位符真实出现在模板中
//   5. 四类反馈功能均有覆盖（主标签互斥由单值枚举保证）
//   6. R-009 形态抽查：直给判断不含打分/成句改法、提问类带方向兜底
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/feedback_variant_pool.dart';

void main() {
  group('kFeedbackVariantPool 完整性', () {
    test('池无违规（validateVariantPool 返回 null）', () {
      expect(validateVariantPool(), isNull);
    });

    test('试点症候每症候 ≥3 变体', () {
      for (final sid in const ['P018', 'P005', 'P021']) {
        expect(
          variantsForSyndrome(sid).length,
          greaterThanOrEqualTo(3),
          reason: '症候 $sid 变体数不足 3',
        );
      }
    });

    test('四类反馈功能均有覆盖', () {
      final functions = kFeedbackVariantPool.map((v) => v.function).toSet();
      for (final f in FeedbackFunction.values) {
        expect(functions, contains(f), reason: '缺少 $f 类变体');
      }
    });

    test('提问类全部 highStableOnly、非提问类无 highStableOnly', () {
      for (final v in kFeedbackVariantPool) {
        if (v.function == FeedbackFunction.guidedQuestion) {
          expect(
            v.eligibility,
            FeedbackEligibility.highStableOnly,
            reason: '${v.id}: 提问类必须声明 highStableOnly',
          );
        } else {
          expect(
            v.eligibility,
            FeedbackEligibility.all,
            reason: '${v.id}: 非提问类默认 all',
          );
        }
      }
    });

    test('R-009 形态抽查：直给判断不评分、提问类有方向兜底', () {
      final direct = kFeedbackVariantPool.where(
        (v) => v.function == FeedbackFunction.directJudgment,
      );
      for (final v in direct) {
        expect(
          v.template.contains('分'),
          isFalse,
          reason: '${v.id}: 直给判断不得出现评分词',
        );
      }
      final question = kFeedbackVariantPool.where(
        (v) => v.function == FeedbackFunction.guidedQuestion,
      );
      for (final v in question) {
        expect(
          v.template.contains('你'),
          isTrue,
          reason: '${v.id}: 提问须以学员为主语（方向兜底，非开放式放养）',
        );
      }
    });
  });
}
