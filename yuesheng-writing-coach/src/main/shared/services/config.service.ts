// 配置管理服务
// 负责：使用 electron-store 读写配置、验证 API Key、测试连接
// 依赖：electron-store, fetch
// 安全：API Key 存储于用户数据目录，不打印到 console

import Store from 'electron-store';
import type { ApiConfig, ApiConfigValidation, ConnectionTestResult } from '../../../shared/types/index';

/** 配置存储键名常量 */
const CONFIG_KEYS = {
  API_KEY: 'apiKey',
  BASE_URL: 'baseUrl',
  MODEL_NAME: 'modelName',
  TEMPERATURE: 'temperature',
  ATTITUDE_LEVEL: 'attitudeLevel',
  MAX_TOKENS: 'maxTokens',
} as const;

/** 默认配置值
 * DeepSeek V4 (2026-04-24 发布)
 * - 上下文窗口：1M tokens
 * - 模型名：deepseek-v4-flash（默认）/ deepseek-v4-pro（旗舰）
 * - BASE URL（OpenAI 格式）：https://api.deepseek.com
 * - 旧模型名 deepseek-chat 将于 2026-07-24 停用
 */
const DEFAULT_CONFIG: ApiConfig = {
  apiKey: '',
  baseUrl: 'https://api.deepseek.com',
  modelName: 'deepseek-v4-flash',
  temperature: 0.7,
  attitudeLevel: 'yuesheng',
  maxTokens: 8192,
};

/** 连接测试超时时间（毫秒） */
const TEST_CONNECTION_TIMEOUT_MS = 10_000;

/**
 * 配置管理服务（单例）
 * 提供配置的读取、写入、验证和连接测试功能
 */
export class ConfigService {
  private store: Store<ApiConfig>;
  private static instance: ConfigService | null = null;

  constructor() {
    // electron-store 自动将数据存储于用户数据目录
    this.store = new Store<ApiConfig>({
      name: 'api-config',
      defaults: DEFAULT_CONFIG,
      // 启用加密存储（操作系统级别保护）
      encryptionKey: undefined, // 后续可启用加密
    });
  }

  /**
   * 获取单例实例
   */
  static getInstance(): ConfigService {
    if (!ConfigService.instance) {
      ConfigService.instance = new ConfigService();
    }
    return ConfigService.instance;
  }

  /**
   * 获取完整的 API 配置（含旧值升级迁移）
   */
  getConfig(): ApiConfig {
    // 读取存储值，回退到默认值
    const config = {
      apiKey: this.store.get(CONFIG_KEYS.API_KEY, DEFAULT_CONFIG.apiKey),
      baseUrl: this.store.get(CONFIG_KEYS.BASE_URL, DEFAULT_CONFIG.baseUrl),
      modelName: this.store.get(CONFIG_KEYS.MODEL_NAME, DEFAULT_CONFIG.modelName),
      temperature: this.store.get(CONFIG_KEYS.TEMPERATURE, DEFAULT_CONFIG.temperature),
      attitudeLevel: this.store.get(CONFIG_KEYS.ATTITUDE_LEVEL, DEFAULT_CONFIG.attitudeLevel),
      maxTokens: this.store.get(CONFIG_KEYS.MAX_TOKENS, DEFAULT_CONFIG.maxTokens),
    };

    // === 自动升级旧配置值 ===
    let needsUpgrade = false;

    if (config.baseUrl === 'https://api.deepseek.com/v1') {
      config.baseUrl = 'https://api.deepseek.com';
      needsUpgrade = true;
    }
    if (config.modelName === 'deepseek-v4-pro') {
      config.modelName = 'deepseek-v4-flash';
      needsUpgrade = true;
    }
    // 旧版 attitudeLevel 'sharp'/'gentle' → 新版三态
    const legacyLevel = config.attitudeLevel as string;
    if (legacyLevel === 'sharp' || legacyLevel === 'gentle') {
      config.attitudeLevel = 'yuesheng';
      needsUpgrade = true;
    }

    // 自动保存升级后的值
    if (needsUpgrade) {
      this.store.set(CONFIG_KEYS.BASE_URL, config.baseUrl);
      this.store.set(CONFIG_KEYS.MODEL_NAME, config.modelName);
      this.store.set(CONFIG_KEYS.ATTITUDE_LEVEL, config.attitudeLevel);
      console.log('[Config] 已自动升级旧配置值');
    }

    return config;
  }

  /**
   * 获取单个配置项
   * @param key 配置键名
   * @returns 配置值
   */
  getConfigKey<K extends keyof ApiConfig>(key: K): ApiConfig[K] {
    return this.store.get(key, DEFAULT_CONFIG[key]) as ApiConfig[K];
  }

  /**
   * 设置单个配置项
   * @param key 配置键名
   * @param value 配置值
   */
  setConfigKey<K extends keyof ApiConfig>(key: K, value: ApiConfig[K]): void {
    this.store.set(key, value);
  }

  /**
   * 批量设置配置项
   * @param config 配置对象
   */
  setConfig(config: Partial<ApiConfig>): void {
    if (config.apiKey !== undefined) this.store.set(CONFIG_KEYS.API_KEY, config.apiKey);
    if (config.baseUrl !== undefined) this.store.set(CONFIG_KEYS.BASE_URL, config.baseUrl);
    if (config.modelName !== undefined) this.store.set(CONFIG_KEYS.MODEL_NAME, config.modelName);
    if (config.temperature !== undefined) this.store.set(CONFIG_KEYS.TEMPERATURE, config.temperature);
    if (config.maxTokens !== undefined) this.store.set(CONFIG_KEYS.MAX_TOKENS, config.maxTokens);
  }

  /**
   * 验证 API 配置是否有效
   * @returns 校验结果
   */
  validateConfig(config: ApiConfig): ApiConfigValidation {
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

  /**
   * 测试 API 连接
   * 通过主进程发起请求，避免 CORS 问题，隐藏 API Key
   * 使用 chat/completions 端点做最小请求（比 /models 更可靠）
   * @param apiKey API 密钥
   * @param baseUrl API 基础 URL
   * @returns 连接测试结果
   */
  async testConnection(apiKey: string, baseUrl: string): Promise<ConnectionTestResult> {
    const startTime = Date.now();
    const modelName = this.getConfigKey('modelName');

    // 使用 chat/completions 端点做最小请求测试（所有 OpenAI 兼容 API 都支持）
    const testUrl = `${baseUrl.replace(/\/+$/, '')}/chat/completions`;

    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), TEST_CONNECTION_TIMEOUT_MS);

      try {
        const response = await fetch(testUrl, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: modelName,
            messages: [{ role: 'user', content: 'hi' }],
            max_tokens: 1,
            stream: false,
          }),
          signal: controller.signal,
        });

        clearTimeout(timeoutId);
        const responseTime = Date.now() - startTime;

        if (!response.ok) {
          // 提取错误信息，剥离敏感数据
          let errorMessage: string;
          try {
            const errorData = await response.json() as Record<string, unknown>;
            errorMessage = (errorData.error as Record<string, string>)?.message ?? `HTTP ${response.status}`;
          } catch {
            errorMessage = `HTTP ${response.status}: ${response.statusText}`;
          }

          return {
            success: false,
            error: `连接失败: ${errorMessage}`,
            responseTime,
          };
        }

        return {
          success: true,
          responseTime,
        };
      } catch (fetchError) {
        clearTimeout(timeoutId);
        throw fetchError;
      }
    } catch (error) {
      const responseTime = Date.now() - startTime;

      // 安全地处理错误，不暴露敏感信息
      let errorMessage: string;
      if (error instanceof Error) {
        if (error.name === 'AbortError') {
          errorMessage = `连接超时（>${TEST_CONNECTION_TIMEOUT_MS / 1000}秒）`;
        } else if (error.message.includes('ENOTFOUND') || error.message.includes('ECONNREFUSED')) {
          errorMessage = '无法连接到服务器，请检查 Base URL 是否正确';
        } else {
          errorMessage = `网络错误: ${error.message}`;
        }
      } else {
        errorMessage = '未知错误';
      }

      return {
        success: false,
        error: errorMessage,
        responseTime,
      };
    }
  }

  /**
   * 重置配置为默认值
   */
  resetConfig(): void {
    this.store.set(DEFAULT_CONFIG);
  }

  /**
   * 检查是否已配置 API Key
   */
  isConfigured(): boolean {
    const apiKey = this.getConfigKey(CONFIG_KEYS.API_KEY);
    return apiKey.trim().length > 0;
  }
}
