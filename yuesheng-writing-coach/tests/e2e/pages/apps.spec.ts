/**
 * AppsPage 应用中心
 *
 * @critical 标签:核心入口
 */

import { test, expect } from '@playwright/test';
import { SUB_PAGES } from '../../utils/test-data';

test.describe('AppsPage 应用中心 @critical', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
  });

  test('应用页标题和 TabBar 可见', async ({ page }) => {
    await expect(page.getByRole('heading', { name: '应用', level: 1 })).toBeVisible();
    await expect(page.getByRole('navigation')).toBeVisible();
  });

  test('2 个图标全部渲染', async ({ page }) => {
    for (const sub of SUB_PAGES) {
      await expect(page.getByText(sub.label, { exact: true }).first()).toBeVisible();
    }
  });

  test('1 个工具项全部渲染', async ({ page }) => {
    for (const label of ['设定管理']) {
      await expect(page.getByText(label, { exact: true })).toBeVisible();
    }
  });

  test('工具区有"设置"分割标题', async ({ page }) => {
    await expect(page.getByText('设置', { exact: true })).toBeVisible();
  });
});
