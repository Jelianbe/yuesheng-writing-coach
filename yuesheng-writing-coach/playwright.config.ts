import { defineConfig, devices } from '@playwright/test';

/**
 * 月笙写作教练 — Playwright E2E 配置
 *
 * 规范来源:.trae/rules/playwright-e2e/SKILL.md
 *
 * 设计原则:
 * 1. Vite-only 跑 E2E(不需要 Electron 主进程),启动快、CI 友好
 * 2. 两个 project:firefox(桌面) + firefox-mobile(移动端,核心场景)
 * 3. 视觉基线入仓(不依赖外部服务),仅 firefox-mobile
 * 4. a11y 报告入仓 test-results/(不阻断 CI,渐进式修)
 * 5. 默认平衡模式:仅失败时留 trace/screenshot/video
 *    设置 PWVERBOSE=1 开启全量捕获(慢但过程可见)
 *
 * 浏览器缓存:Playwright 在 %LOCALAPPDATA%\ms-playwright\
 * 缓存,仅在 Playwright 版本升级时才下载新浏览器,
 * 平时复用缓存,不会每次测试都重新下载。
 *
 * 报告打开:`npm run test:report`(等价 `npx playwright show-report`)
 */
const VERBOSE = process.env.PWVERBOSE === '1';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: 'playwright-report' }],
    ['json', { outputFile: 'test-results/results.json' }],
  ],
  outputDir: 'test-results/',
  timeout: 30_000,
  expect: {
    timeout: 5_000,
    toHaveScreenshot: {
      maxDiffPixels: 100,
      threshold: 0.2,
    },
  },
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:5173',
    // 平衡模式:失败留 trace + 截图 + 视频;VERBOSE 模式:全留
    trace: VERBOSE ? 'on' : 'on-first-retry',
    screenshot: VERBOSE ? 'on' : 'only-on-failure',
    video: VERBOSE ? 'on' : 'retain-on-failure',
    actionTimeout: 10_000,
    navigationTimeout: 30_000,
  },
  projects: [
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
      // 桌面端不跑视觉基线（项目规范：基线仅覆盖 firefox-mobile）
      testIgnore: /visual\//,
    },
    {
      name: 'firefox-mobile',
      use: {
        ...devices['Desktop Firefox'],
        viewport: { width: 393, height: 851 },
        deviceScaleFactor: 2.75,
        // Firefox 不支持 isMobile,改用 viewport + hasTouch + userAgent 模拟
        hasTouch: true,
        userAgent: 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Firefox/93.0 Mobile/Chrome',
      },
    },
  ],
  webServer: {
    command: 'npm run dev:vite',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    stdout: 'pipe',
    stderr: 'pipe',
  },
});
