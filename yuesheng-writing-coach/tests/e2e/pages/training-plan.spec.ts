/**
 * TrainingPlanPage 训练计划子页
 *
 * @regression 标签:已对接 SQLite (Sprint 19 Issue 19-2)
 */

import { test, expect } from '@playwright/test';
import { GrowthReportPage } from '../../pages/growth-report.page';

test.describe('TrainingPlanPage 训练计划 @regression', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
    await page.getByText('训练计划', { exact: true }).first().click();
  });

  test('显示训练计划标题', async ({ page }) => {
    const report = GrowthReportPage.forTitle(page, '训练计划');
    await report.expectOnSubPage();
  });

  test('TabBar 隐藏', async ({ page }) => {
    await expect(page.getByRole('navigation')).toHaveCount(0);
  });

  test('显示返回按钮', async ({ page }) => {
    const backButton = page.locator('header').first().getByRole('button').first();
    await expect(backButton).toBeVisible();
  });

  test('页面渲染：Electron 环境显示 7 阶段，Vite 环境显示空/错误状态', async ({ page }) => {
    // 等待数据加载（无论成功失败）
    await expect(page.getByRole('heading', { name: '训练计划' })).toBeVisible();
    // Vite 浏览器环境无 electronAPI,IPC 会失败,显示空态/错误态
    // Electron 环境会真实渲染 7 个 article
    const articles = page.locator('article');
    const articleCount = await articles.count();
    if (articleCount > 0) {
      // Electron 环境:7 个阶段
      await expect(articles).toHaveCount(7);
      await expect(articles.first().getByRole('heading', { level: 2, name: '练眼' })).toBeVisible();
    } else {
      // Vite 环境:空态或错误态（任一即可）
      const emptyOrError = page.getByText('暂无阶段数据').or(page.getByText('加载中…'));
      await expect(emptyOrError.first()).toBeVisible();
    }
  });
});
