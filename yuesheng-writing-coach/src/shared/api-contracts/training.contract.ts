import type { ApiResponse } from './base';
import type { TrainingRecord } from '../types/types-training';

// ─── 请求类型 ───

export interface TrainingRecommendRequest {
  sessionId: string;
  focusArea?: string;
  count?: number;
}

export interface TrainingAssignRequest {
  sessionId: string;
  challengeId: string;
}

export interface TrainingCompleteRequest {
  recordId: string;
  userResponse: string;
  aiFeedback?: string;
  effectiveness?: number;
}

export interface TrainingSkipRequest {
  sessionId: string;
  recordId: string;
  reason?: string;
}

export interface TrainingHistoryRequest {
  sessionId: string;
  syndromeId?: string;
  limit?: number;
}

export interface TrainingSubmitRequest {
  sessionId: string;
  recordId: string;
  text: string;
}

export interface TrainingEvaluateRequest {
  sessionId: string;
  recordId: string;
  syndromeId: string;
  text: string;
  trainingType: string;
}

export interface TrainingDeriveBehaviorRequest {
  sessionId: string;
  text: string;
}

// ─── 响应类型 ───

export interface TrainingRecommendResponse {
  tasks: Array<{
    templateId: string;
    title: string;
    description: string;
    syndromeId: string;
  }>;
}

export interface TrainingAssignResponse {
  record: TrainingRecord;
}

export interface TrainingCompleteResponse {
  record: TrainingRecord;
}

export interface TrainingHistoryResponse {
  records: Array<{
    recordId: string;
    syndromeId: string;
    title: string;
    score?: number;
    completedAt?: number;
  }>;
}

export interface TrainingSubmitResponse {
  recordId: string;
}

export interface TrainingEvaluateResponse {
  score: number;
  feedback: string;
  downgraded: boolean;
}

import type { AttitudeLevel } from '../types/types-config';

export interface TrainingDecideReadingRequest {
  attitude: AttitudeLevel;
}

export interface TrainingDecideReadingResponse {
  required: boolean;
  recommended: boolean;
  label: string;
  reason?: string;
}

export interface TrainingDeriveBehaviorResponse {
  behaviors: string[];
}

// ─── API 接口定义 ───

export const TrainingApi = {
  recommend: {
    channel: 'training:recommend' as const,
    request: {} as TrainingRecommendRequest,
    response: {} as ApiResponse<TrainingRecommendResponse>,
  },

  assign: {
    channel: 'training:assign' as const,
    request: {} as TrainingAssignRequest,
    response: {} as ApiResponse<TrainingAssignResponse>,
  },

  complete: {
    channel: 'training:complete' as const,
    request: {} as TrainingCompleteRequest,
    response: {} as ApiResponse<TrainingCompleteResponse>,
  },

  skip: {
    channel: 'training:skip' as const,
    request: {} as TrainingSkipRequest,
    response: {} as ApiResponse<TrainingCompleteResponse>,
  },

  history: {
    channel: 'training:history' as const,
    request: {} as TrainingHistoryRequest,
    response: {} as ApiResponse<TrainingHistoryResponse>,
  },

  submit: {
    channel: 'training:submit' as const,
    request: {} as TrainingSubmitRequest,
    response: {} as ApiResponse<TrainingSubmitResponse>,
  },

  evaluate: {
    channel: 'training:evaluate' as const,
    request: {} as TrainingEvaluateRequest,
    response: {} as ApiResponse<TrainingEvaluateResponse>,
  },

  decideReading: {
    channel: 'training:decideReading' as const,
    request: {} as TrainingDecideReadingRequest,
    response: {} as ApiResponse<TrainingDecideReadingResponse>,
  },

  deriveBehavior: {
    channel: 'training:deriveBehavior' as const,
    request: {} as TrainingDeriveBehaviorRequest,
    response: {} as ApiResponse<TrainingDeriveBehaviorResponse>,
  },
} as const;

export type TrainingInvokeChannels =
  | typeof TrainingApi.recommend.channel
  | typeof TrainingApi.assign.channel
  | typeof TrainingApi.complete.channel
  | typeof TrainingApi.skip.channel
  | typeof TrainingApi.history.channel
  | typeof TrainingApi.submit.channel
  | typeof TrainingApi.evaluate.channel
  | typeof TrainingApi.decideReading.channel
  | typeof TrainingApi.deriveBehavior.channel;
