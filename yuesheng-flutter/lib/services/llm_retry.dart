// ─────────────────────────────────────────────────────────────
// LLM 重试策略 — B1-2 超时重试 + 指数退避（纯逻辑，无 IO）
// 参考：yuesheng-writing-coach sprint-18 LLMGateway retry.ts 设计
//   （指数退避重试，最多 3 次尝试）。
// 独立成文件：llm_client.dart 已是 R-019 存量债务（353 行），
// 复杂逻辑外置，client 只做接线。
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

/// 重试策略（可注入，测试可用抖动=0 的确定性配置）
class LlmRetryPolicy {
  /// 总尝试次数（含首次请求）。3 = 1 次原始 + 2 次重试。
  final int maxAttempts;

  /// 首次重试的退避基数（毫秒）。
  final int baseDelayMs;

  /// 指数因子：第 n 次重试延迟 = base * factor^(n-1)。
  final int factor;

  /// 单次退避封顶（毫秒）；null 不封顶。
  final int? maxDelayMs;

  /// 抖动上限（毫秒）：实际延迟 += random(0, jitter]；0 = 确定性。
  final int jitterMs;

  const LlmRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelayMs = 500,
    this.factor = 2,
    this.maxDelayMs = 4000,
    this.jitterMs = 250,
  });

  /// 生产默认：500ms → 1000ms（封顶 4000），抖动 ±250ms 内。
  static const LlmRetryPolicy standard = LlmRetryPolicy();

  /// 第 [retryIndex] 次重试的延迟（retryIndex 从 1 开始）。
  /// 计算值 = min(maxDelayMs, base * factor^(retryIndex-1)) + jitter。
  int delayMsFor(int retryIndex, {math.Random? random}) {
    final raw = baseDelayMs * math.pow(factor, retryIndex - 1).toInt();
    final capped = (maxDelayMs != null && raw > maxDelayMs!)
        ? maxDelayMs!
        : raw;
    if (jitterMs <= 0) return capped;
    final r = random ?? math.Random();
    return capped + r.nextInt(jitterMs);
  }
}

/// 语义性不可重试（区别于网络层错误分类）。
///
/// 用途：streamChat 已向 UI 输出 token 后的失败必须包装为本异常，
/// 防止重试导致「同一段回答重复输出」。executeWithRetry 见到即终止。
class LlmNonRetryableException implements Exception {
  final Object cause;
  const LlmNonRetryableException(this.cause);

  @override
  String toString() => 'LlmNonRetryableException: $cause';
}

/// Dio 错误是否可重试（网络层分类）：
/// - 可重试：超时 / 连接失败 / HTTP 5xx / 429 限流
/// - 不可重试：4xx 参数鉴权错 / 用户取消 / 其他未知
bool isRetryableDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
      return true;
    case DioExceptionType.badResponse:
      final status = e.response?.statusCode ?? 0;
      return status >= 500 || status == 429;
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return false;
  }
}

/// 带重试的统一执行器。
///
/// - [attempt] 收到 1 起始的尝试序号（用于 fallback 端点轮换）。
/// - 可重试：Dio 层错误（见 [isRetryableDioError]）与 [TimeoutException]
///   （流式零 token 断流/首字超时，由 guardStream 抛出）；
///   [LlmNonRetryableException] 与其他错误立即抛出（不可重试）。
/// - 全部尝试耗尽 → 抛最后一次的错误（不吞错，调用方可转用户消息）。
/// - [sleep] 可注入（测试记录退避序列不真等）；默认 Future.delayed。
/// - [onRetry] 每次重试前回调（attempt 序号 / 延迟 / 上次错误），留观测钩子。
Future<T> executeWithRetry<T>(
  Future<T> Function(int attemptIndex) attempt, {
  LlmRetryPolicy policy = LlmRetryPolicy.standard,
  Future<void> Function(Duration delay)? sleep,
  void Function(int attemptIndex, Duration delay, Object error)? onRetry,
}) async {
  final doSleep = sleep ?? (d) => Future<void>.delayed(d);
  assert(policy.maxAttempts >= 1, 'maxAttempts 必须 >= 1');

  var lastError = Object();
  for (var i = 1; i <= policy.maxAttempts; i++) {
    try {
      return await attempt(i);
    } on LlmNonRetryableException {
      rethrow;
    } catch (e) {
      lastError = e;
      final isLast = i >= policy.maxAttempts;
      if (isLast || !_isRetryableError(e)) {
        rethrow;
      }
      final delayMs = policy.delayMsFor(i);
      onRetry?.call(i + 1, Duration(milliseconds: delayMs), e);
      await doSleep(Duration(milliseconds: delayMs));
    }
  }
  // 不可达（循环要么 return 要么 rethrow），保险兜底。
  throw lastError;
}

/// 统一可重试判定：Dio 网络层分类 + 流式超时（guardStream 的
/// TimeoutException——streamChat 仅在零 token 阶段放它到这里，
/// 已输出 token 的失败已由调用方包装为 LlmNonRetryableException）。
bool _isRetryableError(Object e) {
  if (e is DioException) return isRetryableDioError(e);
  if (e is TimeoutException) return true;
  return false;
}
