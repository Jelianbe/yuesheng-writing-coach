/**
 * 统一 IPC handler 工厂函数
 *
 * 功能：
 * - 自动包裹 try-catch
 * - 标准化返回值格式 { success, data, error }
 * - 统一错误序列化
 *
 * 使用方式：
 *   createHandler('channel:name', async (event, args) => {
 *     const result = await service.method(args);
 *     return result;
 *   });
 *
 * handler 只需返回纯数据，不需要手动包裹 apiSuccess/apiError。
 * 验证失败时 throw new Error() 即可。
 */

import { ipcMain, IpcMainInvokeEvent } from 'electron';

type HandlerFn<TReq, TRes> = (event: IpcMainInvokeEvent, request: TReq) => Promise<TRes> | TRes;

interface HandlerResult<T> {
  success: boolean;
  data?: T;
  error?: string;
}

/**
 * 统一 IPC handler 工厂函数
 * - 自动包裹 try-catch
 * - 标准化返回值格式 { success, data, error }
 * - 统一错误序列化
 */
export function createHandler<TReq = unknown, TRes = unknown>(
  channel: string,
  handler: HandlerFn<TReq, TRes>,
): void {
  ipcMain.handle(channel, async (event, request: TReq): Promise<HandlerResult<TRes>> => {
    try {
      const data = await handler(event, request);
      return { success: true, data };
    } catch (error) {
      const isDev = process.env.NODE_ENV === 'development';
      const message = error instanceof Error ? error.message : String(error);
      if (isDev) {
        console.error(`[IPC] ${channel} error:`, error);
      } else {
        console.error(`[IPC] ${channel} error: ${message}`);
      }
      return { success: false, error: message };
    }
  });
}
