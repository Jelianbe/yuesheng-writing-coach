// 配置状态管理（Zustand）
// ⚠️ 本文件 catch 块中的 console.error / console.warn 仅用于开发调试，
//    生产环境应通过构建工具（如 terser drop_console）自动移除。
// 负责：管理 API 配置的前端状态，通过 service-bridge 单端点与主进程同步
// 依赖：zustand, service-bridge (Sprint 26 阶段 3.6: 调用方迁移)

import { create } from 'zustand';
import { serviceBridge } from '../services/service-bridge';
import { isCapacitor } from '../services/_dual-track';
import {
  loadConfig as capacitorLoadConfig,
  setConfigValue as capacitorSetConfig,
  testConnection as capacitorTestConnection,
} from '../services/capacitor-config';
import type {
  ApiConfig,
  ConnectionTestResult,
  ApiConfigValidation,
  AttitudeLevel,
} from '../shared/types';

/** 配置状态接口 */
interface ConfigState {
  // === 状态字段 ===
  /** API 密钥 */
  apiKey: string;
  /** API 基础 URL */
  baseUrl: string;
  /** 模型名称 */
  modelName: string;
  /** 温度参数 */
  temperature: number;
  /** 态度档位 */
  attitudeLevel: AttitudeLevel;
  /** 态度是否锁定 */
  attitudeLocked: boolean;
  /** 聊天流输出最大 token 数 */
  maxTokens: number;
  /** 是否已配置 */
  isConfigured: boolean;
  /** 是否正在加载（初始为 true，loadConfig 完成后设为 false） */
  isLoading: boolean;
  /** 连接测试状态 */
  testStatus: 'idle' | 'testing' | 'success' | 'error';
  /** 连接测试错误消息 */
  testError?: string;
  /** 连接测试响应时间 */
  testResponseTime?: number;
  /** 校验结果 */
  validation: ApiConfigValidation;

  // === 操作字段 ===
  /** 设置 API Key */
  setApiKey: (key: string) => Promise<void>;
  /** 设置 Base URL */
  setBaseUrl: (url: string) => Promise<void>;
  /** 设置模型名称 */
  setModelName: (name: string) => Promise<void>;
  /** 设置温度 */
  setTemperature: (temp: number) => Promise<void>;
  /** 设置态度档位 */
  setAttitudeLevel: (level: AttitudeLevel) => Promise<void>;
  /** 设置态度锁定 */
  setAttitudeLocked: (locked: boolean) => Promise<void>;
  /** 设置最大 token 数 */
  setMaxTokens: (tokens: number) => Promise<void>;
  /** 测试连接 */
  testConnection: () => Promise<ConnectionTestResult>;
  /** 从主进程加载配置 */
  loadConfig: () => Promise<void>;
  /** 重置校验状态 */
  resetValidation: () => void;
}

/**
 * 校验配置字段
 */
function validateConfig(config: Pick<ApiConfig, 'apiKey' | 'baseUrl' | 'modelName' | 'temperature'>): ApiConfigValidation {
  const errors: string[] = [];

  if (!config.apiKey || config.apiKey.trim().length === 0) {
    errors.push('API Key 不能为空');
  }

  if (!config.baseUrl || config.baseUrl.trim().length === 0) {
    errors.push('Base URL 不能为空');
  } else {
    try {
      new URL(config.baseUrl);
    } catch {
      errors.push('Base URL 格式无效');
    }
  }

  if (!config.modelName || config.modelName.trim().length === 0) {
    errors.push('Model Name 不能为空');
  }

  if (config.temperature < 0 || config.temperature > 2) {
    errors.push('Temperature 必须在 0-2 之间');
  }

  return {
    isValid: errors.length === 0,
    errors,
  };
}

/** 默认配置值 */
const DEFAULT_CONFIG: ApiConfig = {
  apiKey: '',
  baseUrl: 'https://api.deepseek.com',
  modelName: 'deepseek-v4-flash',
  temperature: 0.7,
  attitudeLevel: 'yuesheng',
  attitudeLocked: false,
  maxTokens: 8192,
};

/** 创建配置 Store */
export const useConfigStore = create<ConfigState>((set, get) => ({
  // 初始状态
  apiKey: '',
  baseUrl: DEFAULT_CONFIG.baseUrl,
  modelName: DEFAULT_CONFIG.modelName,
  temperature: DEFAULT_CONFIG.temperature,
  attitudeLevel: DEFAULT_CONFIG.attitudeLevel,
  attitudeLocked: DEFAULT_CONFIG.attitudeLocked,
  maxTokens: DEFAULT_CONFIG.maxTokens,
  isConfigured: false,
  isLoading: true,
  testStatus: 'idle',
  testError: undefined,
  testResponseTime: undefined,
  validation: { isValid: false, errors: ['尚未加载配置'] },

  /** 设置 API Key */
  setApiKey: async (key: string) => {
    if (isCapacitor()) {
      await capacitorSetConfig('apiKey', key);
    } else {
      await serviceBridge.invoke('config:set', { key: 'apiKey', value: key });
    }
    const validation = validateConfig({ ...get(), apiKey: key });
    set({
      apiKey: key,
      isConfigured: key.trim().length > 0,
      validation,
    });
  },

  /** 设置 Base URL */
  setBaseUrl: async (url: string) => {
    if (isCapacitor()) {
      await capacitorSetConfig('baseUrl', url);
    } else {
      await serviceBridge.invoke('config:set', { key: 'baseUrl', value: url });
    }
    const validation = validateConfig({ ...get(), baseUrl: url });
    set({ baseUrl: url, validation });
  },

  /** 设置模型名称 */
  setModelName: async (name: string) => {
    if (isCapacitor()) {
      await capacitorSetConfig('modelName', name);
    } else {
      await serviceBridge.invoke('config:set', { key: 'modelName', value: name });
    }
    const validation = validateConfig({ ...get(), modelName: name });
    set({ modelName: name, validation });
  },

  /** 设置温度 */
  setTemperature: async (temp: number) => {
    if (isCapacitor()) {
      await capacitorSetConfig('temperature', temp);
    } else {
      await serviceBridge.invoke('config:set', { key: 'temperature', value: temp });
    }
    const validation = validateConfig({ ...get(), temperature: temp });
    set({ temperature: temp, validation });
  },

  /** 设置态度档位 */
  setAttitudeLevel: async (level: AttitudeLevel) => {
    const { attitudeLocked } = get();
    if (attitudeLocked) return;
    if (isCapacitor()) {
      await capacitorSetConfig('attitudeLevel', level);
    } else {
      await serviceBridge.invoke('config:set', { key: 'attitudeLevel', value: level });
    }
    set({ attitudeLevel: level });
  },

  /** 设置态度锁定 */
  setAttitudeLocked: async (locked: boolean) => {
    if (isCapacitor()) {
      await capacitorSetConfig('attitudeLocked', locked);
    } else {
      await serviceBridge.invoke('config:set', { key: 'attitudeLocked', value: locked });
    }
    set({ attitudeLocked: locked });
  },

  /** 设置最大 token 数 */
  setMaxTokens: async (tokens: number) => {
    if (isCapacitor()) {
      await capacitorSetConfig('maxTokens', tokens);
    } else {
      await serviceBridge.invoke('config:set', { key: 'maxTokens', value: tokens });
    }
    set({ maxTokens: tokens });
  },

  /** 测试连接 */
  testConnection: async (): Promise<ConnectionTestResult> => {
    const { apiKey, baseUrl } = get();
    set({ testStatus: 'testing', testError: undefined, testResponseTime: undefined });

    const result = isCapacitor()
      ? await capacitorTestConnection(apiKey, baseUrl)
      : await serviceBridge.invoke<{ apiKey: string; baseUrl: string }, ConnectionTestResult>(
          'config:testConnection',
          { apiKey, baseUrl },
        );
    const finalResult = result ?? { success: false, error: 'No response data' };

    set({
      testStatus: finalResult.success ? 'success' : 'error',
      testError: finalResult.error,
      testResponseTime: finalResult.responseTime,
    });

    return finalResult;
  },

  /** 加载配置（Electron 走 IPC，Capacitor 走 localStorage） */
  loadConfig: async () => {
    set({ isLoading: true });
    try {
      let config: ApiConfig;

      if (isCapacitor()) {
        config = await capacitorLoadConfig();
      } else {
        const keys: Array<keyof ApiConfig> = [
          'apiKey', 'baseUrl', 'modelName', 'temperature',
          'attitudeLevel', 'attitudeLocked', 'maxTokens',
        ];
        const results = await Promise.all(
          keys.map(k => serviceBridge.invoke<{ key: string }, unknown>('config:get', { key: k })),
        );

        const extractValue = <T>(r: unknown, fallback: T): T => (r !== null && r !== undefined ? (r as T) : fallback);

        config = {
          apiKey: extractValue<string>(results[0], ''),
          baseUrl: extractValue<string>(results[1], DEFAULT_CONFIG.baseUrl),
          modelName: extractValue<string>(results[2], DEFAULT_CONFIG.modelName),
          temperature: extractValue<number>(results[3], DEFAULT_CONFIG.temperature),
          attitudeLevel: extractValue<AttitudeLevel>(results[4], DEFAULT_CONFIG.attitudeLevel),
          attitudeLocked: extractValue<boolean>(results[5], DEFAULT_CONFIG.attitudeLocked),
          maxTokens: extractValue<number>(results[6], DEFAULT_CONFIG.maxTokens),
        };
      }

      const validation = validateConfig(config);

      set({
        ...config,
        isConfigured: config.apiKey.trim().length > 0,
        isLoading: false,
        validation,
      });
    } catch (error) {
      console.error('加载配置失败:', error);
      set({ isLoading: false });
    }
  },

  /** 重置校验状态 */
  resetValidation: () => {
    set({ validation: { isValid: false, errors: [] } });
  },
}));
