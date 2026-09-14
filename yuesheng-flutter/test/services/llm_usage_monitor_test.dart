// ─────────────────────────────────────────────────────────────
// llm_usage_monitor_test — M 批：进程内累计器
//
// 覆盖：空读数 / 累计各字段与次数 / 累计命中率 / reset / sink tear-off
// 可直接注入 / 全局单例可用。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_usage.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';

void main() {
  group('LlmUsageMonitor', () {
    late LlmUsageMonitor monitor;

    setUp(() => monitor = LlmUsageMonitor());

    test('初始为空读数', () {
      final t = monitor.totals;
      expect(t.calls, 0);
      expect(t.promptTokens, 0);
      expect(t.completionTokens, 0);
      expect(t.hitRate, 0.0);
      expect(t.totalTokens, 0);
      expect(t.missTokens, 0);
    });

    test('record 累计各字段与调用次数', () {
      monitor.record(
        const LlmUsage(
          promptTokens: 100,
          completionTokens: 20,
          cachedTokens: 80,
          reasoningTokens: 5,
        ),
        LlmUsageKind.stream,
      );
      monitor.record(
        const LlmUsage(promptTokens: 50, completionTokens: 10, cachedTokens: 0),
        LlmUsageKind.chat,
      );
      final t = monitor.totals;
      expect(t.calls, 2);
      expect(t.promptTokens, 150);
      expect(t.completionTokens, 30);
      expect(t.cachedTokens, 80);
      expect(t.reasoningTokens, 5);
      expect(t.totalTokens, 180);
      expect(t.missTokens, 70);
      expect(t.hitRate, closeTo(80 / 150, 1e-9));
    });

    test('reset 清零', () {
      monitor.record(
        const LlmUsage(promptTokens: 10, completionTokens: 1),
        LlmUsageKind.chat,
      );
      monitor.reset();
      expect(monitor.totals.calls, 0);
      expect(monitor.totals.promptTokens, 0);
    });

    test('sink tear-off 与 record 等价（可注入 LlmClient）', () {
      final LlmUsageSink sink = monitor.sink;
      sink(const LlmUsage(promptTokens: 7, completionTokens: 3), LlmUsageKind.chat);
      expect(monitor.totals.calls, 1);
      expect(monitor.totals.totalTokens, 10);
    });

    test('空读数常量与新建实例一致', () {
      const empty = LlmUsageTotals.empty;
      expect(empty.calls, 0);
      expect(empty.hitRate, 0.0);
      expect(empty.toString(), contains('calls: 0'));
    });

    test('全局共享单例可用且可独立于本地实例', () {
      final before = kSharedLlmUsageMonitor.totals.calls;
      kSharedLlmUsageMonitor.record(
        const LlmUsage(promptTokens: 1, completionTokens: 1),
        LlmUsageKind.stream,
      );
      expect(kSharedLlmUsageMonitor.totals.calls, before + 1);
      expect(monitor.totals.calls, 0);
    });
  });
}
