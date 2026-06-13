import type { ApiResponse } from './base';

// ─── 请求类型 ───

export interface AbilityGetProfileRequest {
  sessionId: string;
}

// ─── 响应类型 ───

export interface SyndromesAbility {
  syndromeId: string;
  score: number;
  trend: 'up' | 'down' | 'stable';
  instances: number;
}

export interface AbilityProfile {
  sessionId: string;
  syndromes: SyndromesAbility[];
  overallScore: number;
  strengths: string[];
  weaknesses: string[];
}

export interface AbilityGetProfileResponse {
  profile: AbilityProfile | null;
}

// ─── API 接口定义 ───

export const AbilityApi = {
  getProfile: {
    channel: 'ability:getProfile' as const,
    request: {} as AbilityGetProfileRequest,
    response: {} as ApiResponse<AbilityGetProfileResponse>,
  },
} as const;

export type AbilityInvokeChannels =
  | typeof AbilityApi.getProfile.channel;
