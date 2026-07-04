/**
 * Service Bridge IPC 端点 — Sprint 26 阶段 3.5 方案 4a
 *
 * 唯一 invoke 端点 `bridge:invoke`,由 createHandler 包装(自带 try-catch + 幂等键)。
 *
 * 挂载时机: 在 ipc-registry 完成所有 service 注册后,最后一步调 `mountBridgeEndpoint()`。
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.5 方案 4a
 */
import { IPC_CHANNELS } from '../../shared/constants';
import { createHandler } from '../ipc/utils/create-handler';
import { handleBridgeInvoke } from './service-bridge';
import type { ServiceInvokeRequest } from '../../shared/bridge/bridge-protocol';

/** 挂载单端点 bridge:invoke(整个应用仅此一处 ipcMain.handle) */
export function mountBridgeEndpoint(): void {
  createHandler<ServiceInvokeRequest, unknown>(IPC_CHANNELS.BRIDGE_INVOKE, async (_event, request) => {
    return handleBridgeInvoke(request);
  });
}
