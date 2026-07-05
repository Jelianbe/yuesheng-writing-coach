/**
 * TabBar 切换 — 3 个根 tab 验证
 *
 * @smoke 标签:每次 PR 必跑
 */

import { test, expect } from '@playwright/test';
import { ROOT_TABS } from '../../utils/test-data';

test.describe('TabBar 切换 @smoke', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('书架 tab 初始激活', async ({ page }) => {
    await expect(page.getByRole('button', { pressed: true })).toContainText('书架');
  });

  test('3 个 tab 全部可见且可点击', async ({ page }) => {
    const tabbar = page.getByRole('navigation');
    for (const label of ROOT_TABS) {
      await expect(tabbar.getByRole('button', { name: label })).toBeVisible();
    }
  });

  test('切换到对话 tab', async ({ page }) => {
    await page.getByRole('navigation').getByRole('button', { name: '对话' }).click();
    await expect(page.getByRole('button', { pressed: true })).toContainText('对话');
  });

  test('切换到应用 tab', async ({ page }) => {
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
    await expect(page.getByRole('button', { pressed: true })).toContainText('应用');
  });

  test('来回切换保持状态', async ({ page }) => {
    const nav = page.getByRole('navigation');
    await nav.getByRole('button', { name: '对话' }).click();
    await expect(page.getByRole('button', { pressed: true })).toContainText('对话');
    await nav.getByRole('button', { name: '应用' }).click();
    await expect(page.getByRole('button', { pressed: true })).toContainText('应用');
    await nav.getByRole('button', { name: '书架' }).click();
    await expect(page.getByRole('button', { pressed: true })).toContainText('书架');
  });
});
