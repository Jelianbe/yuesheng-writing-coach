import { contextBridge, ipcRenderer } from 'electron';
import { ALLOWED_INVOKE_CHANNELS, ALLOWED_EVENT_CHANNELS } from '../shared/constants';

contextBridge.exposeInMainWorld('electronAPI', {
  invoke: (channel: string, args: unknown): Promise<unknown> => {
    if (!ALLOWED_INVOKE_CHANNELS.includes(channel)) {
      return Promise.reject(new Error(`Disallowed IPC channel: ${channel}`));
    }
    return ipcRenderer.invoke(channel, args);
  },

  on: (channel: string, callback: (...args: unknown[]) => void): (() => void) => {
    if (!ALLOWED_EVENT_CHANNELS.includes(channel)) {
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
