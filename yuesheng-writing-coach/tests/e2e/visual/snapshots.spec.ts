/**
 * 视觉回归基线
 *
 * @visual 标签:用 Playwright 内置 toHaveScreenshot
 *
 * 设计:
 * - baseline 入仓(在 tests/e2e/visual/snapshots/ 下)
 * - maxDiffPixels: 100 容忍微小差异
 * - 覆盖:3 根页 + 1 子页
 *
 * 使用:
 * - 首次:`npm run test:visual`(创建基线)
 * - 后续:`npm run test:visual:check`(对比)
 */

import { test, expect } from '@playwright/test';

const ROOT_PAGES = ['书架', '对话', '应用'] as const;

test.describe('视觉回归基线 @visual', () => {
  test.describe.configure({ mode: 'parallel' });

  for (const tabName of ROOT_PAGES) {
    test(`根页:${tabName}`, async ({ page }) => {
      await page.goto('/');
      if (tabName !== '书架') {
        await page.getByRole('navigation').getByRole('button', { name: tabName }).click();
      }
      await expect(page.getByRole('heading', { name: tabName, level: 1 })).toBeVisible();

      // 整页截图(全滚动区域)
      await expect(page).toHaveScreenshot(`root-${tabName}.png`, {
        fullPage: true,
        maxDiffPixelRatio: 0.01,
      });
    });
  }

  test('子页:成长报告', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
    await page.getByText('成长报告', { exact: true }).first().click();
    await expect(page.getByRole('heading', { name: '成长报告' })).toBeVisible();
    // 等加载占位稳定
    await expect(page.getByText('数据加载中…')).toBeVisible();

    await expect(page).toHaveScreenshot('sub-growth-report.png', {
      fullPage: true,
      maxDiffPixelRatio: 0.01,
    });
  });
});
