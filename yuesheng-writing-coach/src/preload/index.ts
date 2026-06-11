import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electronAPI', {
  invoke: (channel: string, args: unknown): Promise<unknown> => {
    const allowedChannels = [
      'config:get',
      'config:set',
      'config:testConnection',
      // diagnosis:query — handler 已注册，但 renderer 当前未直接调用（预留）
      'diagnosis:submitRewrite',
      'diagnosis:getComparison',
      'growth:getTrends',
      // growth:getGlobalTrends — 预留，renderer 未使用
      'teachingState:get',
      'teachingState:update',
      'teachingState:confirm',
      // teachingState:getPrompt — 预留，renderer 未使用
      // teachingState:updateSummary — 预留，renderer 未使用
      'ability:getProfile',
      'chat:send',
      'chat:stop',
      'onboarding:analyze',
      'session:list',
      // session:listWithMeta — 预留，renderer 未使用
      'session:searchMessages',
      'session:create',
      'session:delete',
      'session:rename',
      // session:getMessages — renderer 使用分页版 session:getMessagesPaged
      'session:getMessagesPaged',
      'session:isNewUser',
      // session:updateTitle — 预留，renderer 未使用
      // evidence:* — 以下 4 个通道均为预留，handler 已注册但 renderer 未调用
      // 'evidence:getByDisease',
      // 'evidence:getByAbility',
      // 'evidence:getChain',
      // 'evidence:create',
      'training:recommend',
      'training:assign',
      'training:complete',
      // training:skip — store 内部直接设 null，未通过 IPC 调用
      'training:history',
      'training:submit',
      'training:evaluate',
      'training:derive-behavior',
      'manuscript:list',
      // manuscript:get — renderer 未使用（仅 manuscript:list/create/update）
      'manuscript:create',
      'manuscript:update',
      'manuscript:delete',
      'chapter:list',
      'chapter:get',
      'chapter:create',
      'chapter:delete',
      'chapter:updateContent',
    ];
    if (!allowedChannels.includes(channel)) {
      throw new Error(`Disallowed IPC channel: ${channel}`);
    }
    return ipcRenderer.invoke(channel, args);
  },

  on: (channel: string, callback: (...args: unknown[]) => void): (() => void) => {
    const allowedEvents = [
      'diagnosis:update',
      'teachingState:updated',
      'chat:stream:data',
      'chat:stream:end',
    ];
    if (!allowedEvents.includes(channel)) {
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
