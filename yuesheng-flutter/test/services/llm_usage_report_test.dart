// ─────────────────────────────────────────────────────────────
// llm_usage_report_test — 「本周用量」聚合（`N7` 批次）
//
// 覆盖：窗口过滤（`since`）/ 类别过滤 / llm_call 识别 / 峰闲逐笔分档 /
//       **诚实计数**（坏行计 skipped 而非当 0 token）/ 空库。
//
// ★ 本文件的**鉴别力设计**：
// - 「逐笔判档」与「整批乘同一倍数」在混合峰闲数据上给出**不同的数**
//   ⇒ 断言总额**严格落在**两界之间，且两界互不相等 ⇒ 一个「整批 ×2 或 ×1」
//   的实现必红（见 `逐笔分档` 组）。
// - 窗口/类别/坏行三组都是**负例**：若实现漏了过滤，条数会**变多** ⇒ 必红。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/llm_cost.dart';
import 'package:writingcoach/services/llm_usage_report.dart';

/// 由**北京时间墙钟**构造绝对时刻
DateTime cst(int y, int m, int d, int h, [int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(kCstOffset);

int sec(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

/// 一条 llm_call 埋点的 context 载荷（键名与 `LlmCallLogEntry.toJson` 对齐）
Map<String, dynamic> llmCtx({
  required int cached,
  required int miss,
  required int completion,
  int reasoning = 0,
}) => {
  'event': 'llm_call',
  'session_id': 's1',
  'purpose': 'mainChat',
  'kind': 'stream',
  'prompt_tokens': cached + miss,
  'completion_tokens': completion,
  'cached_tokens': cached,
  'reasoning_tokens': reasoning,
  'miss_tokens': miss,
  'latency_ms': 1200,
  'model': 'deepseek-v4-flash',
};

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> insertLog({
    required String id,
    required int at,
    String level = 'info',
    String category = 'api',
    String message = '[llm_call] mainChat/stream',
    Map<String, dynamic>? ctx,
  }) async {
    await db
        .into(db.errorLogs)
        .insert(
          ErrorLogsCompanion.insert(
            id: id,
            level: Value(level),
            category: Value(category),
            message: message,
            context: Value(ctx == null ? null : jsonEncode(ctx)),
            createdAt: Value(at),
          ),
        );
  }

  // 背景：2026-09-18 是周五 ⇒ 09-14 周一。本周起点 = 09-13 16:00 UTC。
  final now = cst(2026, 9, 18, 12); // 周五 12:00 CST（闲）
  final peakAt = cst(2026, 9, 14, 9); // 周一 09:00 CST（峰）
  final offAt = cst(2026, 9, 14, 8); // 周一 08:00 CST（闲）

  group('空库', () {
    test('全零，但仍报出周起点（UI 才能说清统计的是哪一周）', () async {
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 0);
      expect(r.costCny, 0.0);
      expect(r.skippedRows, 0);
      expect(r.sinceEpochSec, weekStartEpochSecCst(now));
    });
  });

  group('逐笔分档（★ 鉴别「整批乘倍数」错法）', () {
    test('一峰一闲 ⇒ 总额严格落在两界之间，且两界互不相等', () async {
      await insertLog(
        id: 'e1',
        at: sec(peakAt),
        ctx: llmCtx(cached: 1000, miss: 2000, completion: 500),
      );
      await insertLog(
        id: 'e2',
        at: sec(offAt),
        ctx: llmCtx(cached: 3000, miss: 1000, completion: 100),
      );

      final r = await loadWeekLlmUsage(db, nowUtc: now);

      expect(r.calls, 2);
      expect(r.peakCalls, 1);
      expect(r.cachedTokens, 4000);
      expect(r.missTokens, 3000);
      expect(r.completionTokens, 600);

      // 逐笔：峰笔 ×2 ⇒ (20+2000+2000)/1e6*2 = 0.00804；闲笔 ⇒ (60+1000+400)/1e6 = 0.00146
      expect(r.costCny, closeTo(0.0095, 1e-9));

      // 两界（整批按闲 / 整批按峰）必须都 ≠ 逐笔值
      final allOff = llmCostCny(
        cachedTokens: 4000,
        missTokens: 3000,
        completionTokens: 600,
        atUtc: offAt,
      );
      final allPeak = llmCostCny(
        cachedTokens: 4000,
        missTokens: 3000,
        completionTokens: 600,
        atUtc: peakAt,
      );
      expect(allOff, isNot(closeTo(r.costCny, 1e-9)));
      expect(allPeak, isNot(closeTo(r.costCny, 1e-9)));
      expect(r.costCny, greaterThan(allOff));
      expect(r.costCny, lessThan(allPeak));
    });

    test('缓存命中率 = 命中 /（命中 + 未命中）', () async {
      await insertLog(
        id: 'e1',
        at: sec(offAt),
        ctx: llmCtx(cached: 3000, miss: 1000, completion: 100),
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.promptTokens, 4000);
      expect(r.totalTokens, 4100);
      expect(r.cacheHitRate, closeTo(0.75, 1e-9));
    });

    test('reasoning 只作拆解视图：不重复计入成本', () async {
      await insertLog(
        id: 'e1',
        at: sec(offAt),
        // completion 已含 reasoning（协议层如此）
        ctx: llmCtx(cached: 0, miss: 0, completion: 1000, reasoning: 900),
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.reasoningTokens, 900);
      // 只按 1000 输出计费
      expect(r.costCny, closeTo(0.004, 1e-9));
    });
  });

  group('过滤（负例）', () {
    test('窗口前一行不计入', () async {
      await insertLog(
        id: 'before',
        at: sec(cst(2026, 9, 13, 23, 59)), // 周日 23:59 CST ⇒ 上一周
        ctx: llmCtx(cached: 100, miss: 100, completion: 100),
      );
      await insertLog(
        id: 'inside',
        at: sec(offAt),
        ctx: llmCtx(cached: 100, miss: 100, completion: 100),
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 1, reason: '窗口外那行不得计入');
      expect(r.skippedRows, 0, reason: '它根本不在查询集合里，也不算 skipped');
    });

    test('category 非 api 不计入、不计 skipped', () async {
      await insertLog(
        id: 'g1',
        at: sec(offAt),
        category: 'general',
        ctx: llmCtx(cached: 100, miss: 100, completion: 100),
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 0);
      expect(r.skippedRows, 0);
    });

    test('周起点整点当刻**计入**（since 为闭区间）', () async {
      await insertLog(
        id: 'edge',
        at: weekStartEpochSecCst(now),
        ctx: llmCtx(cached: 0, miss: 1000, completion: 0),
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 1);
    });
  });

  group('诚实计数：坏行计 skipped，不当 0 token 吞掉', () {
    test('context 为 null ⇒ skipped', () async {
      await insertLog(id: 'bad1', at: sec(offAt));
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 0);
      expect(r.skippedRows, 1);
      expect(r.costCny, 0.0);
    });

    test('event 不是 llm_call ⇒ skipped', () async {
      await insertLog(
        id: 'bad2',
        at: sec(offAt),
        ctx: {'event': 'connection_test', 'ok': true},
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 0);
      expect(r.skippedRows, 1);
    });

    test('缺 miss_tokens / 类型不对 ⇒ skipped（不补零）', () async {
      final missing = llmCtx(cached: 10, miss: 10, completion: 10)
        ..remove('miss_tokens');
      await insertLog(id: 'bad3', at: sec(offAt), ctx: missing);
      await insertLog(
        id: 'bad4',
        at: sec(offAt),
        ctx: llmCtx(cached: 10, miss: 10, completion: 10)
          ..['completion_tokens'] = 'nope',
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 0);
      expect(r.skippedRows, 2);
    });

    test('好事与坏事并存：只计好的，坏的单列', () async {
      await insertLog(
        id: 'ok',
        at: sec(offAt),
        ctx: llmCtx(cached: 0, miss: 1000, completion: 0),
      );
      await insertLog(id: 'bad', at: sec(offAt));
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 1);
      expect(r.skippedRows, 1);
      expect(r.costCny, closeTo(0.001, 1e-9));
    });
  });

  group('maxRows 保护', () {
    test('超上限时截断（本用例只钉「上限真的生效」）', () async {
      for (var i = 0; i < 5; i++) {
        await insertLog(
          id: 'r$i',
          at: sec(offAt) + i,
          ctx: llmCtx(cached: 0, miss: 1000, completion: 0),
        );
      }
      final capped = await loadWeekLlmUsage(db, nowUtc: now, maxRows: 3);
      expect(capped.calls, 3);
      final all = await loadWeekLlmUsage(db, nowUtc: now);
      expect(all.calls, 5);
    });
  });
}
