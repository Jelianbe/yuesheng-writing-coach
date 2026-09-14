// ─────────────────────────────────────────────────────────────
// llm_usage — LLM 调用用量（token）观测的数据层（M 批）
//
// 动因：本仓此前只有「估算」闸门（token_budget_guard：字符 × 系数），
// **从未接真实 token 计数** —— 响应里的 usage 被整块丢弃，lib/ 全库
// 对 usage 零访问。注入精细化专项要回答「每轮实际发了多少、缓存命中
// 多少」，必须先有真实读数。
//
// 实测（2026-09-14，DeepSeek 官方端点）：
//   - 非流式：响应顶层 `usage` 含 prompt_tokens / completion_tokens /
//     total_tokens / prompt_cache_hit_tokens / prompt_cache_miss_tokens
//     / completion_tokens_details.reasoning_tokens。
//   - 流式：`stream_options.include_usage` **未设**时 usage 仍然返回 ——
//     随**最后一个 chunk**（该 chunk 的 delta.content 为空串、
//     finish_reason 非空）与 choices **同级**下发。⇒ 不需要改请求体，
//     也不存在「独立的空 choices 块」。
//
// 容错是硬要求：llm_fallback 会轮换备选端点，非 DeepSeek provider 是否
// 带 usage 未知 ⇒ 解析失败一律返回 null 静默降级，绝不影响主链路。
// ─────────────────────────────────────────────────────────────

/// 用量来源链路（用于在同一 monitor 上区分不同调用路径的读数）
enum LlmUsageKind {
  /// 流式 SSE（streamChat）
  stream,

  /// 非流式（chatCompletion / testLlmConnection）
  chat,
}

/// 单次 LLM 调用的用量读数（不可变值对象）
class LlmUsage {
  /// 输入 token（system prompt + 历史 + 本轮输入）
  final int promptTokens;

  /// 输出 token（推理模型的 reasoning token 计入其中）
  final int completionTokens;

  /// 输入中**命中缓存**的 token 数。DeepSeek 取顶层
  /// `prompt_cache_hit_tokens`，OpenAI 取 `prompt_tokens_details.cached_tokens`；
  /// 均无此字段时为 0。
  final int cachedTokens;

  /// 输出中**推理** token 数（`completion_tokens_details.reasoning_tokens`），
  /// 非推理模型为 0。注意：推理 token 同样计费，但不会出现在正文里。
  final int reasoningTokens;

  /// 响应顶层回带的模型名（端点可能规范化，如请求 `deepseek-v4-flash`
  /// 实际回 `deepseek-flash`）；端点未回时为 null。
  final String? model;

  const LlmUsage({
    required this.promptTokens,
    required this.completionTokens,
    this.cachedTokens = 0,
    this.reasoningTokens = 0,
    this.model,
  });

  /// 总 token。按定义相加而非取端点的 `total_tokens`，避免端点漏回该
  /// 字段时读数缺失。
  int get totalTokens => promptTokens + completionTokens;

  /// 输入中**未命中缓存**的 token 数（缓存 miss = 全价计费部分）
  int get missTokens {
    final miss = promptTokens - cachedTokens;
    return miss > 0 ? miss : 0;
  }

  /// 缓存命中率（0.0–1.0）。[promptTokens] 为 0 时返回 0.0（不除零）。
  double get hitRate => promptTokens > 0 ? cachedTokens / promptTokens : 0.0;

  /// 从响应中的 `usage` 对象解析。
  ///
  /// 容错契约（**返回 null 而非抛异常**）：
  ///   - [raw] 不是 Map（null / String / List / num …）⇒ null；
  ///   - `prompt_tokens` 与 `completion_tokens` **都**取不到 ⇒ null
  ///     （这不是一个可用的 usage 块，不构成读数）；
  ///   - 单个字段缺失或类型不符 ⇒ 该字段按 0 计，不因此整体作废。
  static LlmUsage? fromJson(Object? raw, {String? model}) {
    if (raw is! Map) return null;
    final prompt = _intOrNull(raw['prompt_tokens']);
    final completion = _intOrNull(raw['completion_tokens']);
    if (prompt == null && completion == null) return null;
    return LlmUsage(
      promptTokens: prompt ?? 0,
      completionTokens: completion ?? 0,
      cachedTokens: _cachedFrom(raw),
      reasoningTokens: _reasoningFrom(raw),
      model: model,
    );
  }

  /// 缓存命中数：优先 DeepSeek 顶层键，其次 OpenAI 的详情嵌套键
  static int _cachedFrom(Map raw) {
    final top = _intOrNull(raw['prompt_cache_hit_tokens']);
    if (top != null) return top;
    final details = raw['prompt_tokens_details'];
    if (details is Map) return _intOrNull(details['cached_tokens']) ?? 0;
    return 0;
  }

  /// 推理 token 数：`completion_tokens_details.reasoning_tokens`
  static int _reasoningFrom(Map raw) {
    final details = raw['completion_tokens_details'];
    if (details is Map) return _intOrNull(details['reasoning_tokens']) ?? 0;
    return 0;
  }

  /// int / num / 数字字符串 ⇒ int；其余（null、bool、Map…）⇒ null。
  /// 数值解析同样按容错处理，避免 provider 用字符串回数字时抛错。
  static int? _intOrNull(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  String toString() =>
      'LlmUsage(prompt: $promptTokens, completion: $completionTokens, '
      'cached: $cachedTokens, miss: $missTokens, reasoning: $reasoningTokens, '
      'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%'
      '${model == null ? '' : ', model: $model'})';
}

/// 用量上报出口。LlmClient 通过构造器接收本函数，缺省上报到全局
/// [kSharedLlmUsageMonitor]（见 llm_usage_monitor.dart）。
///
/// 用「注入函数」而非让 LlmClient 直连具体 monitor：测试可传自己的实例
/// 隔离累计状态，且 LlmClient 只依赖签名、不依赖 monitor 实现。
typedef LlmUsageSink = void Function(LlmUsage usage, LlmUsageKind kind);
