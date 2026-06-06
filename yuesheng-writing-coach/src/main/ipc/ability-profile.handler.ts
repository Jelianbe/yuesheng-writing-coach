/**
 * 能力画像 IPC 处理器
 * 负责：响应前端查询能力画像的请求
 * 依赖：AbilityProfileService
 */

import { ipcMain, BrowserWindow } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { AbilityProfileService } from '../services/ability-profile.service';
import { apiSuccess, apiError } from '../../renderer/shared/types';

let service: AbilityProfileService | null = null;
let mainWindow: BrowserWindow | null = null;

/**
 * 设置能力画像服务实例
 */
export function setAbilityProfileService(svc: AbilityProfileService): void {
  service = svc;
}

/**
 * 设置主窗口实例
 */
export function setMainWindow(win: BrowserWindow): void {
  mainWindow = win;
}

/**
 * 注册能力画像相关的 IPC 处理器
 */
export function registerAbilityProfileHandlers(): void {
  ipcMain.handle(
    IPC_CHANNELS.ABILITY_GET_PROFILE,
    async (_event, args: { sessionId: string }) => {
      try {
        if (!mainWindow) {
          return apiError('Main window not available');
        }
        if (!service) {
          console.warn('[AbilityProfileHandler] Service not initialized');
          return apiError('AbilityProfileService not initialized');
        }
        const profile = await service.computeProfile(args.sessionId);
        return apiSuccess(profile);
      } catch (error) {
        console.error('[AbilityProfileHandler] ABILITY_GET_PROFILE Error:', error);
        return apiError(String(error));
      }
    },
  );
}
