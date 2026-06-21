import type { ApiResponse } from './base';
import type { ActiveProblem } from '../types/types-teaching';

// ─── 诊断域共享类型 ───

export type SeverityLevel = 'critical' | 'high' | 'medium' | 'low' | 'none';

export interface SyndromeResult {
  syndromeId: string;
  severity: SeverityLevel;
  description: string;
  evidence: string;
}

export interface DiagnosisEntry {
  id: string;
  sessionId: string;
  syndromes: SyndromeResult[];
  summary: string;
  createdAt: number;
}

// ─── 请求类型 ───

export interface DiagnosisUpdateRequest {
  sessionId: string;
  syndromes: Array<{
    syndromeId: string;
    severity: SeverityLevel;
    description: string;
    evidence: string;
  }>;
  summary: string;
}

export interface DiagnosisQueryRequest {
  sessionId: string;
  limit?: number;
  offset?: number;
}

export interface DiagnosisSubmitRewriteRequest {
  sessionId: string;
  syndromeId: string;
  originalText: string;
  rewrittenText: string;
}

export interface DiagnosisGetComparisonRequest {
  sessionId: string;
  syndromeId: string;
}

// ─── 响应类型 ───

export interface DiagnosisUpdateResponse {
  entry: DiagnosisEntry;
  mergedToTeaching: boolean;
}

export type DiagnosisQueryResponse = ActiveProblem[];

export interface DiagnosisRewriteEvaluation {
  score: number;
  feedback: string;
  improved: boolean;
  severityAfterUpdate: Record<string, SeverityLevel>;
}

export interface DiagnosisComparisonResult {
  originalText: string;
  rewrites: Array<{
    rewrittenText: string;
    score: number;
    feedback: string;
    timestamp: number;
  }>;
}

// ─── Event 推送类型 ───

export interface DiagnosisUpdateEvent {
  sessionId: string;
  entry: DiagnosisEntry;
}

// ─── API 接口定义 ───

export const DiagnosisApi = {
  update: {
    channel: 'diagnosis:update' as const,
    request: {} as DiagnosisUpdateRequest,
    response: {} as DiagnosisUpdateResponse,
  },

  query: {
    channel: 'diagnosis:query' as const,
    request: {} as DiagnosisQueryRequest,
    response: {} as ApiResponse<DiagnosisQueryResponse>,
  },

  submitRewrite: {
    channel: 'diagnosis:submitRewrite' as const,
    request: {} as DiagnosisSubmitRewriteRequest,
    response: {} as ApiResponse<DiagnosisRewriteEvaluation>,
  },

  getComparison: {
    channel: 'diagnosis:getComparison' as const,
    request: {} as DiagnosisGetComparisonRequest,
    response: {} as DiagnosisComparisonResult,
  },

  updated: {
    channel: 'diagnosis:updated' as const,
    event: {} as DiagnosisUpdateEvent,
  },
} as const;

export type DiagnosisInvokeChannels =
  | typeof DiagnosisApi.update.channel
  | typeof DiagnosisApi.query.channel
  | typeof DiagnosisApi.submitRewrite.channel
  | typeof DiagnosisApi.getComparison.channel;

export type DiagnosisEventChannels =
  | typeof DiagnosisApi.updated.channel;
