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
        },
      },
      {
        test: {
          name: 'shared',
          root: '.',
          include: ['src/shared/**/*.test.ts'],
          environment: 'node',
          globals: true,
        },
      },
    ],
  },
});
