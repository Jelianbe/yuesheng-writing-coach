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
// ─────────────────────────────────────────────────────────────

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

  /// 从任意异常识别 AppError（非 AppError 返回 null）
  static AppError? from(Object error) {
    if (error is AppError) return error;
    // 部分实现可能用 Error.throwWithStackTrace 包装，剥一层
    return null;
  }
}
