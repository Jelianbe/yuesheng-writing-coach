/**
 * IPC 调用工具函数
 * 依据：E-04 消除多处 (window as any).electronAPI
 * 使用方式：所有渲染进程模块从此文件导入 getInvoke / invoke / subscribe
 *
 * 类型安全：
 * - invoke 使用 IPCRequestMap + IPCResponseMap 编译时校验通道/参数/返回类型
 * - subscribe 使用 IPCEventMap 编译时校验通道和数据负载类型
 */

import type { IPCRequestMap, IPCResponseMap, IPCEventMap } from '../shared/types';

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

/**
 * 类型安全的 IPC 事件监听
 * 自动处理 cleanup
 *
 * @example
 *   const cleanup = subscribe('chat:stream:data', (data) => {
 *     // data 类型为 { sessionId: string; chunk: string }
 *   });
 */
export function subscribe<C extends keyof IPCEventMap & string>(
  channel: C,
  callback: (data: IPCEventMap[C]) => void,
): () => void {
  if (!window.electronAPI?.on) {
    // 非 Electron 环境返回空 cleanup（HMR / 浏览器预览）
    return () => {};
  }
  return window.electronAPI.on(channel, (...args: unknown[]) => {
    callback(args[0] as IPCEventMap[C]);
  });
}
