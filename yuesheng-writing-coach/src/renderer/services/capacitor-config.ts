/**
 * Capacitor 配置持久化 — Sprint 31
 *
 * Android/Capacitor 端使用 localStorage 替代 electron-store 做配置持久化。
 * 每次读写更新内存缓存 + localStorage，重启时从 localStorage 恢复。
 *
 * 安全注意 (R-029):
 * - API Key 存于 Android WebView localStorage（应用沙箱隔离）
 * - 不打印到 console.log（仅在 debug 级别输出）
 * - 升级路径：后续可改为 @capacitor/preferences 加密存储
 */
import type { ApiConfig, ConnectionTestResult } from '../../shared/types/types-config';
import { isCapacitor } from './_dual-track';

// ============================================================
// 类型 & 常量
// ============================================================

const STORAGE_KEY = 'yuesheng_config';

const DEFAULT_CONFIG: ApiConfig = {
  apiKey: '',
  baseUrl: 'https://api.deepseek.com',
  modelName: 'deepseek-v4-flash',
  temperature: 0.7,
  attitudeLevel: 'yuesheng',
  attitudeLocked: false,
  maxTokens: 8192,
};

/** 连接测试超时（毫秒） */
const TEST_TIMEOUT_MS = 10_000;

// ============================================================
// 内存缓存（避免频繁序列化 localStorage）
// ============================================================

let _cache: ApiConfig | null = null;

function loadFromStorage(): ApiConfig {
  if (_cache) return _cache;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<ApiConfig>;
      _cache = { ...DEFAULT_CONFIG, ...parsed };
      return _cache;
    }
  } catch {
    // localStorage 不可用或数据损坏，使用默认值
  }
  _cache = { ...DEFAULT_CONFIG };
  return _cache;
}

function saveToStorage(config: ApiConfig): void {
  _cache = { ...config };
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
  } catch {
    // localStorage 满或不可用，静默失败（配置在内存中可用）
  }
}

// ============================================================
// 公开 API
// ============================================================

/** 加载全部配置（Android 端替代 loadConfig IPC） */
export async function loadConfig(): Promise<ApiConfig> {
  return loadFromStorage();
}

/** 获取单个配置项 */
export async function getConfigValue<K extends keyof ApiConfig>(key: K): Promise<ApiConfig[K]> {
  const config = loadFromStorage();
  return config[key];
}

/** 设置单个配置项 */
export async function setConfigValue<K extends keyof ApiConfig>(key: K, value: ApiConfig[K]): Promise<void> {
  const config = loadFromStorage();
  config[key] = value;
  saveToStorage(config);
}

/** 测试连接（Android 端直接 fetch） */
export async function testConnection(apiKey: string, baseUrl: string): Promise<ConnectionTestResult> {
  const startTime = Date.now();
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), TEST_TIMEOUT_MS);

    const response = await fetch(`${baseUrl.replace(/\/+$/, '')}/v1/models`, {
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      signal: controller.signal,
    });

    clearTimeout(timeout);

    if (!response.ok) {
      return {
        success: false,
        error: `HTTP ${response.status}: ${response.statusText}`,
        responseTime: Date.now() - startTime,
      };
    }

    return {
      success: true,
      responseTime: Date.now() - startTime,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      success: false,
      error: message,
      responseTime: Date.now() - startTime,
    };
  }
}

/** 判断当前是否应在 Capacitor 端使用本模块（导出辅助函数） */
export function shouldUseCapacitorConfig(): boolean {
  return isCapacitor();
}
