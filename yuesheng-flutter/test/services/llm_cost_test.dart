// ─────────────────────────────────────────────────────────────
// llm_cost_test — 用量模型 / 周起点
//
// 2026-09-20 改造：原文件测「单价 / 峰闲判档 / 折算」，现测**全模型通用用量**。
// 峰闲判档与单价折算**已被整体移除**（理由见 `llm_cost.dart` 文件头：
// 「峰时 ×2」只对 DeepSeek 成立，套其它厂商会捏造费用）。
//
// 本文件保留的钉子：
// ① [LlmTokenUsage] 的**派生量**必须自洽（total = prompt + completion；
//    prompt = cached + miss）—— 这是「总消耗」主读数的算术基座。
// ② **推理 token 不得被重复计入总量**（协议层 completion 已含 reasoning）——
//    一个「total = prompt + completion + reasoning」的实现会在这里红。
// ③ 缓存命中率的**除零保护**（无输入 token 时 0.0，不是 NaN）。
// ④ 周起点必须按**北京时间**（非设备本地时）—— 见末组。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_cost.dart';

/// 由**北京时间墙钟**构造绝对时刻（显式 −8h），**不看宿主时区**。
DateTime cst(int y, int m, int d, int h, [int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(kCstOffset);

void main() {
  group('LlmTokenUsage — 派生量自洽', () {
    test('prompt = cached + miss；total = prompt + completion', () {
      const u = LlmTokenUsage(
        cachedTokens: 36000,
        missTokens: 22533,
        completionTokens: 16000,
      );
      expect(u.promptTokens, 36000 + 22533);
      expect(u.totalTokens, 36000 + 22533 + 16000);
    });

    test('★ 推理 token 不得重复计入总量（completion 已含 reasoning）', () {
      const withReasoning = LlmTokenUsage(
        cachedTokens: 0,
        missTokens: 0,
        completionTokens: 1000,
        reasoningTokens: 800,
      );
      const withoutReasoning = LlmTokenUsage(
        cachedTokens: 0,
        missTokens: 0,
        completionTokens: 1000,
      );
      // 推理 token 是拆解视图 ⇒ 总量必须**完全相同**
      expect(withReasoning.totalTokens, withoutReasoning.totalTokens);
      expect(withReasoning.totalTokens, 1000);
      // 但拆解值本身要保留（供展示）
      expect(withReasoning.reasoningTokens, 800);
    });

    test('全零 ⇒ 各派生量 0，且命中率不产生 NaN', () {
      const u = LlmTokenUsage();
      expect(u.promptTokens, 0);
      expect(u.totalTokens, 0);
      expect(u.cacheHitRate, 0.0);
      expect(u.cacheHitRate.isNaN, isFalse);
    });
  });

  group('LlmTokenUsage — 缓存命中率', () {
    test('半命中 = 0.5', () {
      const u = LlmTokenUsage(cachedTokens: 500, missTokens: 500);
      expect(u.cacheHitRate, closeTo(0.5, 1e-12));
    });

    test('全命中 = 1.0', () {
      const u = LlmTokenUsage(cachedTokens: 1000, missTokens: 0);
      expect(u.cacheHitRate, 1.0);
    });

    test('零命中 = 0.0', () {
      const u = LlmTokenUsage(cachedTokens: 0, missTokens: 1000);
      expect(u.cacheHitRate, 0.0);
    });

    test('★ 只有输出 token 时（无输入）⇒ 0.0，不除零', () {
      const u = LlmTokenUsage(completionTokens: 5000);
      expect(u.promptTokens, 0);
      expect(u.cacheHitRate, 0.0);
      expect(u.cacheHitRate.isNaN, isFalse);
    });
  });

  group('weekStartEpochSecCst — 周一起点（北京时间）', () {
    // 期望值在测试内**独立构造**（不硬编 epoch 数字）
    // 2026-09-14 是周一 ⇒ CST 00:00 = UTC 09-13 16:00
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

    test('周日 23:59 CST → 仍属本周', () {
      expect(weekStartEpochSecCst(cst(2026, 9, 20, 23, 59)), monSep14);
    });

    test('周一 00:00 CST 前 1 分钟（周日 23:59）→ 上一周起点', () {
      expect(weekStartEpochSecCst(cst(2026, 9, 13, 23, 59)), monSep07);
    });

    test('★ 时区：CST 周一 00:30 的 UTC 表示仍是「周日」', () {
      final at = cst(2026, 9, 14, 0, 30);
      expect(at.weekday, DateTime.sunday, reason: '构造前提：该瞬间 UTC 仍是周日');
      // 若实现读设备本地时而非北京时间，在非 UTC+8 设备上会算错周界
      expect(weekStartEpochSecCst(at), monSep14);
    });

    test('★ 同一瞬间的 UTC 表示与本地表示同判', () {
      final at = cst(2026, 9, 18, 12);
      expect(
        weekStartEpochSecCst(at.toLocal()),
        weekStartEpochSecCst(at),
        reason: '周界不得依赖 DateTime 的表示形式',
      );
    });

    test('周起点 ≤ 当前时刻（自洽性）', () {
      final now = cst(2026, 9, 18, 12);
      final since = weekStartEpochSecCst(now);
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;
      expect(since, lessThanOrEqualTo(nowSec));
      expect(nowSec - since, lessThan(7 * 86400));
    });
  });
}
