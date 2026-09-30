// ─────────────────────────────────────────────────────────────
// llm_cost_test — 用量模型 / 周起点
//
// 2026-09-20 改造：原文件测「单价 / 峰闲判档 / 折算」，现测**全模型通用用量**。
// 峰闲判档与单价折算**已被整体移除**（理由见 `llm_cost.dart` 文件头：
// 「峰时 ×2」只对 DeepSeek 成立，套其它厂商会捏造费用）。
//
// C18（2026-09-30）：死类 LlmTokenUsage 已删（无写入方，真路径 =
// llm_usage.dart LlmUsage）；其派生量/命中率钉子随之删除。本文件现只保留：
// ① 周起点必须按**北京时间**（非设备本地时）—— 见下组。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_cost.dart';

/// 由**北京时间墙钟**构造绝对时刻（显式 −8h），**不看宿主时区**。
DateTime cst(int y, int m, int d, int h, [int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(kCstOffset);

void main() {
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
