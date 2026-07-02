/**
 * PageStackRouter 路由 — push/pop + 4 个子页可达
 *
 * @smoke 标签:核心路由功能
 */

import { test, expect } from '@playwright/test';
import { SUB_PAGES } from '../../utils/test-data';

test.describe('PageStackRouter 路由 @smoke', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    // 切到"应用" tab(子页入口)
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
  });

  test('4 个子页都可从应用页 push 进入', async ({ page }) => {
    for (const sub of SUB_PAGES) {
      // 重置:回到应用页
      await page.goto('/');
      await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();

      // 点击子页图标
      await page.getByText(sub.label, { exact: true }).first().click();

      // 验证子页加载(标题 + TabBar 隐藏)
      await expect(page.getByRole('heading', { name: sub.label, level: 1 })).toBeVisible();
      await expect(page.getByRole('navigation')).toHaveCount(0);
    }
  });

  test('push 后子页显示返回按钮和加载占位', async ({ page }) => {
    await page.getByText('成长报告', { exact: true }).first().click();

    await expect(page.getByRole('heading', { name: '成长报告' })).toBeVisible();
    // 返回按钮是 navbar 内第一个 button
    const backButton = page.locator('header, [class*="navbar"]').first().getByRole('button').first();
    await expect(backButton).toBeVisible();
    await expect(page.getByText('数据加载中…')).toBeVisible();
  });

  test('点击返回按钮 pop 回应用页', async ({ page }) => {
    await page.getByText('训练计划', { exact: true }).first().click();
    await expect(page.getByRole('heading', { name: '训练计划' })).toBeVisible();

    // 点击返回
    const backButton = page.locator('header, [class*="navbar"]').first().getByRole('button').first();
    await backButton.click();

    // 验证回到应用页
    await expect(page.getByRole('heading', { name: '应用' })).toBeVisible();
    await expect(page.getByRole('navigation')).toBeVisible();
  });
});
