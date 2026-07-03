// ─── 学生上下文域 Contract(Sprint 21 E-2 引入)───
//
// 背景:StudentContext 包含学生认知画像(信心/挫折计数/学习风格等),
// 属于 R-029 保护范围的敏感数据。E-1 白名单已为 student-context 配置
// 字段级脱敏动作(studentName mask / email redact / phone redact),
// 本 contract 标注 sensitiveFields 与白名单字段名一一对应,实现
// typecheck 时类型安全 + 启动时白名单覆盖校验。
//
// 通道:studentContext:load / studentContext:save / studentContext:toJSON
// 主进程:src/main/core/student-context.service.ts(consumer)

import type { ApiResponse } from './base';

/** 学生上下文(主进程返回) */
export interface StudentContextData {
  /** 学生姓名(mask:中间字符变 *) */
  studentName: string;
  /** 邮箱(redact:[REDACTED]) */
  email: string;
  /** 电话(redact:[REDACTED]) */
  phone: string;
  /** 认知画像(本 Sprint 不脱敏,S22 候选) */
  cognitiveProfile?: {
    learningStyle: string;
    confidenceLevel: number;
    frustrationCount: number;
  };
  /** 其他元数据(可扩展) */
  [key: string]: unknown;
}

/** 学生上下文持久化格式(JSON) */
export interface StudentContextJson {
  text: string;
}

// ─── 请求类型 ───

export interface StudentContextLoadRequest {
  sessionId?: string;
}

export interface StudentContextSaveRequest {
  sessionId?: string;
  data: StudentContextData;
}

export type StudentContextToJsonRequest = Record<string, never>;

// ─── 响应类型 ───

export interface StudentContextLoadResponse {
  context: StudentContextData | null;
  loaded: boolean;
}

export interface StudentContextSaveResponse {
  saved: boolean;
  savedAt: number;
}

export interface StudentContextToJsonResponse {
  text: string;
}

// ─── API 接口定义 ───

export const StudentContextApi = {
  load: {
    channel: 'studentContext:load' as const,
    request: {} as StudentContextLoadRequest,
    response: {
      success: true,
      data: {} as StudentContextLoadResponse,
      sensitiveFields: ['studentName', 'email', 'phone'] as const,
    } as ApiResponse<StudentContextLoadResponse>,
  },

  save: {
    channel: 'studentContext:save' as const,
    request: {} as StudentContextSaveRequest,
    response: {
      success: true,
      data: {} as StudentContextSaveResponse,
      sensitiveFields: ['studentName', 'email', 'phone'] as const,
    } as ApiResponse<StudentContextSaveResponse>,
  },

  toJSON: {
    channel: 'studentContext:toJSON' as const,
    request: {} as StudentContextToJsonRequest,
    response: {
      success: true,
      data: {} as StudentContextToJsonResponse,
      sensitiveFields: ['studentName', 'email', 'phone'] as const,
    } as ApiResponse<StudentContextToJsonResponse>,
  },
} as const;

export type StudentContextInvokeChannels =
  | typeof StudentContextApi.load.channel
  | typeof StudentContextApi.save.channel
  | typeof StudentContextApi.toJSON.channel;
