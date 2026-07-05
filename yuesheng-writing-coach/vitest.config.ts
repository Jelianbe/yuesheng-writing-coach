import { defineConfig } from 'vitest/config';

export default defineConfig({
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
    ],
  },
});
