import { BrowserWindow, app } from 'electron';
import * as path from 'path';

export class WindowManager {
  private mainWindow: BrowserWindow | null = null;

  create(): BrowserWindow {
    // 使用 app.getAppPath() 获取项目根目录，避免 __dirname 因编译输出位置不同而变化
    const preloadPath = path.join(app.getAppPath(), 'dist', 'preload', 'index.js');
    this.mainWindow = new BrowserWindow({
      width: 1280,
      height: 800,
      minWidth: 1024,
      minHeight: 640,
      frame: false,
      webPreferences: {
        preload: preloadPath,
        contextIsolation: true,
        nodeIntegration: false,
      },
    });

    if (process.env.NODE_ENV === 'development') {
      this.mainWindow.loadURL('http://localhost:5173');
      this.mainWindow.webContents.openDevTools();
    } else {
      this.mainWindow.loadFile(path.join(app.getAppPath(), 'dist', 'renderer', 'index.html'));
    }

    this.mainWindow.on('closed', () => {
      this.mainWindow = null;
    });

    return this.mainWindow;
  }

  get(): BrowserWindow | null {
    return this.mainWindow;
  }
}
