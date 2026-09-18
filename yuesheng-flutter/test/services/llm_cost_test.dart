// ─────────────────────────────────────────────────────────────
// llm_cost_test — 单价 / 峰闲判档 / 折算 / 周起点（`N7` 批次）
//
// 本测试的两个「钉子」：
// ① **算术锚点取自台账里已被真实账单回填验证过的数**（不是我自己算的）：
//    - 36,000 hit × 0.02/百万 = ¥0.00072  ┐ `LEDGER-DETAIL.md:183` 逐项核证
//    - 22,533 miss × 1.00/百万 = ¥0.02253 ┘
//    - 16,000 输出 × 4.00/百万 = ¥0.0640  ← `:166` 的「输出（20×800）」
//    ⇒ 若有人改了单价表，这几条会立刻红。
// ② **时区判档必须用北京时间**：CST 周一 09:00 = UTC 01:00 ——
//    一个「直接读 UTC 小时」的实现会在这里给出 `false`（UTC 小时 = 1）
//    ⇒ 该用例**有鉴别力**，不是复述实现。
//
// ⚠️ **本文件测不到的**：宿主时区恰为 UTC+8 时，「读设备本地小时」这一错法
//    与正确实现**结果完全相同**（CST 就是 UTC+8）⇒ 那种实现只会在非
//    UTC+8 设备上暴露。故此处只钉「结果只取决于绝对时刻」这一契约
//    （见末组用例），**不声称**能拦住该错法。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_cost.dart';

/// 由**北京时间墙钟**构造绝对时刻（显式 −8h），**不看宿主时区**。
DateTime cst(int y, int m, int d, int h, [int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(kCstOffset);

void main() {
  group('单价口径', () {
    test('闲时三档与台账核证值一致', () {
      expect(kLlmOffPeakPrice.cachedPerM, 0.02);
      expect(kLlmOffPeakPrice.missPerM, 1.00);
      expect(kLlmOffPeakPrice.outputPerM, 4.00);
      expect(kPeakMultiplier, 2.0);
    });

    test('峰时区间 = 北京时间 09:00–12:00 与 14:00–18:00', () {
      expect(kPeakHourRangesCst.length, 2);
      expect(kPeakHourRangesCst[0], (from: 9, to: 12));
      expect(kPeakHourRangesCst[1], (from: 14, to: 18));
    });
  });

  group('isPeakHourCst — 边界（周一 2026-09-14，北京时间）', () {
    // 背景日历锚点：2026-09-18 是周五 ⇒ 09-14 周一 / 09-19 周六 / 09-20 周日
    final cases = <({DateTime at, bool peak, String why})>[
      (at: cst(2026, 9, 14, 8, 59), peak: false, why: '周一 08:59 —— 窗左外侧'),
      (at: cst(2026, 9, 14, 9), peak: true, why: '周一 09:00 —— 第一段左闭'),
      (at: cst(2026, 9, 14, 11, 59), peak: true, why: '周一 11:59 —— 第一段内'),
      (at: cst(2026, 9, 14, 12), peak: false, why: '周一 12:00 —— 第一段右开'),
      (at: cst(2026, 9, 14, 13, 59), peak: false, why: '周一 13:59 —— 午休内'),
      (at: cst(2026, 9, 14, 14), peak: true, why: '周一 14:00 —— 第二段左闭'),
      (at: cst(2026, 9, 14, 17, 59), peak: true, why: '周一 17:59 —— 第二段内'),
      (at: cst(2026, 9, 14, 18), peak: false, why: '周一 18:00 —— 第二段右开'),
      (at: cst(2026, 9, 18, 10), peak: true, why: '周五 10:00 —— 工作日'),
      (at: cst(2026, 9, 19, 10), peak: false, why: '周六 10:00 —— 同时刻但周末'),
      (at: cst(2026, 9, 20, 10), peak: false, why: '周日 10:00 —— 同时刻但周末'),
    ];
    for (final c in cases) {
      test(c.why, () {
        expect(isPeakHourCst(c.at), c.peak);
      });
    }

    test('★ 时区：CST 周一 09:00 判峰（UTC 时刻的「小时」是 1）', () {
      final at = cst(2026, 9, 14, 9);
      expect(at.hour, 1, reason: '构造前提：该瞬间的 UTC 小时 = 1');
      expect(isPeakHourCst(at), isTrue);
    });

    test('★ 时区：CST 周一 00:30 判闲 —— 该瞬间的 UTC 是「周日 16:30」', () {
      final at = cst(2026, 9, 14, 0, 30);
      expect(at.weekday, DateTime.sunday, reason: '构造前提：该瞬间 UTC 仍是周日');
      expect(at.hour, 16, reason: '构造前提：该瞬间 UTC 小时 = 16（落在 14–18 段内）');
      // 若实现读 UTC 的「小时/星期」，这里会判成高峰 ⇒ 本用例有鉴别力
      expect(isPeakHourCst(at), isFalse);
    });
  });

  group('isPeakHourCst — 「只取决于绝对时刻」契约', () {
    test('同一瞬间的 UTC 表示与本地表示同判', () {
      for (final at in [
        cst(2026, 9, 14, 9), // 峰
        cst(2026, 9, 14, 8), // 闲
      ]) {
        expect(
          isPeakHourCst(at.toLocal()),
          isPeakHourCst(at),
          reason: '判档不得依赖 DateTime 的表示形式',
        );
      }
    });
  });

  group('llmCostCny — 算术锚点（台账核证值）', () {
    test('闲时：36,000 hit + 22,533 miss = ¥0.023253', () {
      // 0.00072（:183 核证）+ 0.02253（:183 核证）
      final v = llmCostCny(
        cachedTokens: 36000,
        missTokens: 22533,
        completionTokens: 0,
        atUtc: cst(2026, 9, 14, 8),
      );
      expect(v, closeTo(0.023253, 1e-9));
    });

    test('峰时：同 token 恰好翻倍 = ¥0.046506', () {
      final v = llmCostCny(
        cachedTokens: 36000,
        missTokens: 22533,
        completionTokens: 0,
        atUtc: cst(2026, 9, 14, 9),
      );
      expect(v, closeTo(0.046506, 1e-9));
    });

    test('输出侧：16,000 输出 = ¥0.0640（:166 的「输出（20×800）」）', () {
      final v = llmCostCny(
        cachedTokens: 0,
        missTokens: 0,
        completionTokens: 16000,
        atUtc: cst(2026, 9, 14, 8),
      );
      expect(v, closeTo(0.064, 1e-9));
    });

    test('全零 ⇒ 0（不产生 -0.0 / NaN）', () {
      final v = llmCostCny(
        cachedTokens: 0,
        missTokens: 0,
        completionTokens: 0,
        atUtc: cst(2026, 9, 14, 9),
      );
      expect(v, 0.0);
      expect(v.isNaN, isFalse);
    });

    test('hit 与 miss 单价不同 ⇒ 二者不可互换', () {
      final hitOnly = llmCostCny(
        cachedTokens: 1000000,
        missTokens: 0,
        completionTokens: 0,
        atUtc: cst(2026, 9, 14, 8),
      );
      final missOnly = llmCostCny(
        cachedTokens: 0,
        missTokens: 1000000,
        completionTokens: 0,
        atUtc: cst(2026, 9, 14, 8),
      );
      expect(hitOnly, closeTo(0.02, 1e-9));
      expect(missOnly, closeTo(1.0, 1e-9));
    });
  });

  group('weekStartEpochSecCst — 周一起点（北京时间）', () {
    // 期望值在测试内**独立构造**（不硬编 epoch 数字）
    final monSep14 =
        DateTime.utc(2026, 9, 13, 16).millisecondsSinceEpoch ~/ 1000;
    final monSep07 =
        DateTime.utc(2026, 9, 6, 16).millisecondsSinceEpoch ~/ 1000;

    test('周五 → 本周一 00:00 CST', () {
      expect(weekStartEpochSecCst(cst(2026, 9, 18, 12)), monSep14);
    });

    test('周一 00:00 CST 整点 → 仍是这一天（不退到上一周）', () {
      expect(weekStartEpochSecCst(cst(2026, 9, 14, 0)), monSep14);
    });

    test('周日 23:59 CST → 属于**上一周**起点', () {
      expect(weekStartEpochSecCst(cst(2026, 9, 20, 23, 59)), monSep14);
    });

    test('周一 00:00 CST 前 1 分钟（周日 23:59）→ 上一周起点', () {
      expect(weekStartEpochSecCst(cst(2026, 9, 13, 23, 59)), monSep07);
    });

    test('周起点 ≤ 当前时刻（自洽性）', () {
      final now = cst(2026, 9, 18, 12);
      final since = weekStartEpochSecCst(now);
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;
      expect(since, lessThanOrEqualTo(nowSec));
      // 且与当前时刻相差不到 7 天
      expect(nowSec - since, lessThan(7 * 86400));
    });
  });
}
