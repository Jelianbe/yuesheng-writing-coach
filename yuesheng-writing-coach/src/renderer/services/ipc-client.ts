/**
 * 类型化 IPC 客户端
 *
 * 基于 API Contract 的类型安全 invoke/on 封装。
 * 各域 Service 通过此模块调用主进程，不直接访问 window.electronAPI。
 */

import type { ApiResponse } from '../../shared/api-contracts/base';

/**
 * 类型化 invoke — 编译时校验 channel 名与 payload/返回类型
 */
export async function typedInvoke<TRequest, TResponse>(
  channel: string,
  payload: TRequest,
): Promise<ApiResponse<TResponse>> {
  if (!window.electronAPI) {
    return { success: false, error: 'electronAPI not available' };
  }
  const result = await window.electronAPI.invoke(channel, payload);
  return result as ApiResponse<TResponse>;
}

/**
 * 类型化事件监听
 * @returns cleanup 函数
 */
export function typedOn<TEvent>(
  channel: string,
  handler: (data: TEvent) => void,
): () => void {
  if (!window.electronAPI) return () => {};
  return window.electronAPI.on(channel, (data: unknown) => handler(data as TEvent));
}
