// ─────────────────────────────────────────────────────────────
// time_format 单元测试 — 相对时间格式化
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/utils/time_format.dart';

void main() {
  // 固定"现在"：2026-08-07 12:00:00
  final now = DateTime(2026, 8, 7, 12, 0, 0);

  test('刚刚（<60s）', () {
    expect(
      formatRelativeTime(now.millisecondsSinceEpoch ~/ 1000, now: now),
      '刚刚',
    );
    expect(
      formatRelativeTime(
        now.subtract(const Duration(seconds: 59)).millisecondsSinceEpoch ~/
            1000,
        now: now,
      ),
      '刚刚',
    );
  });

  test('N 分钟前（<60min）', () {
    expect(
      formatRelativeTime(
        now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
        now: now,
      ),
      '5 分钟前',
    );
  });

  test('N 小时前（<24h）', () {
    expect(
      formatRelativeTime(
        now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch ~/ 1000,
        now: now,
      ),
      '3 小时前',
    );
  });

  test('N 天前（<7d）', () {
    expect(
      formatRelativeTime(
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
        now: now,
      ),
      '2 天前',
    );
  });

  test('超过一周 → yyyy-MM-dd', () {
    final ts = DateTime(2026, 7, 20, 10, 30).millisecondsSinceEpoch ~/ 1000;
    expect(formatRelativeTime(ts, now: now), '2026-07-20');
  });
}
