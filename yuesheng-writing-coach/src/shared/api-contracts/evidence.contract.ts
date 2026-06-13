import type { ApiResponse } from './base';

// ─── 请求类型 ───

export interface EvidenceGetBySyndromeRequest {
  syndromeId: string;
  sessionId?: string;
  limit?: number;
}

export interface EvidenceGetByDiseaseRequest {
  diseaseId: string;
  sessionId?: string;
}

export interface EvidenceGetByAbilityRequest {
  abilityId: string;
  sessionId?: string;
}

export interface EvidenceGetChainRequest {
  syndromeId: string;
}

export interface EvidenceCreateRequest {
  sessionId: string;
  text: string;
  category: string;
  syndromeId?: string;
}

// ─── 响应类型 ───

export interface EvidenceRecord {
  id: string;
  sessionId: string;
  text: string;
  category: string;
  syndromeId?: string;
  createdAt: number;
}

export interface EvidenceGetResponse {
  records: EvidenceRecord[];
}

export interface EvidenceGetChainResponse {
  chain: EvidenceRecord[];
}

export interface EvidenceCreateResponse {
  record: EvidenceRecord;
}

// ─── API 接口定义 ───

export const EvidenceApi = {
  getBySyndrome: {
    channel: 'evidence:getBySyndrome' as const,
    request: {} as EvidenceGetBySyndromeRequest,
    response: {} as ApiResponse<EvidenceGetResponse>,
  },

  getByDisease: {
    channel: 'evidence:getByDisease' as const,
    request: {} as EvidenceGetByDiseaseRequest,
    response: {} as ApiResponse<EvidenceGetResponse>,
  },

  getByAbility: {
    channel: 'evidence:getByAbility' as const,
    request: {} as EvidenceGetByAbilityRequest,
    response: {} as ApiResponse<EvidenceGetResponse>,
  },

  getChain: {
    channel: 'evidence:getChain' as const,
    request: {} as EvidenceGetChainRequest,
    response: {} as ApiResponse<EvidenceGetChainResponse>,
  },

  create: {
    channel: 'evidence:create' as const,
    request: {} as EvidenceCreateRequest,
    response: {} as ApiResponse<EvidenceCreateResponse>,
  },
} as const;

export type EvidenceInvokeChannels =
  | typeof EvidenceApi.getBySyndrome.channel
  | typeof EvidenceApi.getByDisease.channel
  | typeof EvidenceApi.getByAbility.channel
  | typeof EvidenceApi.getChain.channel
  | typeof EvidenceApi.create.channel;
