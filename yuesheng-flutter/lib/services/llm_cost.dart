// ─────────────────────────────────────────────────────────────
// llm_cost — LLM 用量统计的**唯一实现点**
//
// ## 2026-09-20 改造：从「DeepSeek 专属计价」改为「全模型通用用量」
//
// 改造前本文件按「峰时 = 闲时 × 2」折算 —— 该规则**只对 DeepSeek 成立**
// （DeepSeek 有错峰折扣时段）。对其它厂商（豆包 / OpenAI / 通义 / 智谱 …）
// 该假设**是错的**：它们没有错峰计价，强行套时段会产生**凭空捏造的费用**。
//
// 舰长裁定：**「花多少记多少」** ⇒ 不再推算费用，改为**只统计客观用量**：
//   · 调用次数
//   · 总 token 消耗（输入 / 输出）
//   · 缓存命中率
//
// 这三项**不依赖任何厂商的计价规则** ⇒ 对全部模型通用、也永不会因调价而失真。
//
// ## 为什么不再显示「元」
//
// 单价是**厂商私有且会变**的事实，本机无从核实用户实际签约价。此前那套
// 单价表（0.02 / 1.00 / 4.00）来自单次 DeepSeek 账单回填，**不具备跨厂商
// 普适性**。继续显示折算金额等于向用户**断言一个我们无法保证的数字**。
// ⇒ 本文件不再输出货币金额，只输出**可核实的 token 计数**。
//
// ## 时区（唯一保留的时间逻辑）
//
// 「本周」起点仍是**北京时间周一 00:00**：这是**用户视角的日历归属**，
// 与厂商计价无关，故保留。设备若不在 UTC+8，用 `DateTime.now().hour`
// 会把周界算错 ⇒ 一律显式 `toUtc() + 8h`。
//
// ## ⚠️ 最容易错的一点
//
// `completion_tokens` 在协议层**已含**推理 token（`LlmUsageTotals.completionTokens`
// 注释、`llm_usage.dart` 同），`reasoning_tokens` 是**拆解视图**而非额外项
// ⇒ 统计总量时**不得**再加 `reasoningTokens`。
// ─────────────────────────────────────────────────────────────

/// 北京时区相对 UTC 的固定偏移。
///
/// 中国全境单一时区、**无夏令时** ⇒ 用固定偏移即可，无需时区库。
const Duration kCstOffset = Duration(hours: 8);

/// 北京时间墙钟视图。
///
/// 返回的 `DateTime` 其 **UTC 标记位被复用为「北京时间字段」**（不吃设备时区）。
/// 私有：只供求周起点使用，不外泄以免被误当真实 UTC。
DateTime _cstWallClock(DateTime atUtc) => atUtc.toUtc().add(kCstOffset);

/// 一次调用的用量（**客观 token 计数**，不含任何金额）。
///
/// 不可变。字段全部来自厂商 response 的 `usage` 帧，无一由本机推算。
class LlmTokenUsage {
  /// 输入中**命中缓存**的 token（通常单价更低，但本类不涉及单价）
  final int cachedTokens;

  /// 输入中**未命中缓存**的 token
  final int missTokens;

  /// 输出 token（**已含推理**，勿再加 `reasoningTokens`）
  final int completionTokens;

  /// 推理 token（**拆解视图**：已含在 [completionTokens] 内，仅用于展示）
  final int reasoningTokens;

  const LlmTokenUsage({
    this.cachedTokens = 0,
    this.missTokens = 0,
    this.completionTokens = 0,
    this.reasoningTokens = 0,
  });

  /// 输入侧总 token
  int get promptTokens => cachedTokens + missTokens;

  /// 总 token（输入 + 输出）
  int get totalTokens => promptTokens + completionTokens;

  /// 缓存命中率（0.0–1.0）；无输入 token 时 0.0（不除零）
  double get cacheHitRate =>
      promptTokens > 0 ? cachedTokens / promptTokens : 0.0;

  @override
  String toString() =>
      'LlmTokenUsage(hit=$cachedTokens, miss=$missTokens, '
      'out=$completionTokens, reasoning=$reasoningTokens)';
}

/// 「本周」起点 = 北京时间**本周一 00:00**，返回其 **UTC epoch 秒**
/// （与 `error_logs.created_at` 同一标度，可直接进 SQL 比较）。
///
/// 一周的第一天取**周一**（与北京时间惯例一致；`DateTime.monday == 1`）。
int weekStartEpochSecCst(DateTime nowUtc) {
  final cst = _cstWallClock(nowUtc);
  // 以 UTC 字段承载「北京时间的年月日」
  final dayStartCst = DateTime.utc(cst.year, cst.month, cst.day);
  final mondayCst = dayStartCst.subtract(Duration(days: cst.weekday - 1));
  // 把墙钟换回真实 UTC：减去偏移
  return mondayCst.subtract(kCstOffset).millisecondsSinceEpoch ~/ 1000;
}
