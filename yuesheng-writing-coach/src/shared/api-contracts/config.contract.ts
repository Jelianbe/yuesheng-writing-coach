import type { ApiResponse } from './base';

// ─── 请求类型 ───

export interface ConfigGetRequest {
  keys?: string[];
}

export interface ConfigSetRequest {
  values: Record<string, unknown>;
}

export interface ConfigTestConnectionRequest {
  apiKey: string;
  endpoint?: string;
}

// ─── 响应类型 ───

export interface ConfigGetResponse {
  values: Record<string, unknown>;
}

export interface ConfigSetResponse {
  success: true;
}

export interface ConfigTestConnectionResponse {
  ok: boolean;
  message: string;
}

// ─── API 接口定义 ───

export const ConfigApi = {
  get: {
    channel: 'config:get' as const,
    request: {} as ConfigGetRequest,
    response: {} as ApiResponse<ConfigGetResponse>,
  },

  set: {
    channel: 'config:set' as const,
    request: {} as ConfigSetRequest,
    response: {} as ApiResponse<ConfigSetResponse>,
  },

  testConnection: {
    channel: 'config:testConnection' as const,
    request: {} as ConfigTestConnectionRequest,
    response: {} as ApiResponse<ConfigTestConnectionResponse>,
  },
} as const;

export type ConfigInvokeChannels =
  | typeof ConfigApi.get.channel
  | typeof ConfigApi.set.channel
  | typeof ConfigApi.testConnection.channel;
