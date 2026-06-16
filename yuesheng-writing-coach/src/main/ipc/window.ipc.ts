/**
 * window.ipc — 窗口控制 IPC handler
 *
 * 负责：最小化 / 最大化（还原）/ 关闭窗口
 * 通道格式：domain:action（遵循 IPC 规范）
 * 使用 ipcMain.on 而非 handle，因为窗口操作无需返回值
 */

import { ipcMain, type BrowserWindow } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';

/** 窗口控制 handler 初始化（需要 mainWindow 引用） */
export function initWindowHandlers(mainWindow: BrowserWindow): void {
  ipcMain.on(IPC_CHANNELS.WINDOW_MINIMIZE, () => {
    mainWindow.minimize();
  });

  ipcMain.on(IPC_CHANNELS.WINDOW_MAXIMIZE, () => {
    if (mainWindow.isMaximized()) {
      mainWindow.unmaximize();
    } else {
      mainWindow.maximize();
    }
  });

  ipcMain.on(IPC_CHANNELS.WINDOW_CLOSE, () => {
    mainWindow.close();
  });
}
