/**
 * Service Bridge — Sprint 26 阶段 3.5 方案 4a
 *
 * 主进程单端点 RPC 桥,替代 16 个 IPC handler 文件。
 *
 * 核心 API:
 * - `registerMethod(method, handler)` — 注册 method → handler 映射(白名单)
 * - `handleBridgeInvoke(req)` — 端点处理器,查白名单调 handler,返回纯数据
 * - `getRegisteredMethods()` — 返回已注册 method 列表(供调试)
 *
 * 安全模型:
 * - 未注册 method 直接抛 METHOD_NOT_REGISTERED 错误
 * - 不暴露 SQL/路径/任意 IPC,只允许显式注册的方法
 *
 * 生命周期:
 * - 应用启动时 ipc-registry 调 registerMethod 注册所有 service 方法
 * - 注册完成后,ipc-registry 调 createHandler(BRIDGE_INVOKE_CHANNEL, handleBridgeInvoke)
 *   挂载 IPC 端点(createHandler 自带 try-catch + 幂等键支持)
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.5 方案 4a
 */
import type { ServiceInvokeRequest } from '../../shared/bridge/bridge-protocol';

/** Method handler 类型: 接 args,返回 promise 结果或抛错 */
export type BridgeMethodHandler = (args: unknown) => Promise<unknown>;

/** 错误类(让 createHandler 序列化) */
class MethodNotRegisteredError extends Error {
  constructor(method: string) {
    super(`METHOD_NOT_REGISTERED: ${method}`);
    this.name = 'MethodNotRegisteredError';
  }
}

class InvalidRequestError extends Error {
  constructor(message: string) {
    super(`INVALID_REQUEST: ${message}`);
    this.name = 'InvalidRequestError';
  }
}

/** 全局白名单 Map<method, handler> */
const methodRegistry = new Map<string, BridgeMethodHandler>();

/** 注册一个 method + handler(白名单入口) */
export function registerMethod(method: string, handler: BridgeMethodHandler): void {
  if (methodRegistry.has(method)) {
    console.warn(`[ServiceBridge] Overwriting existing method: ${method}`);
  }
  methodRegistry.set(method, handler);
}

/** 批量注册 — 接收 {method, handler}[] 数组 */
export function registerMethods(entries: Array<{ method: string; handler: BridgeMethodHandler }>): void {
  for (const { method, handler } of entries) {
    registerMethod(method, handler);
  }
}

/** 移除一个 method(用于测试/重置) */
export function unregisterMethod(method: string): boolean {
  return methodRegistry.delete(method);
}

/** 清空所有 method(用于测试) */
export function clearRegistry(): void {
  methodRegistry.clear();
}

/** 返回已注册 method 列表(只读副本) */
export function getRegisteredMethods(): string[] {
  return Array.from(methodRegistry.keys()).sort();
}

/** 检查 method 是否已注册 */
export function isMethodRegistered(method: string): boolean {
  return methodRegistry.has(method);
}

/**
 * Bridge invoke 端点主入口 — 由 createHandler 包装,返回纯数据或抛错
 *
 * 用法:
 *   createHandler(BRIDGE_INVOKE_CHANNEL, handleBridgeInvoke);
 *
 * createHandler 会自动:
 * - 捕获抛出的错误并返回 { success: false, error: message }
 * - 支持 idempotencyKey(5 秒内同 key 去重)
 *
 * @param req - 来自 renderer 的 ServiceInvokeRequest
 * @returns handler 返回的纯数据
 * @throws InvalidRequestError / MethodNotRegisteredError / handler 自身错误
 */
export async function handleBridgeInvoke(req: ServiceInvokeRequest): Promise<unknown> {
  if (!req || typeof req.method !== 'string') {
    throw new InvalidRequestError('missing method string');
  }

  const handler = methodRegistry.get(req.method);
  if (!handler) {
    throw new MethodNotRegisteredError(req.method);
  }

  return handler(req.args);
}

/** 内部 — 供测试使用的注册表快照 */
export function _getRegistryForTest(): ReadonlyMap<string, BridgeMethodHandler> {
  return new Map(methodRegistry);
}
