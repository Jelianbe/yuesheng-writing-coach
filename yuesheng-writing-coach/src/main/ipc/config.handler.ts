// 配置相关 IPC 处理器
// 负责：处理渲染进程的配置请求，转发到 ConfigService
// 依赖：electron.ipcMain, ConfigService
// 安全：不在日志中打印 API Key

import type { ConfigService } from '../shared/services/config.service';
import { IPC_CHANNELS } from '../../shared/constants';
import type {
  ApiConfig,
} from '../../shared/types/index';
import { createHandler } from './utils/create-handler';
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

/**
 * 可修改配置键白名单 — SEC-DEBT-1
 *
 * 运行时白名单，防止 renderer 注入任意 key 覆盖敏感配置。
 * 所有值类型在运行时再次校验。
 */
const CONFIG_SET_ALLOWED_KEYS = new Set<keyof ApiConfig>([
  'apiKey',
  'baseUrl',
  'modelName',
  'temperature',
  'attitudeLevel',
  'attitudeLocked',
  'maxTokens',
]);

/** 每个 key 对应的预期运行时类型 */
const CONFIG_VALUE_VALIDATORS: Record<string, (v: unknown) => boolean> = {
  apiKey: (v): v is string => typeof v === 'string',
  baseUrl: (v): v is string => typeof v === 'string',
  modelName: (v): v is string => typeof v === 'string',
  temperature: (v): v is number => typeof v === 'number' && v >= 0 && v <= 2,
  attitudeLevel: (v): v is string => typeof v === 'string' && ['yuesheng', 'doubao', 'sensei'].includes(v),
  attitudeLocked: (v): v is boolean => typeof v === 'boolean',
  maxTokens: (v): v is number => typeof v === 'number' && v >= 256 && v <= 128000,
};

/**
 * 注册配置相关的 IPC 处理器
 * 应在主进程初始化时调用
 */
export function registerConfigHandlers(): void {
  if (!deps) {
    throw new Error('ConfigHandler deps not injected');
  }
  const d = deps;

  // 获取配置值
  createHandler(
    IPC_CHANNELS.CONFIG_GET,
    (_event, args: { key: keyof ApiConfig }) => {
      return d.configService.getConfig()[args.key];
    }
  );

  // 设置配置值（SEC-DEBT-1：白名单 + 值类型校验）
  createHandler(
    IPC_CHANNELS.CONFIG_SET,
    async (
      _event,
      args: { key: string; value: unknown }
    ) => {
      // 1. 白名单检查
      if (!CONFIG_SET_ALLOWED_KEYS.has(args.key as keyof ApiConfig)) {
        throw new Error(`INVALID_PAYLOAD: config key '${args.key}' is not writable`);
      }
      // 2. 值类型校验（白名单 key 必须存在对应校验器）
      const validator = CONFIG_VALUE_VALIDATORS[args.key];
      if (!validator || !validator(args.value)) {
        throw new Error(`INVALID_PAYLOAD: invalid value type for config key '${args.key}'`);
      }
      d.configService.setConfigKey(args.key as keyof ApiConfig, args.value as ApiConfig[keyof ApiConfig]);
    }
  );

  // 测试连接
  createHandler(
    IPC_CHANNELS.CONFIG_TEST_CONNECTION,
    async (_event, args: { apiKey: string; baseUrl: string }) => {
      return await d.configService.testConnection(args.apiKey, args.baseUrl);
    }
  );

  // 获取阅读库条目（按症候 ID 筛选）
  createHandler(
    IPC_CHANNELS.CONFIG_GET_READING_ENTRY,
    async (_event, args: { syndromeId: string }) => {
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
        // 按 syndromeId 筛选：精确匹配或包含
        const matches = library.entries.filter(
          (e: { syndromeId: string }) => e.syndromeId === args.syndromeId
        );
        return { entries: matches };
      } catch {
        return { entries: [] };
      }
    }
  );
}
