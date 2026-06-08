// 配置相关 IPC 处理器
// 负责：处理渲染进程的配置请求，转发到 ConfigService
// 依赖：electron.ipcMain, ConfigService
// 安全：不在日志中打印 API Key

import { ipcMain } from 'electron';
import { ConfigService } from '../services/config.service';
import { IPC_CHANNELS } from '../../shared/constants';
import {
  ApiConfig,
  ApiResponse,
  ConnectionTestResult,
  apiSuccess,
  apiError,
} from '../../renderer/shared/types';

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
  ipcMain.handle(
    IPC_CHANNELS.CONFIG_GET,
    (_event, args: { key: keyof ApiConfig }): ApiResponse<ApiConfig[keyof ApiConfig]> => {
      try {
        return apiSuccess(deps!.configService.getConfig()[args.key]);
      } catch (error) {
        console.error('[ConfigHandler] CONFIG_GET Error:', error);
        return apiError(String(error));
      }
    }
  );

  // 设置配置值
  ipcMain.handle(
    IPC_CHANNELS.CONFIG_SET,
    async (
      _event,
      args: { key: keyof ApiConfig; value: ApiConfig[keyof ApiConfig] }
    ): Promise<ApiResponse<undefined>> => {
      try {
        deps!.configService.setConfigKey(args.key, args.value);
        return apiSuccess(undefined);
      } catch (error) {
        console.error('[ConfigHandler] CONFIG_SET Error:', error);
        return apiError(String(error));
      }
    }
  );

  // 测试连接
  ipcMain.handle(
    IPC_CHANNELS.CONFIG_TEST_CONNECTION,
    async (_event, args: { apiKey: string; baseUrl: string }): Promise<ApiResponse<ConnectionTestResult>> => {
      try {
        return apiSuccess(await deps!.configService.testConnection(args.apiKey, args.baseUrl));
      } catch (error) {
        console.error('[ConfigHandler] CONFIG_TEST_CONNECTION Error:', error);
        return apiError(String(error));
      }
    }
  );
}
