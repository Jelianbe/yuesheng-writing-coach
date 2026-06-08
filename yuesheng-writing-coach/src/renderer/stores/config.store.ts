// 配置状态管理（Zustand）
// 负责：管理 API 配置的前端状态，通过 IPC 与主进程同步
// 依赖：zustand, electron IPC (通过 preload 暴露)

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import type {
  ApiConfig,
  ConnectionTestResult,
  ApiConfigValidation,
  AttitudeLevel,
  ApiResponse,
} from '../shared/types';
import { getInvoke } from '../utils/ipc';

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
  /** 聊天流输出最大 token 数 */
  maxTokens: number;
  /** 是否已配置 */
  isConfigured: boolean;
  /** 是否正在加载 */
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
  maxTokens: DEFAULT_CONFIG.maxTokens,
  isConfigured: false,
  isLoading: false,
  testStatus: 'idle',
  testError: undefined,
  testResponseTime: undefined,
  validation: { isValid: false, errors: ['尚未加载配置'] },

  /** 设置 API Key */
  setApiKey: async (key: string) => {
    const invoke = getInvoke();
    await invoke(IPC_CHANNELS.CONFIG_SET, { key: 'apiKey', value: key });
    const validation = validateConfig({ ...get(), apiKey: key });
    set({
      apiKey: key,
      isConfigured: key.trim().length > 0,
      validation,
    });
  },

  /** 设置 Base URL */
  setBaseUrl: async (url: string) => {
    const invoke = getInvoke();
    await invoke(IPC_CHANNELS.CONFIG_SET, { key: 'baseUrl', value: url });
    const validation = validateConfig({ ...get(), baseUrl: url });
    set({ baseUrl: url, validation });
  },

  /** 设置模型名称 */
  setModelName: async (name: string) => {
    const invoke = getInvoke();
    await invoke(IPC_CHANNELS.CONFIG_SET, { key: 'modelName', value: name });
    const validation = validateConfig({ ...get(), modelName: name });
    set({ modelName: name, validation });
  },

  /** 设置温度 */
  setTemperature: async (temp: number) => {
    const invoke = getInvoke();
    await invoke(IPC_CHANNELS.CONFIG_SET, { key: 'temperature', value: temp });
    const validation = validateConfig({ ...get(), temperature: temp });
    set({ temperature: temp, validation });
  },

  /** 设置态度档位 */
  setAttitudeLevel: async (level: AttitudeLevel) => {
    const invoke = getInvoke();
    await invoke(IPC_CHANNELS.CONFIG_SET, { key: 'attitudeLevel', value: level });
    set({ attitudeLevel: level });
  },

  /** 测试连接 */
  testConnection: async (): Promise<ConnectionTestResult> => {
    const { apiKey, baseUrl } = get();
    set({ testStatus: 'testing', testError: undefined, testResponseTime: undefined });

    try {
      const invoke = getInvoke();
      const response = (await invoke(IPC_CHANNELS.CONFIG_TEST_CONNECTION, {
        apiKey,
        baseUrl,
      })) as ApiResponse<ConnectionTestResult>;
      const result = response.data ?? { success: false, error: response.error || 'No response data' };

      set({
        testStatus: result.success ? 'success' : 'error',
        testError: result.error,
        testResponseTime: result.responseTime,
      });

      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : '未知错误';
      set({
        testStatus: 'error',
        testError: errorMessage,
      });
      return { success: false, error: errorMessage };
    }
  },

  /** 从主进程加载配置 */
  loadConfig: async () => {
    set({ isLoading: true });
    try {
      const invoke = getInvoke();
      const results = await Promise.all([
        invoke(IPC_CHANNELS.CONFIG_GET, { key: 'apiKey' }),
        invoke(IPC_CHANNELS.CONFIG_GET, { key: 'baseUrl' }),
        invoke(IPC_CHANNELS.CONFIG_GET, { key: 'modelName' }),
        invoke(IPC_CHANNELS.CONFIG_GET, { key: 'temperature' }),
        invoke(IPC_CHANNELS.CONFIG_GET, { key: 'attitudeLevel' }),
        invoke(IPC_CHANNELS.CONFIG_GET, { key: 'maxTokens' }),
      ]) as ApiResponse<unknown>[];

      const extractValue = <T>(r: ApiResponse<unknown> | undefined | null, fallback: T): T =>
        r && typeof r === 'object' && 'success' in r ? (r.success ? (r.data as T) : fallback) : fallback;

      const apiKey = extractValue<string>(results[0], '');
      const baseUrl = extractValue<string>(results[1], DEFAULT_CONFIG.baseUrl);
      const modelName = extractValue<string>(results[2], DEFAULT_CONFIG.modelName);
      const temperature = extractValue<number>(results[3], DEFAULT_CONFIG.temperature);
      const attitudeLevel = extractValue<AttitudeLevel>(results[4], DEFAULT_CONFIG.attitudeLevel);
      const maxTokens = extractValue<number>(results[5], DEFAULT_CONFIG.maxTokens);

      const config: ApiConfig = {
        apiKey,
        baseUrl,
        modelName,
        temperature,
        attitudeLevel,
        maxTokens,
      };

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

