interface ElectronAPI {
  invoke: (channel: string, args?: unknown) => Promise<unknown>;
  on: (channel: string, callback: (...args: unknown[]) => void) => () => void;
}

interface Window {
  /** preload 脚本注入的 Electron API（非 Electron 环境可能为 undefined） */
  electronAPI?: ElectronAPI;
}
