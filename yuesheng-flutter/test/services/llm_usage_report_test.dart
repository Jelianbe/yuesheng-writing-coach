// ─────────────────────────────────────────────────────────────
// llm_usage_report_test — 「本周调用统计」聚合
//
// 覆盖：窗口过滤（`since`）/ 类别过滤 / llm_call 识别 / token 聚合 /
//       **诚实计数**（坏行计 skipped 而非当 0 token）/ 空库 / maxRows 上限。
//
// 2026-09-20 改造：原「峰闲逐笔分档 + 金额折算」断言已随计价移除
// （理由见 `llm_cost.dart` 文件头）。现断言改为**客观 token 量**。
//
// ★ 本文件的**鉴别力设计**（均为负例，实现漏了就会红）：
// - 窗口 / 类别 / 坏行三组：漏了过滤 ⇒ 条数**变多** ⇒ 必红。
// - `reasoning 不得重复计入总量`：一个「total 含 reasoning」的实现 ⇒ 必红。
// - `cacheHitRate` 除零：一个「直接 cached/prompt」的实现 ⇒ 出 NaN ⇒ 必红。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/llm_call_log_sink.dart';
import 'package:writingcoach/services/llm_cost.dart';
import 'package:writingcoach/services/llm_usage.dart';
import 'package:writingcoach/services/llm_usage_report.dart';

/// 由**北京时间墙钟**构造绝对时刻
DateTime cst(int y, int m, int d, int h, [int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(kCstOffset);

int sec(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

/// 一条 llm_call 埋点的 context 载荷 —— **由真写入方生成，不手抄键名**。
///
/// 手抄一份 = 把「context 键口径」推算两遍：写入方改名后手抄副本静默不同步
/// （同 `DECISIONS §4-41`；`settings_page_test` 的 `#N7` 段早已按此改）。
/// **`TH-2` 新增 `reasoning_tier` 时本处暴露了该偏差** ⇒ 统一走
/// `LlmCallLogEntry.toJson()`，此后写入方加/改键自动跟随。
Map<String, dynamic> llmCtx({
  required int cached,
  required int miss,
  required int completion,
  int reasoning = 0,
  String model = 'deepseek-v4-flash',
}) => LlmCallLogEntry(
  sessionId: 's1',
  purpose: LlmCallPurpose.mainChat,
  kind: LlmUsageKind.stream,
  promptTokens: cached + miss,
  completionTokens: completion,
  cachedTokens: cached,
  reasoningTokens: reasoning,
  latencyMs: 1200,
  model: model,
).toJson();

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
  final now = cst(2026, 9, 18, 12);
  final at9 = cst(2026, 9, 14, 9);
  final at8 = cst(2026, 9, 14, 8);

  group('空库', () {
    test('全零，但仍报出周起点（UI 才能说清统计的是哪一周）', () async {
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 0);
      expect(r.totalTokens, 0);
      expect(r.cacheHitRate, 0.0);
      expect(r.skippedRows, 0);
      expect(r.sinceEpochSec, weekStartEpochSecCst(now));
    });
  });

  group('token 聚合', () {
    test('多笔累加：命中 / 未命中 / 输出分别求和', () async {
      await insertLog(
        id: 'e1',
        at: sec(at9),
        ctx: llmCtx(cached: 1000, miss: 2000, completion: 500),
      );
      await insertLog(
        id: 'e2',
        at: sec(at8),
        ctx: llmCtx(cached: 3000, miss: 1000, completion: 100),
      );

      final r = await loadWeekLlmUsage(db, nowUtc: now);

      expect(r.calls, 2);
      expect(r.cachedTokens, 4000);
      expect(r.missTokens, 3000);
      expect(r.completionTokens, 600);
      expect(r.promptTokens, 7000);
      expect(r.totalTokens, 7600);
    });

    test('缓存命中率 = 命中 /（命中 + 未命中）', () async {
      await insertLog(
        id: 'e1',
        at: sec(at8),
        ctx: llmCtx(cached: 3000, miss: 1000, completion: 100),
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.promptTokens, 4000);
      expect(r.totalTokens, 4100);
      expect(r.cacheHitRate, closeTo(0.75, 1e-9));
    });

    test('★ reasoning 只作拆解视图：不重复计入总量', () async {
      await insertLog(
        id: 'e1',
        at: sec(at8),
        // completion 已含 reasoning（协议层如此）
        ctx: llmCtx(cached: 0, miss: 0, completion: 1000, reasoning: 900),
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.reasoningTokens, 900);
      // 总量只按 1000 输出算 ⇒ 若实现误加 reasoning 会得到 1900 ⇒ 必红
      expect(r.totalTokens, 1000);
    });

    test('★ 全模型通用：不同厂商/模型名不影响统计口径', () async {
      // 同一次统计里混入多种模型 —— 统计量只取决于 token，与 model 无关
      for (final (i, m) in [
        ('deepseek-v4-flash', 'deepseek-v4-flash'),
        ('doubao-pro', 'doubao-pro'),
        ('gpt-4o-mini', 'gpt-4o-mini'),
      ].indexed) {
        await insertLog(
          id: 'm$i',
          at: sec(at8) + i,
          ctx: llmCtx(cached: 100, miss: 100, completion: 100, model: m.$2),
        );
      }
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 3);
      expect(r.cachedTokens, 300);
      expect(r.missTokens, 300);
      expect(r.completionTokens, 300);
      expect(r.totalTokens, 900);
      expect(r.cacheHitRate, closeTo(0.5, 1e-9));
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
        at: sec(at8),
        ctx: llmCtx(cached: 100, miss: 100, completion: 100),
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 1, reason: '窗口外那行不得计入');
      expect(r.skippedRows, 0, reason: '它根本不在查询集合里，也不算 skipped');
    });

    test('category 非 api 不计入、不计 skipped', () async {
      await insertLog(
        id: 'g1',
        at: sec(at8),
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
      await insertLog(id: 'bad1', at: sec(at8));
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 0);
      expect(r.skippedRows, 1);
      expect(r.totalTokens, 0);
    });

    test('event 不是 llm_call ⇒ skipped', () async {
      await insertLog(
        id: 'bad2',
        at: sec(at8),
        ctx: {'event': 'connection_test', 'ok': true},
      );
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 0);
      expect(r.skippedRows, 1);
    });

    test('缺 miss_tokens / 类型不对 ⇒ skipped（不补零）', () async {
      final missing = llmCtx(cached: 10, miss: 10, completion: 10)
        ..remove('miss_tokens');
      await insertLog(id: 'bad3', at: sec(at8), ctx: missing);
      await insertLog(
        id: 'bad4',
        at: sec(at8),
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
        at: sec(at8),
        ctx: llmCtx(cached: 0, miss: 1000, completion: 0),
      );
      await insertLog(id: 'bad', at: sec(at8));
      final r = await loadWeekLlmUsage(db, nowUtc: now);
      expect(r.calls, 1);
      expect(r.skippedRows, 1);
      expect(r.totalTokens, 1000);
    });
  });

  group('maxRows 保护', () {
    test('超上限时截断（本用例只钉「上限真的生效」）', () async {
      for (var i = 0; i < 5; i++) {
        await insertLog(
          id: 'r$i',
          at: sec(at8) + i,
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
