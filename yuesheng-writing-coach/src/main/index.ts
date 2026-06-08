// 月笙写作教练 - 主进程入口
// 负责：应用生命周期管理，委托 AppInitializer 完成初始化

import { app, BrowserWindow } from 'electron';
import { AppInitializer } from './core/app-initializer';
import { ServiceContainer } from './core/service-container';

let appInitializer: AppInitializer | null = null;

app.whenReady().then(async () => {
  const container = ServiceContainer.getInstance();
  appInitializer = new AppInitializer(container);
  await appInitializer.initialize();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0 && appInitializer) {
    appInitializer.recreateWindow();
  }
});
