// 配置与 API 基础类型

/** 态度档位类型（三态：温柔/月笙/尖锐） */
export type AttitudeLevel = 'doubao' | 'yuesheng' | 'sensei';

/** API 配置数据 */
export interface ApiConfig {
  /** OpenAI 兼容 API 密钥 */
  apiKey: string;
  /** API 基础 URL */
  baseUrl: string;
  /** 模型名称 */
  modelName: string;
  /** 温度参数 (0-2) */
  temperature: number;
  /** 态度档位 */
  attitudeLevel: AttitudeLevel;
  /** 聊天流输出最大 token 数（默认 8192） */
  maxTokens: number;
}

/**
 * 统一 IPC 响应格式（ER5）
 * 所有 handler 统一使用此格式返回，确保渲染进程可用统一方式处理错误
 */
export interface ApiResponse<T = unknown> {
  /** 操作是否成功 */
  success: boolean;
  /** 成功时返回的数据 */
  data?: T;
  /** 失败时的错误信息 */
  error?: string;
}

/** 创建成功响应 */
export function apiSuccess<T>(data: T): ApiResponse<T> {
  return { success: true, data };
}

/** 创建错误响应 */
export function apiError(error: string): ApiResponse<never> {
  return { success: false, error };
}

/** API 配置校验结果 */
export interface ApiConfigValidation {
  /** 是否通过校验 */
  isValid: boolean;
  /** 校验错误消息（仅当 isValid=false 时存在） */
  errors: string[];
}

/** 连接测试结果 */
export interface ConnectionTestResult {
  /** 测试是否成功 */
  success: boolean;
  /** 错误消息（仅当 success=false 时存在） */
  error?: string;
  /** 响应时间（毫秒） */
  responseTime?: number;
}
