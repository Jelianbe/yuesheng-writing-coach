import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;

import 'llm_usage.dart';

// ─────────────────────────────────────────────────────────────
// llm_usage_monitor — 进程内用量累计器（M 批 · 出口层）
//
// 形态：仿 kSharedLlmGate（llm_concurrency_gate.dart:54）的「全局单例 +
// 可注入独立实例」写法 —— LlmClient 默认上报到此，生产零组装改动即生效。
//
// 范围（M-1 裁定）：**只做观测内核 + kDebugMode 日志**，不持久化、无 UI。
// 先拿到数据，再决定要不要面板，避免为用不上的界面付维护成本。
//
// 纪律：record **永不抛出**（观测是旁路，失败不得阻断主流程），
// 对齐 chat_service.dart _observeReplyLength 的「仅留痕、不改变行为」。
// ─────────────────────────────────────────────────────────────

/// 累计读数快照（不可变）
class LlmUsageTotals {
  /// 已观测调用次数
  final int calls;

  /// 累计输入 token
  final int promptTokens;

  /// 累计输出 token（含推理 token）
  final int completionTokens;

  /// 累计命中的输入缓存 token
  final int cachedTokens;

  /// 累计推理 token
  final int reasoningTokens;

  const LlmUsageTotals({
    required this.calls,
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedTokens,
    required this.reasoningTokens,
  });

  /// 空读数（尚未观测到任何调用）
  static const LlmUsageTotals empty = LlmUsageTotals(
    calls: 0,
    promptTokens: 0,
    completionTokens: 0,
    cachedTokens: 0,
    reasoningTokens: 0,
  );

  int get totalTokens => promptTokens + completionTokens;

  /// 累计未命中缓存的输入 token（全价部分）
  int get missTokens {
    final miss = promptTokens - cachedTokens;
    return miss > 0 ? miss : 0;
  }

  /// 累计缓存命中率（0.0–1.0）；无输入 token 时为 0.0（不除零）
  double get hitRate => promptTokens > 0 ? cachedTokens / promptTokens : 0.0;

  @override
  String toString() =>
      'calls: $calls, prompt: $promptTokens, completion: $completionTokens, '
      'cached: $cachedTokens, miss: $missTokens, '
      'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%';
}

/// 进程内累计器。不持久化 —— 重启即清零（本批定位是「尺子」不是「报表」）。
class LlmUsageMonitor {
  int _calls = 0;
  int _promptTokens = 0;
  int _completionTokens = 0;
  int _cachedTokens = 0;
  int _reasoningTokens = 0;

  /// 记账一次调用。**永不抛出** —— 观测失败不得影响请求结果。
  void record(LlmUsage usage, LlmUsageKind kind) {
    try {
      _calls++;
      _promptTokens += usage.promptTokens;
      _completionTokens += usage.completionTokens;
      _cachedTokens += usage.cachedTokens;
      _reasoningTokens += usage.reasoningTokens;
      if (kDebugMode) debugPrint('[M 批 消耗] ${_line(usage, kind)}');
    } catch (_) {
      // 观测是旁路：任何异常都不得冒泡（含 debugPrint 在极端环境下的失败）
    }
  }

  /// 当前累计读数
  LlmUsageTotals get totals => LlmUsageTotals(
    calls: _calls,
    promptTokens: _promptTokens,
    completionTokens: _completionTokens,
    cachedTokens: _cachedTokens,
    reasoningTokens: _reasoningTokens,
  );

  /// 直接注入 LlmClient 的出口（tear-off，签名与 [LlmUsageSink] 一致）
  LlmUsageSink get sink => record;

  /// 清零（测试隔离 / 会话边界用）
  @visibleForTesting
  void reset() {
    _calls = 0;
    _promptTokens = 0;
    _completionTokens = 0;
    _cachedTokens = 0;
    _reasoningTokens = 0;
  }

  /// 单轮留痕行（仿 llm_client.dart _logFirstToken 的「仅观测」措辞）
  String _line(LlmUsage u, LlmUsageKind kind) =>
      '${kind.name} prompt=${u.promptTokens} completion=${u.completionTokens} '
      'cached=${u.cachedTokens} miss=${u.missTokens} '
      'reasoning=${u.reasoningTokens} hit=${(u.hitRate * 100).toStringAsFixed(1)}%'
      '${u.model == null ? '' : ' model=${u.model}'}（仅观测）';
}

/// 应用级共享累计器（LlmClient 默认使用）
final LlmUsageMonitor kSharedLlmUsageMonitor = LlmUsageMonitor();
