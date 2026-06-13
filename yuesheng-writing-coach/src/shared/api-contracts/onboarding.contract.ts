import type { ApiResponse } from './base';

// ─── 请求类型 ───

export interface OnboardingAnalyzeRequest {
  sessionId: string;
  baseline: {
    genre?: string;
    experience?: string;
    goal?: string;
  };
}

// ─── 响应类型 ───

export interface OnboardingAnalyzeResponse {
  analysis: string;
  strategy: Record<string, unknown>;
}

// ─── API 接口定义 ───

export const OnboardingApi = {
  analyze: {
    channel: 'onboarding:analyze' as const,
    request: {} as OnboardingAnalyzeRequest,
    response: {} as ApiResponse<OnboardingAnalyzeResponse>,
  },
} as const;

export type OnboardingInvokeChannels =
  | typeof OnboardingApi.analyze.channel;
