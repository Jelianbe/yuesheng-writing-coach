// ─── API Contract 基础类型 ───
// 所有域级 Contract 扩展此模块

/** 成功响应包装 */
export interface ApiSuccess<T> {
  success: true;
  data: T;
  /**
   * 该 contract 响应中包含的敏感字段路径(相对 data 字段的 dot-path)
   * 用于 PayloadSanitizer 启动时校验白名单覆盖,阶段 1 为可选,
   * Sprint 22 收尾时改必填(R-029 安全底线)。
   *
   * 字段路径示例:`['originalText', 'evaluation.feedback', 'activeProblems.evidence']`
   * 字段名需与 resources/config/payload-sanitize-whitelist.json 中
   * 对应 service 的 fields 键名完全一致。
   */
  sensitiveFields?: ReadonlyArray<string>;
}

/** 错误响应包装 */
export interface ApiError {
  success: false;
  error: string;
  /** 可读的错误消息（可选，生产不暴露 stack） */
  message?: string;
  /** 错误响应也可能含敏感字段(例如后端 trace 中夹带用户输入) */
  sensitiveFields?: ReadonlyArray<string>;
}

/** 判别式联合响应类型 */
export type ApiResponse<T> = ApiSuccess<T> | ApiError;

/** API 端点元类型 — 每个域 Contract 的每个端点扩展此类型 */
export interface ApiEndpoint<TRequest, TResponse> {
  readonly channel: string;
  readonly request: TRequest;
  readonly response: ApiResponse<TResponse>;
}

/** 事件通道元类型 */
export interface ApiEvent<TEvent> {
  readonly channel: string;
  readonly event: TEvent;
}
