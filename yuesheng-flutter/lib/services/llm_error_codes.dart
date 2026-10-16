// ─────────────────────────────────────────────────────────────
// LLM 错误分类与用户可操作文案 — 批次 3 稳定性
//
// 对齐外来设计《AI小说写作工具_错误处理设计.md》第五章 AI 层错误矩阵
// （NOT_CONFIGURED / TIMEOUT / NETWORK_ERROR / RATE_LIMITED / AI_API_ERROR），
// 适配月笙单账号形态（无用量系统、无多供应商降级，故 COST_LIMIT /
// ALL_UNAVAILABLE 不落地——批次 D 多账号时再扩展）。
//
// 目标：用户看到的不是裸 "HTTP 401"，而是可操作指引
// （Key 无效→去设置检查；429→稍后重试；超时→重试）。
//
// R-027 任务 A：文案本体收敛到 lib/config/svc_copy.dart（L-SVC 单一真源），
// 本函数只做「错误码 → 文案」组合分派；统一收尾「重试」（原 429 文案误写
// 「再试」，随迁移消灭）。
//
// 纯函数、无 IO，全部可单测。取消（DioExceptionType.cancel）不在本层
// 分类——上游 LlmClient 已原样上抛走取消分支。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';

import '../config/svc_copy.dart';

/// LLM 错误分类（DioException → 语义类别）
enum LlmErrorKind {
  /// 请求超时（连接/接收/发送三态）
  timeout,

  /// 网络连接失败（无法连到服务器）
  network,

  /// 401/403：API Key 无效或已过期（含余额不足被服务端拒绝）
  unauthorized,

  /// 429：请求过于频繁（限流）
  rateLimited,

  /// 5xx：服务端异常
  server,

  /// 400：请求不被接受（模型名/参数错误）
  invalidRequest,

  /// 其他 HTTP 状态或未分类错误
  unknown,
}

/// 分类 DioException → [LlmErrorKind]。
///
/// 判定顺序（R-019）：超时/连接类型优先于状态码（Dio 超时类型可能
/// 同时带非空 statusCode）；其余按 HTTP 状态码归类。
LlmErrorKind classifyLlmError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.transformTimeout:
      return LlmErrorKind.timeout;
    case DioExceptionType.connectionError:
      return LlmErrorKind.network;
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      break;
  }
  final status = e.response?.statusCode;
  if (status == 401 || status == 403) return LlmErrorKind.unauthorized;
  if (status == 429) return LlmErrorKind.rateLimited;
  if (status != null && status >= 500) return LlmErrorKind.server;
  if (status == 400) return LlmErrorKind.invalidRequest;
  return LlmErrorKind.unknown;
}

/// 用户可操作文案（单一真源）。
///
/// [status] / [preview]（已脱敏的错误体预览）/ [timeoutSeconds] 由调用方
/// 按需传入——本函数只做文案拼接，不做 IO 与脱敏。
String llmErrorMessage(
  LlmErrorKind kind, {
  int? status,
  String? preview,
  int? timeoutSeconds,
}) {
  switch (kind) {
    case LlmErrorKind.timeout:
      return kLlmTimeoutMessage(timeoutSeconds ?? 60);
    case LlmErrorKind.network:
      return kLlmNetworkMessage;
    case LlmErrorKind.unauthorized:
      return kLlmUnauthorizedMessage;
    case LlmErrorKind.rateLimited:
      return kLlmRateLimitedMessage;
    case LlmErrorKind.server:
      return kLlmServerMessage(status);
    case LlmErrorKind.invalidRequest:
      // W-18 调试增强（2026-10-15）：invalidRequest 的服务端 body 原被吞掉，
      // 400 归因（哪个参数非法）只能靠猜。preview 非空时附上（已在上游脱敏）。
      return preview != null && preview.isNotEmpty
          ? '$kLlmInvalidRequestMessage · 服务端响应：$preview'
          : kLlmInvalidRequestMessage;
    case LlmErrorKind.unknown:
      return preview != null && preview.isNotEmpty
          ? 'HTTP $status: $preview'
          : 'HTTP $status';
  }
}
