/**
 * 配置管理 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('config:get' | 'config:set' | 'config:testConnection' | 'config:getReadingEntry', ...)`
 *
 * 保留 SEC-DEBT-1 白名单 + 值类型校验(安全要求)
 * 保留 app.isPackaged 路径解析(已知不可靠,后续 Sprint 27 修)
 */

import type { ConfigService } from '../shared/services/config.service';
import type { ApiConfig } from '../../shared/types/index';
import { registerMethod } from '../core/service-bridge';
import { app } from 'electron';
import * as path from 'path';
import * as fs from 'fs';

export interface ConfigHandlerDeps {
  configService: ConfigService;
}

let deps: ConfigHandlerDeps | null = null;

export function initConfigHandlers(d: ConfigHandlerDeps): void {
  deps = d;
}

const CONFIG_SET_ALLOWED_KEYS = new Set<keyof ApiConfig>([
  'apiKey',
  'baseUrl',
  'modelName',
  'temperature',
  'attitudeLevel',
  'attitudeLocked',
  'maxTokens',
]);

const CONFIG_VALUE_VALIDATORS: Record<string, (v: unknown) => boolean> = {
  apiKey: (v): v is string => typeof v === 'string',
  baseUrl: (v): v is string => typeof v === 'string',
  modelName: (v): v is string => typeof v === 'string',
  temperature: (v): v is number => typeof v === 'number' && v >= 0 && v <= 2,
  attitudeLevel: (v): v is string => typeof v === 'string' && ['yuesheng', 'doubao', 'sensei'].includes(v),
  attitudeLocked: (v): v is boolean => typeof v === 'boolean',
  maxTokens: (v): v is number => typeof v === 'number' && v >= 256 && v <= 128000,
};

export function registerConfigHandlers(): void {
  if (!deps) {
    throw new Error('ConfigHandler deps not injected');
  }
  const d = deps;

  registerMethod('config:get', async (args) => {
    const { key } = args as { key: keyof ApiConfig };
    return d.configService.getConfig()[key];
  });

  registerMethod('config:set', async (args) => {
    const { key, value } = args as { key: string; value: unknown };
    if (!CONFIG_SET_ALLOWED_KEYS.has(key as keyof ApiConfig)) {
      throw new Error(`INVALID_PAYLOAD: config key '${key}' is not writable`);
    }
    const validator = CONFIG_VALUE_VALIDATORS[key];
    if (!validator || !validator(value)) {
      throw new Error(`INVALID_PAYLOAD: invalid value type for config key '${key}'`);
    }
    d.configService.setConfigKey(key as keyof ApiConfig, value as ApiConfig[keyof ApiConfig]);
  });

  registerMethod('config:testConnection', async (args) => {
    const { apiKey, baseUrl } = args as { apiKey: string; baseUrl: string };
    return await d.configService.testConnection(apiKey, baseUrl);
  });

  registerMethod('config:getReadingEntry', async (args) => {
    const { syndromeId } = args as { syndromeId: string };
    const resourcesRoot = app.isPackaged
      ? path.join(process.resourcesPath, 'config')
      : path.join(app.getAppPath(), 'resources', 'config');
    const filePath = path.join(resourcesRoot, 'reading-library.json');
    try {
      const raw = fs.readFileSync(filePath, 'utf-8');
      const library = JSON.parse(raw);
      if (!library.entries || !Array.isArray(library.entries)) {
        return { entries: [] };
      }
      const matches = library.entries.filter(
        (e: { syndromeId: string }) => e.syndromeId === syndromeId
      );
      return { entries: matches };
    } catch {
      return { entries: [] };
    }
  });
}
