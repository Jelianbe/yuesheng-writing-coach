// ─────────────────────────────────────────────────────────────
// llm_usage_report — 「本周调用统计」的**查询侧**聚合
//
// 数据源：`error_logs` 中 `category='api'` 且 `context.event='llm_call'`
// 的埋点行（写入方 = `llm_call_log_sink.dart`，TH 九批落地）。
// **不新增表、不新增写入方** —— 本文件是**纯读取**。
//
// ## 2026-09-20 改造：去掉计价，改「全模型通用用量」
//
// 原实现按峰/闲判档折算金额 —— 该规则**只对 DeepSeek 成立**，对其它厂商
// 是错的（详见 `llm_cost.dart` 文件头）。现改为只统计三项客观量：
//   · [calls] 调用次数
//   · token 消耗（[cachedTokens] / [missTokens] / [completionTokens]）
//   · [cacheHitRate] 缓存命中率
// 均**不依赖厂商计价规则** ⇒ 全模型通用。
//
// ## 诚实计数（刻意保留的「不好看但不撒谎」字段）
//
// - [skippedRows]：`category='api'` 但 `context` 缺失 / 不是 `llm_call` /
//   关键字段缺失或类型不对 ⇒ **不猜、不补零**，只计数。
//   理由：本仓反复吃亏的「零命中 vs 没跑起来外观完全相同」——
//   把坏行静默当 0 token 计入，会让「本周调用统计」在埋点出问题时**显示一个
//   偏小的数**而看不出异常。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/error_log_repository.dart';
import 'llm_cost.dart';

/// 一次查询的聚合读数。不可变。
class LlmUsageReport {
  /// 计入统计的 LLM 调用次数
  final int calls;

  /// 命中缓存的输入 token
  final int cachedTokens;

  /// 未命中缓存的输入 token
  final int missTokens;

  /// 输出 token（**已含**推理 token）
  final int completionTokens;

  /// 推理 token（**拆解视图**，已含于 [completionTokens]；仅用于展示）
  final int reasoningTokens;

  /// 有 `category='api'` 行但**无法计入**的条数（见文件头「诚实计数」）
  final int skippedRows;

  /// 统计窗口起点（UTC epoch 秒）
  final int sinceEpochSec;

  const LlmUsageReport({
    required this.calls,
    required this.cachedTokens,
    required this.missTokens,
    required this.completionTokens,
    required this.reasoningTokens,
    required this.skippedRows,
    required this.sinceEpochSec,
  });

  /// 空读数（含窗口起点，便于 UI 无数据时仍能说清「统计的是哪一周」）
  static LlmUsageReport empty({required int sinceEpochSec}) => LlmUsageReport(
    calls: 0,
    cachedTokens: 0,
    missTokens: 0,
    completionTokens: 0,
    reasoningTokens: 0,
    skippedRows: 0,
    sinceEpochSec: sinceEpochSec,
  );

  /// 输入侧总 token
  int get promptTokens => cachedTokens + missTokens;

  /// 总 token（输入 + 输出）—— 「总消耗」的主读数
  int get totalTokens => promptTokens + completionTokens;

  /// 缓存命中率（0.0–1.0）；无输入 token 时 0.0（不除零）
  double get cacheHitRate =>
      promptTokens > 0 ? cachedTokens / promptTokens : 0.0;

  @override
  String toString() =>
      'LlmUsageReport(calls=$calls, hit=$cachedTokens, miss=$missTokens, '
      'out=$completionTokens, total=$totalTokens, '
      'skipped=$skippedRows, since=$sinceEpochSec)';
}

/// 单行埋点 → 四类 token；不可解析返回 null（调用方计入 [LlmUsageReport.skippedRows]）。
({int cached, int miss, int completion, int reasoning})? _parseLlmCallRow(
  Map<String, dynamic>? ctx,
) {
  if (ctx == null) return null;
  if (ctx['event'] != 'llm_call') return null;
  int? asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
  final cached = asInt(ctx['cached_tokens']);
  final miss = asInt(ctx['miss_tokens']);
  final completion = asInt(ctx['completion_tokens']);
  final reasoning = asInt(ctx['reasoning_tokens']);
  if (cached == null || miss == null || completion == null) return null;
  return (
    cached: cached,
    miss: miss,
    completion: completion,
    reasoning: reasoning ?? 0,
  );
}

/// 逐行累加器（可变；仅本文件使用）。
///
/// 为何独立成类：查询函数只留骨架，符合 R-019（函数 ≤50 行）。
class _UsageAccumulator {
  int calls = 0;
  int cached = 0;
  int miss = 0;
  int completion = 0;
  int reasoning = 0;
  int skipped = 0;

  /// 累加一行。无法解析的行只计 [skipped]，**不猜、不补零**。
  void add(ErrorLogEntry row) {
    final parsed = _parseLlmCallRow(row.context);
    if (parsed == null) {
      skipped++;
      return;
    }
    calls++;
    cached += parsed.cached;
    miss += parsed.miss;
    completion += parsed.completion;
    reasoning += parsed.reasoning;
  }

  LlmUsageReport toReport(int sinceEpochSec) => LlmUsageReport(
    calls: calls,
    cachedTokens: cached,
    missTokens: miss,
    completionTokens: completion,
    reasoningTokens: reasoning,
    skippedRows: skipped,
    sinceEpochSec: sinceEpochSec,
  );
}

/// 查询「本周」用量。
///
/// [nowUtc] 显式传入（默认取当前 UTC）便于测试与「回到上一周」类扩展。
/// [maxRows] 保护：`queryErrorLogs` 默认 limit=100 ⇒ 必须显式放大，
/// 否则会**静默截断**成「最近 100 次调用」而用户以为是整周。
Future<LlmUsageReport> loadWeekLlmUsage(
  AppDatabase db, {
  DateTime? nowUtc,
  int maxRows = 5000,
}) async {
  final since = weekStartEpochSecCst((nowUtc ?? DateTime.now()).toUtc());
  final rows = await ErrorLogRepository(db).queryErrorLogs(
    query: ErrorLogQuery(category: 'api', since: since, limit: maxRows),
  );
  final acc = _UsageAccumulator();
  rows.forEach(acc.add);
  return acc.toReport(since);
}
