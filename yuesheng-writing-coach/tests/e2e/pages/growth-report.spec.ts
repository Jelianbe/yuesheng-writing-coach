/**
 * GrowthReportPage 成长报告子页
 *
 * @regression 标签:Sprint 19 Issue 19-3 实装,接入 SQLite 真实数据
 * - 4 状态卡片(已掌握/进步中/稳定/需关注)
 * - 5 维能力雷达图
 * - 趋势总览 + 症候详情列表
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

  test('页面渲染：Electron 环境显示 4 状态卡片+雷达图，Vite 环境显示空/错误状态', async ({ page }) => {
    await expect(page.getByRole('heading', { name: '成长报告' })).toBeVisible();
    // Vite 浏览器环境无 electronAPI,IPC 会失败,显示加载占位/空态
    // Electron 环境会真实渲染雷达图与状态卡片
    const radar = page.getByTestId('growth-radar');
    const radarCount = await radar.count();
    if (radarCount > 0) {
      // Electron 环境:雷达图存在
      await expect(radar).toBeVisible();
      await expect(page.getByTestId('growth-status-cards')).toBeVisible();
      await expect(page.getByTestId('growth-trend-summary')).toBeVisible();
    } else {
      // Vite 环境:加载占位或空态（任一即可）
      const placeholder = page.getByTestId('growth-loading').or(page.getByTestId('growth-empty'));
      await expect(placeholder.first()).toBeVisible();
    }
  });
});
