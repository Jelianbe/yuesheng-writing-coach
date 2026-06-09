// 配置相关 IPC 处理器
// 负责：处理渲染进程的配置请求，转发到 ConfigService
// 依赖：electron.ipcMain, ConfigService
// 安全：不在日志中打印 API Key

import { ConfigService } from '../services/config.service';
import { IPC_CHANNELS } from '../../shared/constants';
import {
  ApiConfig,
  ConnectionTestResult,
} from '../../renderer/shared/types';
import { createHandler } from './utils/create-handler';

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

  // 获取配置值
  createHandler<{ key: keyof ApiConfig }, ApiConfig[keyof ApiConfig]>(
    IPC_CHANNELS.CONFIG_GET,
    (_event, args) => {
      return deps!.configService.getConfig()[args.key];
    },
  );

  // 设置配置值
  createHandler<{ key: keyof ApiConfig; value: ApiConfig[keyof ApiConfig] }, undefined>(
    IPC_CHANNELS.CONFIG_SET,
    async (_event, args) => {
      deps!.configService.setConfigKey(args.key, args.value);
      return undefined;
    },
  );

  // 测试连接
  createHandler<{ apiKey: string; baseUrl: string }, ConnectionTestResult>(
    IPC_CHANNELS.CONFIG_TEST_CONNECTION,
    async (_event, args) => {
      return await deps!.configService.testConnection(args.apiKey, args.baseUrl);
    },
  );
}
