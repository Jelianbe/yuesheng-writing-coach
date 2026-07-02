/**
 * GrowthReportPage 成长报告子页
 *
 * @regression 标签:占位页结构验证
 */

import { test, expect } from '@playwright/test';
import { GrowthReportPage } from '../../pages/growth-report.page';

test.describe('GrowthReportPage 成长报告 @regression', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
    await page.getByText('成长报告', { exact: true }).first().click();
  });

  test('显示成长报告标题', async ({ page }) => {
    const report = GrowthReportPage.forTitle(page, '成长报告');
    await report.expectOnSubPage();
  });

  test('TabBar 隐藏', async ({ page }) => {
    await expect(page.getByRole('navigation')).toHaveCount(0);
  });

  test('显示返回按钮', async ({ page }) => {
    const backButton = page.locator('header, [class*="navbar"]').first().getByRole('button').first();
    await expect(backButton).toBeVisible();
  });

  test('显示加载占位文本(等对接 store 后会变为数据)', async ({ page }) => {
    await expect(page.getByText('数据加载中…')).toBeVisible();
  });
});
