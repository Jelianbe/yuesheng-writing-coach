/**
 * preload 脚本 — Electron 安全桥接
 *
 * ⚠️ Electron sandbox 限制：preload 无法 require 外部相对路径模块，
 * 因此白名单必须内联在此文件。
 *
 * Sprint 26 阶段 3.4/3.5: invoke 白名单已压缩为单端点 `bridge:invoke`。
 * 调用方通过 `serviceBridge.invoke('domain:method', args)` 走单 RPC 端点。
 * window 控制保留(单向 send)、事件通道保留(主进程推送)。
 *
 * 添加新 IPC 通道时：
 *   1. invoke 通道: 在主进程 service-bridge.registerMethod 注册,客户端用 serviceBridge.invoke
 *   2. event 通道: 在此处 allowedEventChannels 添加,在主进程用 webContents.send
 *   3. send 通道(单向): 在此处 allowedSendChannels 添加
 */

import { contextBridge, ipcRenderer } from 'electron';

/** 允许渲染进程通过 invoke() 调用的 IPC 通道白名单 — 阶段 3.5 压缩为单端点 bridge:invoke */
const allowedInvokeChannels: readonly string[] = [
  'bridge:invoke',
];

/** 允许渲染进程通过 send() 单向发送的 IPC 通道白名单 */
const allowedSendChannels: readonly string[] = [
  'window:minimize',
  'window:maximize',
  'window:close',
];

/** 允许渲染进程通过 on() 订阅的 IPC 事件通道白名单 */
const allowedEventChannels: readonly string[] = [
  'diagnosis:updated',
  'teachingState:updated',
  'teachingState:mastery',
  'chat:stream:data',
  'chat:stream:end',
  'chat:tool:executing',
  'chat:event',
  // Sprint 24 A-4: ActiveTraining 状态推送事件(主进程 → renderer)
  'activeTraining:updated',
];

contextBridge.exposeInMainWorld('electronAPI', {
  invoke: (channel: string, args: unknown): Promise<unknown> => {
    if (!allowedInvokeChannels.includes(channel)) {
      return Promise.reject(new Error(`Disallowed IPC channel: ${channel}`));
    }
    return ipcRenderer.invoke(channel, args);
  },

  send: (channel: string, args: unknown): void => {
    if (!allowedSendChannels.includes(channel)) {
      throw new Error(`Disallowed IPC channel: ${channel}`);
    }
    ipcRenderer.send(channel, args);
  },

  on: (channel: string, callback: (...args: unknown[]) => void): (() => void) => {
    if (!allowedEventChannels.includes(channel)) {
      throw new Error(`Disallowed event channel: ${channel}`);
    }
    const handler = (_event: Electron.IpcRendererEvent, ...args: unknown[]) => {
      callback(...args);
    };
    ipcRenderer.on(channel, handler);
    return () => {
      ipcRenderer.removeListener(channel, handler);
    };
  },
});
