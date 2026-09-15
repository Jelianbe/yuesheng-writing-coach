// ─────────────────────────────────────────────────────────────
// llm_call_log_sink — LLM 调用埋点的**落库出口**（TH 九批）
//
// 动因（TH 六/七/八 三批同源卡点）：「Teacher 是否被调用」「产出量多少」
// 「这批花了多少钱」在 DB 与日志里**都不可观测** —— M 批的用量采集只
// 在 kDebugMode 下 debugPrint、进程重启即清零，且无业务链路标识。
// 结果：审计批反复困在「n=1 无法定论」。
//
// 形态：与 [LlmUsageMonitor] 同构（LlmUsageSink 的实现），但把读数
// **持久化**到既有 error_logs 表 —— 复用 [ErrorHandler.captureError]
// 而非自建 DAO，理由：
//   ① 它已处理「DB 未 ready → 内存入队（有界 200）」的边界；
//   ② 它已做 A12 脱敏（防 API Key 经日志泄漏）；
//   ③ error_logs 有 (level, created_at) / (category, created_at) 索引。
//
// 落库形态：level='info' + category='api' —— 与真实错误（warn/error）
// **天然分离**，故不污染错误查询；`context` JSON 承载结构化字段，
// event='llm_call' 为查询锚点。
//
// 纪律（对齐 M 批 / _observeReplyLength）：埋点是**旁路** —— writer
// 抛错、DB 不可用都**不得阻断主流程**，也不改变任何既有返回值。
// ─────────────────────────────────────────────────────────────

import 'error_handler.dart';
import 'llm_usage.dart';

/// 单条调用埋点的结构化载荷。
///
/// 字段口径与审计脚本（`_th*.py` 读 `error_logs.context`）对齐，用
/// snake_case；**不含成本折算**（单价会变，且成本结论须显式声明峰/闲
/// 时段（台账 §一.2）⇒ 折算留给查询侧，本层只存原始 token）。
class LlmCallLogEntry {
  /// 所属会话（调用点拿不到时为 null）
  final String? sessionId;

  /// 业务链路（TH 九批新维度）
  final LlmCallPurpose purpose;

  /// 传输形态
  final LlmUsageKind kind;

  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
  final int reasoningTokens;

  /// 请求发出到 usage 帧到达的毫秒数（语义见 [LlmCallContext.latencyMs]）
  final int? latencyMs;

  final String? model;

  const LlmCallLogEntry({
    required this.sessionId,
    required this.purpose,
    required this.kind,
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedTokens,
    required this.reasoningTokens,
    this.latencyMs,
    this.model,
  });

  /// 未命中缓存的输入 token（全价计费部分）——预计算，免查询侧重复算。
  int get missTokens {
    final miss = promptTokens - cachedTokens;
    return miss > 0 ? miss : 0;
  }

  /// 落 error_logs.context 的 JSON 载荷。
  Map<String, dynamic> toJson() => {
    'event': 'llm_call',
    'session_id': sessionId,
    'purpose': purpose.name,
    'kind': kind.name,
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'cached_tokens': cachedTokens,
    'reasoning_tokens': reasoningTokens,
    'miss_tokens': missTokens,
    'latency_ms': latencyMs,
    'model': model,
  };

  @override
  String toString() =>
      'LlmCallLogEntry(${purpose.name}/${kind.name} '
      'prompt=$promptTokens completion=$completionTokens '
      'cached=$cachedTokens miss=$missTokens reasoning=$reasoningTokens'
      '${latencyMs == null ? '' : ' latency=${latencyMs}ms'}'
      '${model == null ? '' : ' model=$model'})';
}

/// 落库通道签名（便于测试注入收集器，不触碰 DB / 全局单例）
typedef LlmCallLogWriter = void Function(LlmCallLogEntry entry);

/// LLM 调用埋点出口。可直接作为 [LlmUsageSink] 交给 LlmClient
/// （`LlmClient(..., usageSink: sink.call)`）。
class LlmCallLogSink {
  final LlmCallLogWriter _writer;

  LlmCallLogSink({LlmCallLogWriter? writer})
    : _writer = writer ?? _defaultWriter;

  /// 缺省通道：写 error_logs（info 级、api 类）。
  ///
  /// message 只放链路名（**不放正文 / 不放 token 数**，避免与 context
  /// 重复且便于按 level+category 索引过滤）；结构化字段全在 context。
  static void _defaultWriter(LlmCallLogEntry entry) {
    ErrorHandler.instance.captureError(
      level: 'info',
      category: 'api',
      message: '[llm_call] ${entry.purpose.name}/${entry.kind.name}',
      context: entry.toJson(),
    );
  }

  /// [LlmUsageSink] 适配（tear-off 入口）。
  ///
  /// **永不抛出** —— 埋点是旁路：写入失败不得影响请求结果。
  void call(LlmUsage usage, LlmUsageKind kind) {
    try {
      _writer(_toEntry(usage, kind));
    } catch (_) {
      // 观测失败静默（对齐 LlmUsageMonitor.record 纪律）
    }
  }

  /// 组装埋点载荷（R-019 拆出：`call` 只留 try 包装）。
  LlmCallLogEntry _toEntry(LlmUsage usage, LlmUsageKind kind) {
    final ctx = usage.context;
    return LlmCallLogEntry(
      sessionId: ctx?.sessionId,
      purpose: ctx?.purpose ?? LlmCallPurpose.unknown,
      kind: kind,
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens,
      cachedTokens: usage.cachedTokens,
      reasoningTokens: usage.reasoningTokens,
      latencyMs: ctx?.latencyMs,
      model: usage.model,
    );
  }
}
