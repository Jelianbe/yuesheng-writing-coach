/**
 * ElectronAPI 类型声明
 *
 * 由 preload/index.ts 通过 contextBridge.exposeInMainWorld 暴露。
 * 消除渲染进程中 (window as any).electronAPI 的类型不安全模式。
 */

interface ElectronAPI {
  /**
   * 调用主进程 IPC handler
   * 通道名在 preload 中经过白名单校验
   */
  invoke(channel: string, args?: unknown): Promise<unknown>;

  /**
   * 监听主进程事件推送
   * @returns cleanup 函数，调用后移除监听器
   */
  on(channel: string, callback: (...args: unknown[]) => void): () => void;
}

interface Window {
  electronAPI: ElectronAPI | undefined;
}
