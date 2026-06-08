import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electronAPI', {
  invoke: (channel: string, args: unknown): Promise<unknown> => {
    const allowedChannels = [
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
      'chat:send',
      'onboarding:analyze',
      'session:list',
      'session:listWithMeta',
      'session:searchMessages',
      'session:create',
      'session:delete',
      'session:rename',
      'session:getMessages',
      'session:getMessagesPaged',
      'evidence:getByDisease',
      'evidence:getByAbility',
      'evidence:getChain',
      'evidence:create',
      'training:recommend',
      'training:assign',
      'training:complete',
      'training:skip',
      'training:history',
      'training:submit',
      'training:evaluate',
      'training:derive-behavior',
      'manuscript:list',
      'manuscript:get',
      'manuscript:create',
      'manuscript:update',
      'chapter:list',
      'chapter:get',
      'chapter:create',
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
