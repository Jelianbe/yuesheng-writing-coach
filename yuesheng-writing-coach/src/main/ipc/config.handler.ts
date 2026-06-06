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

// ===== 服务引用 =====

let configService: ConfigService | null = null;

export function setConfigService(svc: ConfigService): void {
  configService = svc;
}

/**
 * 注册配置相关的 IPC 处理器
 * 应在主进程初始化时调用
 */
export function registerConfigHandlers(): void {
  if (!configService) {
    throw new Error('ConfigService not injected');
  }

  // 获取配置值
  // 渲染进程 -> 主进程: { key: string }
  // 主进程 -> 渲染进程: 配置值
  ipcMain.handle(
    IPC_CHANNELS.CONFIG_GET,
    (_event, args: { key: keyof ApiConfig }): ApiResponse<ApiConfig[keyof ApiConfig]> => {
      try {
        // 调用 getConfig() 而非 getConfigKey()，确保旧值自动升级逻辑生效
        return apiSuccess(configService!.getConfig()[args.key]);
      } catch (error) {
        console.error('[ConfigHandler] CONFIG_GET Error:', error);
        return apiError(String(error));
      }
    }
  );

  // 设置配置值
  // 渲染进程 -> 主进程: { key: string, value: any }
  // 主进程 -> 渲染进程: void
  ipcMain.handle(
    IPC_CHANNELS.CONFIG_SET,
    async (
      _event,
      args: { key: keyof ApiConfig; value: ApiConfig[keyof ApiConfig] }
    ): Promise<ApiResponse<undefined>> => {
      try {
        configService!.setConfigKey(args.key, args.value);
        return apiSuccess(undefined);
      } catch (error) {
        console.error('[ConfigHandler] CONFIG_SET Error:', error);
        return apiError(String(error));
      }
    }
  );

  // 测试连接
  // 渲染进程 -> 主进程: { apiKey: string, baseUrl: string }
  // 主进程 -> 渲染进程: { success: boolean, error?: string }
  ipcMain.handle(
    IPC_CHANNELS.CONFIG_TEST_CONNECTION,
    async (_event, args: { apiKey: string; baseUrl: string }): Promise<ApiResponse<ConnectionTestResult>> => {
      try {
        // 安全：不在日志中打印 API Key
        return apiSuccess(await configService!.testConnection(args.apiKey, args.baseUrl));
      } catch (error) {
        console.error('[ConfigHandler] CONFIG_TEST_CONNECTION Error:', error);
        return apiError(String(error));
      }
    }
  );
}
