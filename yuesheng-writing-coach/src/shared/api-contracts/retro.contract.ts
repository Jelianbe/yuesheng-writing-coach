import type { ApiResponse } from './base';

// ─── 请求类型 ───

export interface RetroGenerateRequest {
  sessionId: string;
}

export interface RetroSaveRequest {
  sessionId: string;
  summary: string;
  masteredSyndromes: string[];
  improvementScore: number;
}

// ─── 响应类型 ───

export interface RetroSummarySyndrome {
  syndromeId: string;
  syndromeName: string;
  trainingCount: number;
  initialScore: number | null;
  currentScore: number | null;
  improvement: number | null;
  mastered: boolean;
}

export interface RetroGenerateResponse {
  totalTrainingCount: number;
  syndromeCount: number;
  syndromeSummaries: RetroSummarySyndrome[];
  overallImprovement: number;
  masteredTechniques: string[];
  recommendedFocus: string[];
  summary: string;
}

export interface RetroSaveResponse {
  saved: boolean;
}

// ─── API 接口定义 ───

export const RetroApi = {
  generate: {
    channel: 'retro:generate' as const,
    request: {} as RetroGenerateRequest,
    response: {} as ApiResponse<RetroGenerateResponse>,
  },

  save: {
    channel: 'retro:save' as const,
    request: {} as RetroSaveRequest,
    response: {} as ApiResponse<RetroSaveResponse>,
  },
} as const;

export type RetroInvokeChannels =
  | typeof RetroApi.generate.channel
  | typeof RetroApi.save.channel;
