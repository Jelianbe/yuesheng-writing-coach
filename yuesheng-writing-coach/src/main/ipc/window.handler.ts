/**
 * 窗口控制 IPC Handler
 *
 * 处理窗口最小化、最大化、关闭操作
 */

import { ipcMain, BrowserWindow } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';

/** 获取当前主窗口实例 */
function getMainWindow(): BrowserWindow | null {
  const wins = BrowserWindow.getAllWindows();
  return wins.length > 0 ? wins[0] : null;
}

/**
 * 初始化窗口控制 handler
 */
export function initWindowHandlers(): void {
  // 最小化窗口
  ipcMain.on(IPC_CHANNELS.WINDOW_MINIMIZE, () => {
    const win = getMainWindow();
    if (win) win.minimize();
  });

  // 最大化/还原窗口
  ipcMain.on(IPC_CHANNELS.WINDOW_MAXIMIZE, () => {
    const win = getMainWindow();
    if (win) {
      if (win.isMaximized()) {
        win.unmaximize();
      } else {
        win.maximize();
      }
    }
  });

  // 关闭窗口
  ipcMain.on(IPC_CHANNELS.WINDOW_CLOSE, () => {
    const win = getMainWindow();
    if (win) win.close();
  });
}
