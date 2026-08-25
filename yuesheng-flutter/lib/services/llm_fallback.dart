// ─────────────────────────────────────────────────────────────
// LLM 备选端点链 — B1-1 fallback chain（纯逻辑，无 IO）
// 主端点失败时按序切换备选（baseUrl 必填，model/apiKey 可选
// 继承主配置）。存储键 yuesheng_api_fallbacks 存 JSON 数组；
// 未配置 = 空列表 = 行为与现状零差异（R-010 最小化范围）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'llm_config_storage.dart';

/// 备选端点声明（JSON 的一条记录）
class LlmFallbackEntry {
  final String baseUrl;

  /// null = 沿用主配置 model
  final String? model;

  /// null = 沿用主配置 apiKey（备选服务商同 key 中转场景）
  final String? apiKey;

  const LlmFallbackEntry({required this.baseUrl, this.model, this.apiKey});

  Map<String, dynamic> toJson() => {
    if (model != null) 'model': model,
    if (apiKey != null) 'apiKey': apiKey,
    'baseUrl': baseUrl,
  };
}

/// 解析存储中的 fallback JSON。容错优先：
/// 空/null/非 JSON/非数组/元素缺 baseUrl → 跳过该条；
/// 整体异常一律返回空列表（配置损坏不应放大为运行时崩溃）。
List<LlmFallbackEntry> parseFallbacks(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .where((m) => (m['baseUrl'] as String?)?.isNotEmpty ?? false)
        .map(
          (m) => LlmFallbackEntry(
            baseUrl: m['baseUrl'] as String,
            model: m['model'] as String?,
            apiKey: m['apiKey'] as String?,
          ),
        )
        .toList();
  } catch (_) {
    return const [];
  }
}

/// 展开重试端点序列（B1 执行模型，长度 ≤ [maxAttempts]）：
///
/// - 无 fallback：[主, 主, 主…] —— 退化为纯同端点指数退避重试。
/// - 有 fallback：[主, 备1, 备2…, 主, 主…] —— 首次失败即切备选
///   （对「服务端挂了」场景同端点立即重试无意义），备选耗尽后
///   剩余额度回到主端点（应对「备家也抖、主已恢复」）。
///
/// 端点字段合成：备选缺省 model/apiKey 继承 [primary]。
List<LlmConfigValues> expandEndpoints(
  LlmConfigValues primary,
  List<LlmFallbackEntry> fallbacks,
  int maxAttempts,
) {
  final merged = fallbacks
      .map(
        (f) => LlmConfigValues(
          baseUrl: f.baseUrl,
          model: f.model ?? primary.model,
          apiKey: f.apiKey ?? primary.apiKey,
        ),
      )
      .toList();
  final sequence = <LlmConfigValues>[primary, ...merged, primary, primary];
  return sequence.take(maxAttempts).toList();
}
