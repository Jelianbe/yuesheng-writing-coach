import type { ApiResponse } from './base';

// ─── 教学状态共享类型 ───

export interface TeachingState {
  sessionId: string;
  currentPhase: string | null;
  currentSubphase: string | null;
  activeProblems: Array<{
    syndromeId: string;
    severity: string;
    trained: boolean;
    score?: number;
  }>;
  completedActions: string[];
  nextSuggestedActions: string[];
  diagnosisSummary: string;
  lockedSyndromes: string[];
  createdAt: number;
  updatedAt: number;
}

// ─── 请求类型 ───

export interface TeachingStateGetRequest {
  sessionId: string;
}

export interface TeachingStateUpdateRequest {
  sessionId: string;
  updates: Partial<Pick<
    TeachingState,
    'currentPhase' | 'currentSubphase' | 'activeProblems' | 'completedActions' | 'nextSuggestedActions' | 'diagnosisSummary' | 'lockedSyndromes'
  >>;
}

export interface TeachingStateConfirmRequest {
  sessionId: string;
}

export interface TeachingStateGetPromptRequest {
  sessionId: string;
}

export interface TeachingStateUpdateSummaryRequest {
  sessionId: string;
  newContent: string;
}

// ─── 响应类型 ───

export interface TeachingStateGetResponse extends TeachingState {
  phaseName: string;
  subphaseName: string;
  phaseProgress: number;
}

export interface TeachingStateConfirmResponse {
  oldState: TeachingState;
  newState: TeachingState;
}

export interface TeachingStateGetPromptResponse {
  promptContent: string;
}

// ─── Event 推送类型 ───

export interface TeachingStateUpdatedEvent extends TeachingState {
  phaseName: string;
  subphaseName: string;
  phaseProgress: number;
}

// ─── API 接口定义 ───

export const TeachingStateApi = {
  get: {
    channel: 'teachingState:get' as const,
    request: {} as TeachingStateGetRequest,
    response: {} as ApiResponse<TeachingStateGetResponse>,
  },

  update: {
    channel: 'teachingState:update' as const,
    request: {} as TeachingStateUpdateRequest,
    response: {} as ApiResponse<TeachingState>,
  },

  confirm: {
    channel: 'teachingState:confirm' as const,
    request: {} as TeachingStateConfirmRequest,
    response: {} as ApiResponse<TeachingStateConfirmResponse>,
  },

  getPrompt: {
    channel: 'teachingState:getPrompt' as const,
    request: {} as TeachingStateGetPromptRequest,
    response: {} as ApiResponse<TeachingStateGetPromptResponse>,
  },

  updateSummary: {
    channel: 'teachingState:updateSummary' as const,
    request: {} as TeachingStateUpdateSummaryRequest,
    response: {} as ApiResponse<TeachingState>,
  },

  updated: {
    channel: 'teachingState:updated' as const,
    event: {} as TeachingStateUpdatedEvent,
  },
} as const;

export type TeachingStateInvokeChannels =
  | typeof TeachingStateApi.get.channel
  | typeof TeachingStateApi.update.channel
  | typeof TeachingStateApi.confirm.channel
  | typeof TeachingStateApi.getPrompt.channel
  | typeof TeachingStateApi.updateSummary.channel;

export type TeachingStateEventChannels =
  | typeof TeachingStateApi.updated.channel;
