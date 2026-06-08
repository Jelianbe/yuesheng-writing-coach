/**
 * 能力画像 IPC 处理器
 * 负责：响应前端查询能力画像的请求
 * 依赖：AbilityProfileService
 */

import { ipcMain } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { AbilityProfileService } from '../services/ability-profile.service';
import { apiSuccess, apiError } from '../../renderer/shared/types';

export interface AbilityProfileHandlerDeps {
  abilityProfileService: AbilityProfileService;
}

let deps: AbilityProfileHandlerDeps | null = null;

export function initAbilityProfileHandlers(d: AbilityProfileHandlerDeps): void {
  deps = d;
}

/**
 * 注册能力画像相关的 IPC 处理器
 */
export function registerAbilityProfileHandlers(): void {
  ipcMain.handle(
    IPC_CHANNELS.ABILITY_GET_PROFILE,
    async (_event, args: { sessionId: string }) => {
      try {
        if (!deps) {
          console.warn('[AbilityProfileHandler] Deps not initialized');
          return apiError('AbilityProfileHandler deps not initialized');
        }
        const profile = await deps.abilityProfileService.computeProfile(args.sessionId);
        return apiSuccess(profile);
      } catch (error) {
        console.error('[AbilityProfileHandler] ABILITY_GET_PROFILE Error:', error);
        return apiError(String(error));
      }
    },
  );
}
