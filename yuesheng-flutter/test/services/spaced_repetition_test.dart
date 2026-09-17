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

  // ─────────────────────────────────────────────────────────────
  // 批1·N2：用户回忆难度自评（again/hard/good/easy）
  // ─────────────────────────────────────────────────────────────
  group('FsrsRating.fromValue：落库值解析', () {
    test('四档合法值 → 对应枚举', () {
      expect(FsrsRating.fromValue('again'), FsrsRating.again);
      expect(FsrsRating.fromValue('hard'), FsrsRating.hard);
      expect(FsrsRating.fromValue('good'), FsrsRating.good);
      expect(FsrsRating.fromValue('easy'), FsrsRating.easy);
    });

    test('null / 未知值 → null（不抛异常，降级为「无自评」）', () {
      expect(FsrsRating.fromValue(null), isNull);
      expect(FsrsRating.fromValue(''), isNull);
      expect(FsrsRating.fromValue('AGAIN'), isNull); // 大小写敏感（落库值恒小写）
      expect(FsrsRating.fromValue('unknown'), isNull);
    });

    test('value 与落库值一一对应（防枚举改名后 DB 值漂移）', () {
      expect(FsrsRating.values.map((r) => r.value).toList(), [
        'again',
        'hard',
        'good',
        'easy',
      ]);
    });
  });

  group('effectivePassesFor：四档折算', () {
    test('again → 归零（不是减一）', () {
      expect(effectivePassesFor(0, FsrsRating.again), 0);
      expect(effectivePassesFor(3, FsrsRating.again), 0);
      expect(effectivePassesFor(9, FsrsRating.again), 0);
    });

    test('hard → −1，且有下界 0', () {
      expect(effectivePassesFor(0, FsrsRating.hard), 0);
      expect(effectivePassesFor(3, FsrsRating.hard), 2);
    });

    test('good → 不变', () {
      for (final n in [0, 1, 3, 5, 9]) {
        expect(effectivePassesFor(n, FsrsRating.good), n, reason: 'n=$n');
      }
    });

    test('easy → +1', () {
      expect(effectivePassesFor(0, FsrsRating.easy), 1);
      expect(effectivePassesFor(4, FsrsRating.easy), 5);
    });
  });

  group('★ 向后兼容：无自评路径与改造前逐点一致', () {
    // 判据：不能只靠「测试没红」。既有断言只覆盖 0/1..4/5/9 三点区间，
    // 这里把 0..10 全定义域的**期望值显式写出**（期望值独立于实现书写）。
    test('fsrsIntervalDaysFor 0..10 期望值锁定', () {
      const expected = {
        0: 1,
        1: 1,
        2: 2,
        3: 4,
        4: 8,
        5: 14,
        6: 14,
        7: 14,
        8: 14,
        9: 14,
        10: 14,
      };
      expected.forEach((n, days) {
        expect(fsrsIntervalDaysFor(n), days, reason: 'n=$n');
      });
    });

    test('阳性对照：good 档折算后与「无自评」同值（good 不应改变间隔）', () {
      for (var n = 0; n <= 6; n++) {
        expect(
          fsrsIntervalDaysFor(effectivePassesFor(n, FsrsRating.good)),
          fsrsIntervalDaysFor(n),
          reason: 'n=$n',
        );
      }
    });

    test('阴性对照：again 档确实改变间隔（证折算生效、不是空转）', () {
      expect(fsrsIntervalDaysFor(5), 14); // 无自评 = 封顶 14
      expect(fsrsIntervalDaysFor(effectivePassesFor(5, FsrsRating.again)), 1);
    });

    test('阴性对照：easy 档确实加速（n=4 → 8 天 ⇒ n=5 → 14 天）', () {
      expect(fsrsIntervalDaysFor(4), 8);
      expect(fsrsIntervalDaysFor(effectivePassesFor(4, FsrsRating.easy)), 14);
    });
  });
}
