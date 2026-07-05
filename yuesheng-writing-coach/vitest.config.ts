import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { storybookTest } from '@storybook/addon-vitest/vitest-plugin';
import { playwright } from '@vitest/browser-playwright';
import { cjsToEsmFix } from './src/renderer/plugins/cjs-to-esm-fix';

const dirname = typeof __dirname !== 'undefined' ? __dirname : path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  plugins: [cjsToEsmFix(), react()],
  root: 'src/renderer',
  base: './',
  build: {
    outDir: '../../dist/renderer',
    emptyOutDir: true,
    target: 'chrome120',
    sourcemap: 'hidden',
  },
  resolve: {
    alias: {
      '@': path.resolve(dirname, './src/renderer'),
    },
  },
  server: {
    port: 5173,
  },
  test: {
    projects: [
      {
        test: {
          name: 'renderer',
          root: '.',
          include: ['src/renderer/**/*.test.{ts,tsx}'],
          environment: 'jsdom',
          globals: true,
          setupFiles: ['src/renderer/test/setup.ts'],
          css: true,
          coverage: {
            enabled: true,
            reportsDirectory: 'coverage/renderer',
            include: ['src/renderer/**/*.{ts,tsx}'],
            exclude: ['src/renderer/**/*.test.*', 'src/renderer/test/**', 'src/renderer/**/__tests__/**'],
            thresholds: {
              lines: 55,
              branches: 45,
              functions: 50,
              statements: 55,
            },
          },
        },
      },
      {
        test: {
          name: 'main',
          root: '.',
          include: ['src/main/**/*.test.ts'],
          exclude: [],
          environment: 'node',
          globals: true,
          coverage: {
            enabled: true,
            reportsDirectory: 'coverage/main',
            include: ['src/main/**/*.ts'],
            exclude: ['src/main/**/*.test.*', 'src/main/**/__tests__/**'],
            thresholds: {
              lines: 60,
              branches: 50,
              functions: 55,
              statements: 60,
            },
          },
        },
      },
      {
        test: {
          name: 'shared',
          root: '.',
          include: ['src/shared/**/*.test.ts'],
          environment: 'node',
          globals: true,
          coverage: {
            enabled: true,
            reportsDirectory: 'coverage/shared',
            include: ['src/shared/**/*.ts'],
            exclude: ['src/shared/**/*.test.*', 'src/shared/**/__tests__/**'],
            thresholds: {
              lines: 65,
              branches: 55,
              functions: 60,
              statements: 65,
            },
          },
        },
      },
      {
        extends: true,
        plugins: [
          storybookTest({ configDir: path.join(dirname, '.storybook') }),
        ],
        test: {
          name: 'storybook',
          browser: {
            enabled: true,
            headless: true,
            provider: playwright({}),
            instances: [{ browser: 'chromium' }],
          },
        },
      },
    ],
  },
});
