// 配置相关 IPC 处理器
// 负责：处理渲染进程的配置请求，转发到 ConfigService
// 依赖：electron.ipcMain, ConfigService
// 安全：不在日志中打印 API Key

import { ConfigService } from '../shared/services/config.service';
import { IPC_CHANNELS } from '../../shared/constants';
import {
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

  // 设置配置值
  createHandler(
    IPC_CHANNELS.CONFIG_SET,
    async (
      _event,
      args: { key: keyof ApiConfig; value: ApiConfig[keyof ApiConfig] }
    ) => {
      d.configService.setConfigKey(args.key, args.value);
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
