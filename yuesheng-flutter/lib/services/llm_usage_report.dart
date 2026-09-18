// ─────────────────────────────────────────────────────────────
// llm_usage_report — 「本周用量」的**查询侧**聚合（`N7` 批次）
//
// 数据源：`error_logs` 中 `category='api'` 且 `context.event='llm_call'`
// 的埋点行（写入方 = `llm_call_log_sink.dart`，TH 九批落地）。
// **不新增表、不新增写入方** —— 本批是**纯读取**。
//
// 折算是**逐笔**做的：每行按**自己的 `created_at`** 判峰闲，再求和。
// 一整周跨了峰闲边界 ⇒ 不能整批乘同一个倍数（`llm_cost.dart` 已把判档
// 封在纯函数里）。
//
// ## 诚实计数（本文件刻意保留的两个「不好看但不撒谎」的字段）
//
// - [skippedRows]：`category='api'` 但 `context` 缺失 / 不是 `llm_call` /
//   关键字段缺失或类型不对 ⇒ **不猜、不补零**，只计数。
//   理由：本仓反复吃亏的「零命中 vs 没跑起来外观完全相同」——
//   把坏行静默当 0 token 计入，会让「本周用量」在埋点出问题时**显示一个
//   偏小的数**而看不出异常。
// - [peakCalls]：落在高峰档的调用数 ⇒ 用户能解释「为什么同样的调用量这周更贵」。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/error_log_repository.dart';
import 'llm_cost.dart';

/// 一次查询的聚合读数。不可变。
class LlmUsageReport {
  /// 计入成本的 LLM 调用次数
  final int calls;

  /// 命中缓存的输入 token
  final int cachedTokens;

  /// 未命中缓存的输入 token（全价部分）
  final int missTokens;

  /// 输出 token（**已含**推理 token）
  final int completionTokens;

  /// 推理 token（**拆解视图**，不重复计费；仅用于展示）
  final int reasoningTokens;

  /// 折算成本（元，逐笔判峰闲后求和）
  final double costCny;

  /// 落在高峰档的调用数
  final int peakCalls;

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
    required this.costCny,
    required this.peakCalls,
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
    costCny: 0,
    peakCalls: 0,
    skippedRows: 0,
    sinceEpochSec: sinceEpochSec,
  );

  /// 输入侧总 token
  int get promptTokens => cachedTokens + missTokens;

  /// 总 token（输入 + 输出）
  int get totalTokens => promptTokens + completionTokens;

  /// 缓存命中率（0.0–1.0）；无输入 token 时 0.0（不除零）
  double get cacheHitRate =>
      promptTokens > 0 ? cachedTokens / promptTokens : 0.0;

  @override
  String toString() =>
      'LlmUsageReport(calls=$calls, hit=$cachedTokens, miss=$missTokens, '
      'out=$completionTokens, ¥${costCny.toStringAsFixed(4)}, '
      'peak=$peakCalls, skipped=$skippedRows, since=$sinceEpochSec)';
}

/// 单行埋点 → 三档 token；不可解析返回 null（调用方计入 [LlmUsageReport.skippedRows]）。
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
/// 为何独立成类：`loadWeekLlmUsage` 原先把「查询 + 逐行解析 + 逐笔折算 +
/// 组装」四件事写在一个函数里（**57 行**，超 R-019 硬限 50）⇒ 这里把
/// 「逐行累加」这一职责整体提取（含判峰与折算），查询函数只留骨架。
class _UsageAccumulator {
  int calls = 0;
  int cached = 0;
  int miss = 0;
  int completion = 0;
  int reasoning = 0;
  int peak = 0;
  int skipped = 0;
  double cost = 0;

  /// 累加一行。无法解析的行只计 [skipped]，**不猜、不补零**。
  void add(ErrorLogEntry row) {
    final parsed = _parseLlmCallRow(row.context);
    if (parsed == null) {
      skipped++;
      return;
    }
    // 折算必须用**该行自己的发生时刻**判峰闲（整批乘同一倍数会算错）。
    final at = DateTime.fromMillisecondsSinceEpoch(
      row.createdAt * 1000,
      isUtc: true,
    );
    calls++;
    cached += parsed.cached;
    miss += parsed.miss;
    completion += parsed.completion;
    reasoning += parsed.reasoning;
    if (isPeakHourCst(at)) peak++;
    cost += llmCostCny(
      cachedTokens: parsed.cached,
      missTokens: parsed.miss,
      completionTokens: parsed.completion,
      atUtc: at,
    );
  }

  LlmUsageReport toReport(int sinceEpochSec) => LlmUsageReport(
    calls: calls,
    cachedTokens: cached,
    missTokens: miss,
    completionTokens: completion,
    reasoningTokens: reasoning,
    costCny: cost,
    peakCalls: peak,
    skippedRows: skipped,
    sinceEpochSec: sinceEpochSec,
  );
}

/// 查询并折算「本周」用量。
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
