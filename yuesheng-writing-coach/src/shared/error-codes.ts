/**
 * 错误码体系 — 前端/主进程共享
 *
 * 标准化错误码 + 中文错误消息映射（R-029 安全：不暴露内部技术细节）
 *
 * 设计原则：
 * 1. 所有用户可见消息使用中文
 * 2. 不暴露内部技术细节（堆栈、API Key、模块路径等）
 * 3. 提供分类错误码供 UI 按类型展示
 */

/** 错误分类 */
export const ErrorCategory = {
  NETWORK: 'NETWORK',
  TIMEOUT: 'TIMEOUT',
  AUTH: 'AUTH',
  PROMPT: 'PROMPT',
  STREAM: 'STREAM',
  STATE: 'STATE',
  VALIDATION: 'VALIDATION',
  UNKNOWN: 'UNKNOWN',
} as const;

export type ErrorCategory = (typeof ErrorCategory)[keyof typeof ErrorCategory];

/** 错误码 */
export const ErrorCode = {
  // — 网络类 —
  NETWORK_DISCONNECTED: 'ERR_NETWORK_DISCONNECTED',
  NETWORK_TIMEOUT: 'ERR_NETWORK_TIMEOUT',
  API_UNAUTHORIZED: 'ERR_API_UNAUTHORIZED',
  API_RATE_LIMIT: 'ERR_API_RATE_LIMIT',

  // — 超时类 —
  STREAM_TIMEOUT: 'ERR_STREAM_TIMEOUT',
  REQUEST_TIMEOUT: 'ERR_REQUEST_TIMEOUT',

  // — Prompt 类 —
  PROMPT_LOAD_FAILED: 'ERR_PROMPT_LOAD_FAILED',
  PROMPT_GENERATION_FAILED: 'ERR_PROMPT_GENERATION_FAILED',

  // — 流式类 —
  STREAM_INTERRUPTED: 'ERR_STREAM_INTERRUPTED',
  STREAM_PARSE_FAILED: 'ERR_STREAM_PARSE_FAILED',

  // — 状态类 —
  STATE_TRANSITION_INVALID: 'ERR_STATE_TRANSITION_INVALID',
  STATE_NOT_FOUND: 'ERR_STATE_NOT_FOUND',
  STATE_PERSISTENCE_FAILED: 'ERR_STATE_PERSISTENCE_FAILED',

  // — 验证类 —
  SESSION_MISSING: 'ERR_SESSION_MISSING',
  INPUT_INVALID: 'ERR_INPUT_INVALID',

  // — 未知 —
  UNKNOWN: 'ERR_UNKNOWN',
} as const;

export type ErrorCode = (typeof ErrorCode)[keyof typeof ErrorCode];

/** 错误码 → 分类映射 */
export const ERROR_CATEGORY: Record<ErrorCode, ErrorCategory> = {
  [ErrorCode.NETWORK_DISCONNECTED]: ErrorCategory.NETWORK,
  [ErrorCode.NETWORK_TIMEOUT]: ErrorCategory.NETWORK,
  [ErrorCode.API_UNAUTHORIZED]: ErrorCategory.AUTH,
  [ErrorCode.API_RATE_LIMIT]: ErrorCategory.NETWORK,
  [ErrorCode.STREAM_TIMEOUT]: ErrorCategory.TIMEOUT,
  [ErrorCode.REQUEST_TIMEOUT]: ErrorCategory.TIMEOUT,
  [ErrorCode.PROMPT_LOAD_FAILED]: ErrorCategory.PROMPT,
  [ErrorCode.PROMPT_GENERATION_FAILED]: ErrorCategory.PROMPT,
  [ErrorCode.STREAM_INTERRUPTED]: ErrorCategory.STREAM,
  [ErrorCode.STREAM_PARSE_FAILED]: ErrorCategory.STREAM,
  [ErrorCode.STATE_TRANSITION_INVALID]: ErrorCategory.STATE,
  [ErrorCode.STATE_NOT_FOUND]: ErrorCategory.STATE,
  [ErrorCode.STATE_PERSISTENCE_FAILED]: ErrorCategory.STATE,
  [ErrorCode.SESSION_MISSING]: ErrorCategory.VALIDATION,
  [ErrorCode.INPUT_INVALID]: ErrorCategory.VALIDATION,
  [ErrorCode.UNKNOWN]: ErrorCategory.UNKNOWN,
};

/**
 * 中文错误消息映射
 *
 * 所有消息：
 * - 使用中文，清晰可理解
 * - 不暴露技术细节（堆栈、路径、Key 等）
 * - 提供可操作的建议（重试、检查网络、联系支持）
 */
export const ERROR_MESSAGES: Record<ErrorCode, string> = {
  // — 网络类 —
  [ErrorCode.NETWORK_DISCONNECTED]: '网络连接异常，请检查网络后重试。',
  [ErrorCode.NETWORK_TIMEOUT]: '网络请求超时，请检查网络连接后重试。',
  [ErrorCode.API_UNAUTHORIZED]: 'API 认证失败，请在设置中检查 API Key 是否正确。',
  [ErrorCode.API_RATE_LIMIT]: '请求过于频繁，请稍后再试。',

  // — 超时类 —
  [ErrorCode.STREAM_TIMEOUT]: 'AI 回复超时，请重试。',
  [ErrorCode.REQUEST_TIMEOUT]: '请求超时，请重试。',

  // — Prompt 类 —
  [ErrorCode.PROMPT_LOAD_FAILED]: '加载教学模板失败，请重试。',
  [ErrorCode.PROMPT_GENERATION_FAILED]: 'AI 生成回复失败，请重试。',

  // — 流式类 —
  [ErrorCode.STREAM_INTERRUPTED]: '回复被中断，请重试。',
  [ErrorCode.STREAM_PARSE_FAILED]: 'AI 回复格式异常，请重试。',

  // — 状态类 —
  [ErrorCode.STATE_TRANSITION_INVALID]: '教学状态异常，已自动恢复到安全状态。',
  [ErrorCode.STATE_NOT_FOUND]: '未找到教学状态，已重新初始化。',
  [ErrorCode.STATE_PERSISTENCE_FAILED]: '保存教学状态失败，请重试。',

  // — 验证类 —
  [ErrorCode.SESSION_MISSING]: '会话已过期，请刷新页面。',
  [ErrorCode.INPUT_INVALID]: '输入内容无效，请检查后重新提交。',

  // — 未知 —
  [ErrorCode.UNKNOWN]: '发生未知错误，请重试。如果问题持续，请联系支持。',
};

/** 错误码 → 是否可重试 */
export const ERROR_RETRYABLE: ReadonlySet<ErrorCode> = new Set([
  ErrorCode.NETWORK_DISCONNECTED,
  ErrorCode.NETWORK_TIMEOUT,
  ErrorCode.STREAM_TIMEOUT,
  ErrorCode.REQUEST_TIMEOUT,
  ErrorCode.PROMPT_LOAD_FAILED,
  ErrorCode.PROMPT_GENERATION_FAILED,
  ErrorCode.STREAM_INTERRUPTED,
  ErrorCode.UNKNOWN,
]);

/** 错误码 → 是否建议降级 */
export const ERROR_DEGRADE: ReadonlySet<ErrorCode> = new Set([
  ErrorCode.STREAM_TIMEOUT,
  ErrorCode.STREAM_INTERRUPTED,
  ErrorCode.PROMPT_GENERATION_FAILED,
]);

/**
 * 从原生 Error 猜测错误码
 */
export function inferErrorCode(error: unknown): ErrorCode {
  if (!error) return ErrorCode.UNKNOWN;

  const message = error instanceof Error ? error.message.toLowerCase() : String(error).toLowerCase();

  if (message.includes('abort') || message.includes('aborted')) return ErrorCode.STREAM_INTERRUPTED;
  if (message.includes('timeout') || message.includes('timed out')) return ErrorCode.NETWORK_TIMEOUT;
  if (message.includes('network') || message.includes('fetch') || message.includes('enotfound') || message.includes('econnrefused')) {
    return ErrorCode.NETWORK_DISCONNECTED;
  }
  if (message.includes('unauthorized') || message.includes('401') || message.includes('apikey') || message.includes('auth')) {
    return ErrorCode.API_UNAUTHORIZED;
  }
  if (message.includes('rate limit') || message.includes('429')) return ErrorCode.API_RATE_LIMIT;
  if (message.includes('session') || message.includes('sessionid')) return ErrorCode.SESSION_MISSING;
  if (message.includes('prompt') || message.includes('template')) return ErrorCode.PROMPT_LOAD_FAILED;
  if (message.includes('parse') || message.includes('format')) return ErrorCode.STREAM_PARSE_FAILED;
  if (message.includes('transition') || message.includes('invalid state')) return ErrorCode.STATE_TRANSITION_INVALID;

  return ErrorCode.UNKNOWN;
}

/**
 * 获得用户可见的中文错误消息
 */
export function getUserFacingErrorMessage(error: unknown): string {
  if (typeof error === 'string' && Object.values(ErrorCode).includes(error as ErrorCode)) {
    return ERROR_MESSAGES[error as ErrorCode] ?? ERROR_MESSAGES[ErrorCode.UNKNOWN];
  }

  const code = inferErrorCode(error);
  return ERROR_MESSAGES[code] ?? ERROR_MESSAGES[ErrorCode.UNKNOWN];
}

/**
 * 判断错误是否可重试
 */
export function isRetryable(error: unknown): boolean {
  const code = typeof error === 'string' && Object.values(ErrorCode).includes(error as ErrorCode)
    ? error as ErrorCode
    : inferErrorCode(error);
  return ERROR_RETRYABLE.has(code);
}

/**
 * 判断错误是否建议降级模式
 */
export function shouldDegrade(error: unknown): boolean {
  const code = typeof error === 'string' && Object.values(ErrorCode).includes(error as ErrorCode)
    ? error as ErrorCode
    : inferErrorCode(error);
  return ERROR_DEGRADE.has(code);
}
