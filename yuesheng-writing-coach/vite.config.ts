import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import * as path from 'path';
import { cjsToEsmFix } from './src/renderer/plugins/cjs-to-esm-fix';

export default defineConfig({
  plugins: [cjsToEsmFix(), react()],
  root: 'src/renderer',
  base: './',  // Electron file:// 协议必须使用相对路径
  build: {
    outDir: '../../dist/renderer',
    emptyOutDir: true,
    target: 'chrome120',
    sourcemap: 'hidden',  // 生产生成 sourcemap 但不暴露给用户，用于崩溃报告
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src/renderer'),
    },
  },
  server: {
    port: 5173,
  },
});
