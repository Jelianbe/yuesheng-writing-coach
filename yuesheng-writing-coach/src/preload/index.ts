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
      'session:list',
      'session:create',
      'session:delete',
      'session:rename',
      'session:getMessages',
      'evidence:getByDisease',
      'evidence:getByAbility',
      'evidence:getChain',
      'evidence:create',
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
