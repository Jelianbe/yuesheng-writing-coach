/**
 * 能力画像 IPC 处理器
 * 负责：响应前端查询能力画像的请求
 * 依赖：AbilityProfileService
 */

import { IPC_CHANNELS } from '../../shared/constants';
import { AbilityProfileService } from '../domains/student/ability-profile.service';
import { createHandler } from './utils/create-handler';

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
  createHandler(IPC_CHANNELS.ABILITY_GET_PROFILE, async (_event, args: { sessionId: string }) => {
    if (!deps) {
      console.warn('[AbilityProfileHandler] Deps not initialized');
      throw new Error('AbilityProfileHandler deps not initialized');
    }
    const profile = await deps.abilityProfileService.computeProfile(args.sessionId);
    return profile;
  });
}
