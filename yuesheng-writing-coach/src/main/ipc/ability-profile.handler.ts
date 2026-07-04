/**
 * 能力画像 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`abilityProfileService`('ability:getProfile', { sessionId })
 */

import { registerMethod } from '../core/service-bridge';
import type { AbilityProfileService } from '../domains/02-prescription/student/ability-profile.service';

let abilityProfileService: AbilityProfileService | null = null;

/** 注入 service(原 initAbilityProfileHandlers) */
export function initAbilityProfileHandlers(d: { abilityProfileService: AbilityProfileService }): void {
  abilityProfileService = d.abilityProfileService;
}

/** 注册 method 到 bridge(原 registerAbilityProfileHandlers) */
export function registerAbilityProfileHandlers(): void {
  registerMethod('ability:getProfile', async (args) => {
    if (!abilityProfileService) {
      throw new Error('AbilityProfileService not initialized');
    }
    const { sessionId } = args as { sessionId: string };
    return abilityProfileService.computeProfile(sessionId);
  });
}
