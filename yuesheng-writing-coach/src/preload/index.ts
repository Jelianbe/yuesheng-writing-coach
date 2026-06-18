/**
 * preload 脚本 — Electron 安全桥接
 *
 * ⚠️ Electron sandbox 限制：preload 无法 require 外部相对路径模块，
 * 因此白名单必须内联在此文件。同步参考 src/shared/constants.ts。
 *
 * 添加新 IPC 通道时，必须同步更新：
 *   1. src/shared/constants.ts（IPC_CHANNELS + ALLOWED_INVOKE_CHANNELS）
 *   2. src/shared/constants.js（IPC_CHANNELS + 白名单）
 *   3. src/preload/index.ts（下面的 allowedInvokeChannels / allowedEventChannels）
 */

import { contextBridge, ipcRenderer } from 'electron';

/** 允许渲染进程通过 invoke() 调用的 IPC 通道白名单 */
const allowedInvokeChannels: readonly string[] = [
  'config:get',
  'config:set',
  'config:testConnection',
  'diagnosis:query',
  'diagnosis:submitRewrite',
  'diagnosis:getComparison',
  'growth:getTrends',
  'growth:getGlobalTrends',
  'teachingState:get',
  'teachingState:update',
  'teachingState:confirm',
  'teachingState:getPrompt',
  'teachingState:updateSummary',
  'ability:getProfile',
  'evidence:getByDisease',
  'evidence:getByAbility',
  'evidence:getChain',
  'evidence:create',
  'evidence:getBySyndrome',
  'chat:send',
  'chat:stop',
  'session:list',
  'session:create',
  'session:delete',
  'session:rename',
  'session:getMessages',
  'session:getMessagesPaged',
  'session:listWithMeta',
  'session:updateTitle',
  'session:searchMessages',
  'session:isNewUser',
  'onboarding:analyze',
  'training:recommend',
  'training:assign',
  'training:complete',
  'training:skip',
  'training:history',
  'training:submit',
  'training:evaluate',
  'training:deriveBehavior',
  'manuscript:list',
  'manuscript:get',
  'manuscript:create',
  'manuscript:update',
  'manuscript:delete',
  'chapter:list',
  'chapter:get',
  'chapter:create',
  'chapter:delete',
  'chapter:updateContent',
  'teachingHistory:add',
];

/** 允许渲染进程通过 send() 单向发送的 IPC 通道白名单 */
const allowedSendChannels: readonly string[] = [
  'window:minimize',
  'window:maximize',
  'window:close',
];

/** 允许渲染进程通过 on() 订阅的 IPC 事件通道白名单 */
const allowedEventChannels: readonly string[] = [
  'diagnosis:update',
  'teachingState:updated',
  'teachingState:mastery',
  'chat:stream:data',
  'chat:stream:end',
  'chat:tool:executing',
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
