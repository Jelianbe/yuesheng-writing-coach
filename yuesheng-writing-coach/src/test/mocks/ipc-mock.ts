/**
 * IPC 通道模拟工厂
 * 用于集成测试中模拟 Electron IPC，无需实际 Electron 环境
 */

import { vi } from 'vitest';

/** IPC handler 函数类型（模拟 Electron IPC handler 签名） */
type IpcHandlerFn = (event: Record<string, unknown>, args: Record<string, unknown>) => unknown;

/** 事件监听器回调类型 */
type EventListenerFn = (data: Record<string, unknown>) => void;

/** IPC 处理器映射（模拟 ipcMain.handle 注册） */
// @ts-expect-error: 保留供未来 mock 注册使用，当前通过 createMockIpcMain 动态注册
const _handlerMap = new Map<string, IpcHandlerFn>();

/** 事件监听器映射（模拟 webContents.on 注册） */
const eventListenerMap = new Map<string, Set<EventListenerFn>>();

/** 模拟的 BrowserWindow 实例 */
export function createMockMainWindow() {
  const listeners = new Map<string, Set<EventListenerFn>>();

  return {
    webContents: {
      send: (channel: string, data: Record<string, unknown>): void => {
        const handlers = listeners.get(channel);
        if (handlers) {
          handlers.forEach((fn) => fn(data));
        }
      },
      on: (channel: string, fn: EventListenerFn): (() => boolean | undefined) => {
        if (!listeners.has(channel)) {
          listeners.set(channel, new Set());
        }
        listeners.get(channel)!.add(fn);
        return () => listeners.get(channel)?.delete(fn);
      },
      removeAllListeners: (channel?: string): void => {
        if (channel) {
          listeners.delete(channel);
        } else {
          listeners.clear();
        }
      },
    },
    on: vi.fn(),
    loadURL: vi.fn(),
    close: vi.fn(),
  };
}

/** 模拟的 IPC Main 对象 */
export function createMockIpcMain() {
  const handlers = new Map<string, IpcHandlerFn>();

  return {
    handle: (channel: string, handler: IpcHandlerFn): void => {
      handlers.set(channel, handler);
    },
    removeHandler: (channel: string): void => {
      handlers.delete(channel);
    },
    /** 模拟调用指定的 IPC handler */
    invoke: async (
      channel: string,
      args: Record<string, unknown>,
    ): Promise<unknown> => {
      const handler = handlers.get(channel);
      if (!handler) {
        throw new Error(`No handler registered for channel: ${channel}`);
      }
      return handler({}, args);
    },
  };
}

/** 创建完整 IPC 测试环境 */
export function createIpcTestEnvironment() {
  const mainWindow = createMockMainWindow();
  const ipcMain = createMockIpcMain();

  return {
    mainWindow,
    ipcMain,
    /** 清理所有注册的 handler 和 listener */
    cleanup: () => {
      eventListenerMap.clear();
    },
  };
}
