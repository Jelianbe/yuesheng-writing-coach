/**
 * Service Bridge Client — Sprint 26 阶段 3.5 方案 4a renderer 端
 *
 * 统一调用入口,把 16 个 IPC channel 压缩为 1 个 `bridge:invoke` 端点。
 *
 * 双轨:
 * - Android 端: 直调 service(走 runDualTrack)
 * - Electron 端: typedInvoke(BRIDGE_INVOKE_CHANNEL, { method, args })
 *
 * 错误处理: 失败时 console.error + 返回 fallback(由 signature 推断)
 *
 * 用法:
 *   await serviceBridge.invoke('project:list', {}, 'projectService', 'listProjects');
 *   或(更直白):
 *   await serviceBridge.invokeDirect<{ sessionId: string }, AbilityProfile>(
 *     'ability:getProfile',
 *     { sessionId },
 *     () => directAbilityService.getProfile(sessionId),
 *   );
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.5 方案 4a
 */
import { typedInvoke } from './ipc-client';
import { IPC_CHANNELS } from '../../shared/constants';
import { isCapacitor } from './_dual-track';
import type { ServiceInvokeRequest } from '../../shared/bridge/bridge-protocol';

const BRIDGE_CHANNEL = IPC_CHANNELS.BRIDGE_INVOKE;

/**
 * Bridge invoke — 跨端统一调用入口
 *
 * @param method - `domain:method` 形式,如 `project:list`
 * @param args - service 方法入参
 * @param directFallback - 可选:Android 端直调函数,签名 `(args: TArgs) => Promise<TResult>`
 *                      若不传,Android 端返回 null(调用方需自己处理)
 * @returns handler 返回值(或直调结果)
 */
export async function invokeBridge<TArgs, TResult>(
  method: string,
  args: TArgs,
  directFallback?: (args: TArgs) => Promise<TResult>,
): Promise<TResult | null> {
  // Android 端走直调(不依赖 IPC)
  if (isCapacitor() && directFallback) {
    try {
      return await directFallback(args);
    } catch (err) {
      console.error(`[serviceBridge] ${method} direct call failed:`, err);
      return null;
    }
  }

  // Electron 端走单端点 bridge
  const req: ServiceInvokeRequest = { method, args };
  const result = await typedInvoke<ServiceInvokeRequest, TResult>(BRIDGE_CHANNEL, req);
  if (!result.success) {
    console.error(`[serviceBridge] ${method} failed:`, result.error);
    return null;
  }
  return result.data;
}

/** 简化 API — 显式声明"只走 Electron"(Android 端 noop) */
export async function invokeBridgeElectronOnly<TArgs, TResult>(
  method: string,
  args: TArgs,
): Promise<TResult | null> {
  const req: ServiceInvokeRequest = { method, args };
  const result = await typedInvoke<ServiceInvokeRequest, TResult>(BRIDGE_CHANNEL, req);
  if (!result.success) {
    console.error(`[serviceBridge] ${method} failed:`, result.error);
    return null;
  }
  return result.data;
}

export const serviceBridge = { invoke: invokeBridge, invokeElectronOnly: invokeBridgeElectronOnly };
