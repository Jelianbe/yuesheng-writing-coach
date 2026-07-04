/**
 * Service Bridge Protocol — Sprint 26 阶段 3.5 方案 4a
 *
 * 目的: 把 16 个 IPC handler 压缩为 1 个通用 RPC 端点
 *
 * 设计:
 * - 客户端发请求:`{ method: 'domain:method', args: unknown }`
 * - 服务端从白名单查 method → handler,调 handler(args),返回结果
 * - 白名单 = 显式注册的 service:method 映射
 *
 * 收益:
 * - `ipcMain.handle` 调用从 ~75 个降为 1 个
 * - 新增 service:method 不需要改 IPC_CHANNELS / preload / ipc-registry
 * - 主进程有完整权限控制(未注册的 method 直接拒绝)
 *
 * 跨端策略:
 * - Android 端 renderer 直接调 service,不走 bridge
 * - Electron 端 renderer 走 `bridge:invoke` 单端点
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.5 方案 4a
 */
import type { ApiResponse } from '../api-contracts/base';

/** Bridge 单一 IPC 通道名 */
export const BRIDGE_INVOKE_CHANNEL = 'bridge:invoke' as const;

/** Bridge invoke 请求体 */
export interface ServiceInvokeRequest {
  /** 形如 `domain:method`,例:`project:list` */
  method: string;
  /** service 方法入参(任意可序列化对象) */
  args: unknown;
}

/** Bridge invoke 响应体 — 与 ApiResponse 保持一致 */
export type ServiceInvokeResponse = ApiResponse<unknown>;
