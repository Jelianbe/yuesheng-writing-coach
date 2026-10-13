// ─────────────────────────────────────────────────────────────
// app_error — 业务错误统一基类（入档批次：AppError 业务错误基类）
//
// 对齐外来《AI小说写作工具_错误处理设计.md》AppError(code, message) 模型，
// 适配 Flutter + Riverpod 形态：
//   - AppErrorCode：业务错误码枚举（通用层，不覆盖 LLM 专属分类——
//     LLM 层继续走 llm_error_codes.dart 的 LlmErrorKind + 用户文案）
//   - AppError：结构化业务异常（code + message + 可选 cause/stack）
//
// 设计约束：
//   - 不强制替换现有自定义 Exception（LastAccountException /
//     LlmRequestCancelledException / LlmNonRetryableException /
//     ProgressiveDiagnosisCancelled 保持兼容），新业务路径用 AppError；
//   - 文案不进基类（message 由调用方给），避免复制 llmErrorCodes 的
//     文案映射职责；UI 展示文案由各调用方决定；
//   - captureError 可识别 AppError：Observer / 钩子层提取 code 入 context。
//   - R-027 任务 A：新增 [toUserMessage] 作为「内部错误 → 用户可见文案」
//     唯一通道——按 code 走 lib/config/svc_copy.dart 单一真源，不外露
//     [message]（调用方给的内部详情，可能含堆栈/对象），防内部信息泄漏。
// ─────────────────────────────────────────────────────────────

import '../config/svc_copy.dart';

/// 业务错误码（通用层）
enum AppErrorCode {
  /// 参数非法（如章节超 100KB）
  invalidParams,

  /// 资源不存在（如会话/稿件被删除后仍被引用）
  notFound,

  /// 认证/授权失败（如 API Key 无效）
  auth,

  /// 网络不可达
  network,

  /// 请求超时
  timeout,

  /// 限流（请求过于频繁）
  rateLimited,

  /// 服务端错误
  server,

  /// 数据库错误（读/写/迁移失败）
  database,

  /// 业务校验失败（如标题为空、重复提交）
  validation,

  /// 操作被取消
  cancelled,

  /// 未分类的内部错误
  internal,
}

/// 结构化业务异常（可被全局拦截层识别并提取 code）
class AppError implements Exception {
  final AppErrorCode code;
  final String message;

  /// 底层原因（原异常），保留诊断上下文
  final Object? cause;

  /// 底层堆栈
  final StackTrace? stackTrace;

  const AppError(this.code, this.message, {this.cause, this.stackTrace});

  @override
  String toString() => 'AppError(${code.name}): $message';

  /// 用户可见文案（R-027 任务 A：内部错误 → 用户可操作指引的唯一通道）。
  ///
  /// 只按 [code] 映射 svc_copy 单一真源；[message]（内部详情）不直接外露。
  /// 与 LLM 层分工：HTTP/超时语义映射走 llm_error_codes.dart 的
  /// llmErrorMessage，本函数覆盖业务层 AppErrorCode 通用族。
  /// [AppErrorCode.cancelled] 为用户主动取消（预期行为），返回空串——
  /// 调用方应自行决定是否给提示（通常不给）。
  String toUserMessage() => switch (code) {
    AppErrorCode.network => kLlmNetworkMessage,
    AppErrorCode.timeout => kOperationFailed('操作'),
    AppErrorCode.rateLimited => kLlmRateLimitedMessage,
    AppErrorCode.server => kOperationFailed('服务'),
    AppErrorCode.auth => kLlmUnauthorizedMessage,
    AppErrorCode.invalidParams => kOperationFailed('操作'),
    AppErrorCode.notFound => kOperationFailed('内容加载'),
    AppErrorCode.database => kOperationFailed('数据读写'),
    AppErrorCode.validation => kOperationFailed('提交'),
    AppErrorCode.internal => kOperationFailed('操作'),
    AppErrorCode.cancelled => '',
  };

  /// 从任意异常识别 AppError（非 AppError 返回 null）
  static AppError? from(Object error) {
    if (error is AppError) return error;
    // 部分实现可能用 Error.throwWithStackTrace 包装，剥一层
    return null;
  }
}
