/**
 * IPC 通道模拟工厂
 * 用于集成测试中模拟 Electron IPC，无需实际 Electron 环境
 */

import { vi } from 'vitest';

/** IPC 处理器映射（模拟 ipcMain.handle 注册） */
const handlerMap = new Map<string, (event: any, args: any) => any>();

/** 事件监听器映射（模拟 webContents.on 注册） */
const eventListenerMap = new Map<string, Set<(data: any) => void>>();

/** 模拟的 BrowserWindow 实例 */
export function createMockMainWindow() {
  const listeners = new Map<string, Set<(data: any) => void>>();

  return {
    webContents: {
      send: (channel: string, data: any) => {
        const handlers = listeners.get(channel);
        if (handlers) {
          handlers.forEach((fn) => fn(data));
        }
      },
      on: (channel: string, fn: (data: any) => void) => {
        if (!listeners.has(channel)) {
          listeners.set(channel, new Set());
        }
        listeners.get(channel)!.add(fn);
        return () => listeners.get(channel)?.delete(fn);
      },
      removeAllListeners: (channel?: string) => {
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
  } as any;
}

/** 模拟的 IPC Main 对象 */
export function createMockIpcMain() {
  const handlers = new Map<string, (event: any, args: any) => any>();

  return {
    handle: (channel: string, handler: (event: any, args: any) => any) => {
      handlers.set(channel, handler);
    },
    removeHandler: (channel: string) => {
      handlers.delete(channel);
    },
    /** 模拟调用指定的 IPC handler */
    invoke: async (channel: string, args: any) => {
      const handler = handlers.get(channel);
      if (!handler) {
        throw new Error(`No handler registered for channel: ${channel}`);
      }
      return handler({}, args);
    },
  } as any;
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
