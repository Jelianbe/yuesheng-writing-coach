// ─────────────────────────────────────────────────────────────
// llm_circuit_breaker — LLM 请求熔断器（入档批次：LLM 熔断器）
//
// 对齐外来《AI小说写作工具_错误处理设计.md》熔断思路，适配月笙
// 单供应商形态：连续失败开路后「快速失败」+ 冷却自动恢复，
// **不切供应商**（无多供应商降级链，批次 D-2 冻结）。
//
// 状态机（简单三态，无 half-open 试探——单用户场景保持简单）：
//   closed（正常）→ 连续失败达阈值 → open（熔断 N 秒，快速失败）
//   → 冷却到期自动复位 closed（下次请求直接重试真实链路）
//
// 计数规则：只计「可恢复错误」（timeout / network / rateLimited /
// server）——401/400 等配置类错误重试也不会恢复，计数会掩盖
// 「用户 key 失效」的真实问题，故不计数。
//
// 取消（cancel）不计数：用户主动取消不是服务故障。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';

import 'llm_error_codes.dart';

/// 熔断开路异常（LlmClient 入口抛给调用方，UI 转用户可读提示）
class LlmCircuitOpenException implements Exception {
  final Duration remaining;

  const LlmCircuitOpenException(this.remaining);

  @override
  String toString() => '服务暂时不可用（连续失败熔断），${remaining.inSeconds} 秒后自动恢复';
}

/// LLM 请求熔断器（纯状态机，无 IO，可独立测试）
class LlmCircuitBreaker {
  /// 连续失败阈值：达到即开路
  final int failureThreshold;

  /// 开路冷却时长：到期自动复位
  final Duration cooldown;

  int _consecutiveFailures = 0;
  bool _open = false;
  DateTime? _openedAt;

  LlmCircuitBreaker({
    this.failureThreshold = 3,
    this.cooldown = const Duration(seconds: 30),
  });

  /// 是否处于熔断状态（冷却到期自动复位为关闭）
  bool get isOpen {
    if (!_open) return false;
    final openedAt = _openedAt;
    if (openedAt == null) return false;
    if (DateTime.now().difference(openedAt) >= cooldown) {
      _reset();
      return false;
    }
    return true;
  }

  /// 剩余冷却时长（未熔断返回 [Duration.zero]）
  Duration get remaining {
    final openedAt = _openedAt;
    if (!_open || openedAt == null) return Duration.zero;
    final left = cooldown - DateTime.now().difference(openedAt);
    return left.isNegative ? Duration.zero : left;
  }

  /// 请求成功：复位计数与状态
  void onSuccess() => _reset();

  /// 请求失败（可恢复类）：累计计数，达到阈值开路
  void onFailure() {
    if (_open) return; // 已开路不再累计，等待冷却复位
    _consecutiveFailures++;
    if (_consecutiveFailures >= failureThreshold) {
      _open = true;
      _openedAt = DateTime.now();
    }
  }

  /// 判定 Dio 错误是否应计入熔断（可恢复类才计数）
  static bool shouldCount(DioException e) {
    switch (classifyLlmError(e)) {
      case LlmErrorKind.timeout:
      case LlmErrorKind.network:
      case LlmErrorKind.rateLimited:
      case LlmErrorKind.server:
        return true;
      case LlmErrorKind.unauthorized:
      case LlmErrorKind.invalidRequest:
      case LlmErrorKind.unknown:
        return false;
    }
  }

  void _reset() {
    _open = false;
    _consecutiveFailures = 0;
    _openedAt = null;
  }
}
