// ─── API Contract 基础类型 ───
// 所有域级 Contract 扩展此模块

/** 成功响应包装 */
export interface ApiSuccess<T> {
  success: true;
  data: T;
}

/** 错误响应包装 */
export interface ApiError {
  success: false;
  error: string;
  /** 可读的错误消息（可选，生产不暴露 stack） */
  message?: string;
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
