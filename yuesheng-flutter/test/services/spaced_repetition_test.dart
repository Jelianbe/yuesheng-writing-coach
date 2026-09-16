// ─────────────────────────────────────────────────────────────
// P2-9：FSRS 间隔重复调度纯函数测试
// ─────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/spaced_repetition.dart';

void main() {
  group('fsrsIntervalDaysFor：指数增长封顶 14', () {
    test('连续通过 0 次 → 1 天（最近失败/无记录尽快重测）', () {
      expect(fsrsIntervalDaysFor(0), 1);
    });

    test('连续通过 1..4 次 → 2^(n-1)', () {
      expect(fsrsIntervalDaysFor(1), 1);
      expect(fsrsIntervalDaysFor(2), 2);
      expect(fsrsIntervalDaysFor(3), 4);
      expect(fsrsIntervalDaysFor(4), 8);
    });

    test('连续通过 ≥5 → 封顶 14（对齐 fsrsReady ≥14 判据）', () {
      expect(fsrsIntervalDaysFor(5), 14);
      expect(fsrsIntervalDaysFor(9), 14);
    });
  });

  group('isReviewDue / reviewStatusFor', () {
    test('距上次训练达到间隔 → due', () {
      expect(isReviewDue(2, 2), isTrue); // 间隔 2 天，正好到期
      expect(isReviewDue(2, 3), isTrue);
      expect(isReviewDue(5, 14), isTrue);
    });

    test('未达间隔 → 不到期；负数天数 → 不到期', () {
      expect(isReviewDue(2, 1), isFalse);
      expect(isReviewDue(2, -1), isFalse);
    });

    test('可达提取性过半衰减 → upcoming（可预防性巩固）', () {
      expect(reviewStatusFor(3, 2), ReviewStatus.upcoming); // 间隔 4，过半
      expect(reviewStatusFor(3, 4), ReviewStatus.due);
      expect(reviewStatusFor(3, 1), ReviewStatus.fresh);
    });
  });

  group('retrievabilityFor：线性衰减', () {
    test('刚训练完 → 1.0；达间隔 → 0.0', () {
      expect(retrievabilityFor(4, 0), 1.0);
      expect(retrievabilityFor(4, 8), 0.0);
    });

    test('无记录/负天数 → 1.0（不复习从未训练的症候）', () {
      expect(retrievabilityFor(0, -1), 1.0);
    });

    test('超间隔 → clamp 到 0', () {
      expect(retrievabilityFor(1, 10), 0.0);
    });
  });
}
