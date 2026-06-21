/**
 * IPC 调用工具函数
 * 依据：E-04 消除多处 (window as any).electronAPI
 * 使用方式：所有渲染进程模块从此文件导入 getInvoke / invoke / subscribe
 *
 * 类型安全：
 * - invoke 使用 IPCRequestMap + IPCResponseMap 编译时校验通道/参数/返回类型
 */

import type { IPCRequestMap, IPCResponseMap } from '../shared/types';

/**
 * 类型安全的 IPC invoke
 * @example
 *   const result = await invoke('config:get', { key: 'apiKey' });
 *   // result 类型为 ApiConfig[keyof ApiConfig]
 */
export async function invoke<C extends keyof IPCRequestMap & keyof IPCResponseMap & string>(
  channel: C,
  args?: IPCRequestMap[C],
): Promise<IPCResponseMap[C]> {
  if (!window.electronAPI?.invoke) {
    throw new Error('[IPC] ElectronAPI not available. Make sure preload script is loaded.');
  }
  return window.electronAPI.invoke(channel, args) as Promise<IPCResponseMap[C]>;
}

/**
 * 为 IPC 请求添加幂等键（IDEM-1）
 *
 * 自动生成一个唯一 idempotencyKey 注入到请求参数中。
 * 后端 createHandler 在 TTL（5 秒）内遇到同一 key 的请求会自动返回缓存结果。
 * 适用于 WRITE-risk 通道（training:evaluate, chat:send, diagnosis:submitRewrite 等）。
 *
 * @param args  请求参数对象
 * @param key   可选的自定义 key（未提供时自动生成 UUID）
 * @returns     注入 idempotencyKey 后的请求参数
 *
 * @example
 *   await invoke('training:evaluate', withIdempotency({ trainingId, answer }));
 */
export function withIdempotency<T extends Record<string, unknown>>(
  args: T,
  key?: string,
): T & { idempotencyKey: string } {
  return {
    ...args,
    idempotencyKey: key ?? crypto.randomUUID(),
  };
}

/**
 * 获取安全的 IPC invoke 函数（无类型校验，用于无法使用类型化版本的场景）
 * 在非 Electron 环境（HMR / 浏览器预览）中返回空操作函数，不抛异常
 */
export function getInvoke(): (channel: string, args?: unknown) => Promise<unknown> {
  if (!window.electronAPI?.invoke) {
    // 非 Electron 环境返回空操作（HMR / 浏览器预览）
    return async () => ({ success: false, error: 'IPC not available' });
  }
  return window.electronAPI.invoke.bind(window.electronAPI);
}

// subscribe 函数已移除（零引用）— 若需事件监听，请使用 window.electronAPI.on 直接绑定
