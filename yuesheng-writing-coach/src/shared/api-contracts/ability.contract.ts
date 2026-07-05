import type { ApiResponse } from './base';
import type {
  AbilityScore,
  WeakPoint,
  TrainingStats,
  DiagnosisTrend,
} from '../types/types-growth';

// ─── 请求类型 ───

export interface AbilityGetProfileRequest {
  sessionId: string;
}

// ─── 响应类型 ───

/** @deprecated 使用 AbilityScore[] 替代 — 保留仅用于兼容旧版引用 */
export interface SyndromesAbility {
  syndromeId: string;
  score: number;
  trend: 'up' | 'down' | 'stable';
  instances: number;
}

export interface AbilityProfile {
  sessionId: string;
  /** @deprecated IPC 实际返回 abilities 而非 syndromes，保留字段避免破坏现有引用 */
  syndromes: SyndromesAbility[];
  /** @deprecated 不再由后端计算 */
  overallScore: number;
  /** @deprecated 不再由后端计算 */
  strengths: string[];
  /** @deprecated 不再由后端计算 */
  weaknesses: string[];
  // ─── 实际返回字段（来自 AbilityProfileService.computeProfile） ───
  abilities: AbilityScore[];
  weakPoints: WeakPoint[];
  trainingStats: TrainingStats;
  diagnosisTrend: DiagnosisTrend;
  computedAt: string;
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
