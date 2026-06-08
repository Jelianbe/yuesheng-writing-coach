/**
 * IPC 通用工具
 *
 * 提供统一的 handler 包装函数，确保所有 IPC 通道的错误处理风格一致。
 * 响应格式：{ success: boolean, data?: T, error?: string }
 */

import { apiSuccess, apiError } from '../../renderer/shared/types';

/**
 * 创建标准化 IPC handler 包装函数
 *
 * 使用方法：
 *   ipcMain.handle('channel:name', createHandler(async (event, args) => {
 *     const result = await someService.doSomething(args);
 *     return result;
 *   }));
 *
 * 自动处理：
 *   - try-catch 包装
 *   - 统一错误响应格式
 *   - 错误日志记录
 *   - 生产环境不暴露 stack trace
 */
export function createHandler<T, R>(
  fn: (event: Electron.IpcMainInvokeEvent, args: T) => R | Promise<R>,
): (event: Electron.IpcMainInvokeEvent, args: T) => Promise<ReturnType<typeof apiSuccess<R>> | ReturnType<typeof apiError>> {
  return async (event, args) => {
    try {
      const result = await fn(event, args);
      return apiSuccess(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : '未知错误';
      console.error(`[IPC] Handler error:`, errorMessage);
      return apiError(errorMessage);
    }
  };
}
