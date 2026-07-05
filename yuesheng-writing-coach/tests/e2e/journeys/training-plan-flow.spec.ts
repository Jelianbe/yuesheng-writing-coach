/**
 * P3: 训练计划流 — 核心用户旅程
 *
 * 覆盖场景:
 * 1. 书架 → 应用 → 训练计划 完整导航路径
 * 2. 子页渲染（标题 / 返回按钮 / TabBar 隐藏）
 * 3. 返回导航回到应用页
 * 4. 子页间切换
 * 5. 应用页图标渲染
 *
 * @journey 标签:核心用户旅程 P3
 */

import { test, expect } from '@playwright/test';

test.describe('P3: 训练计划流 @journey', () => {
  test('P3-1: 书架 → 应用 → 训练计划 完整导航', async ({ page }) => {
    // 起点:书架
    await page.goto('/');
    await expect(page.getByRole('heading', { name: '书架', level: 1 })).toBeVisible();

    // 切到应用
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
    await expect(page.getByRole('heading', { name: '应用', level: 1 })).toBeVisible();

    // 应用页图标可见
    await expect(page.getByText('成长报告', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('训练计划', { exact: true }).first()).toBeVisible();

    // 进入训练计划子页
    await page.getByText('训练计划', { exact: true }).first().click();

    // 子页渲染:标题 + 返回按钮 + TabBar 隐藏
    await expect(page.getByRole('heading', { name: '训练计划', level: 1 })).toBeVisible();
    const backButton = page.locator('header').first().getByRole('button').first();
    await expect(backButton).toBeVisible();
    await expect(page.getByRole('navigation')).toHaveCount(0);
  });

  test('P3-2: 训练计划返回应用页', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
    await page.getByText('训练计划', { exact: true }).first().click();

    // 确认在子页
    await expect(page.getByRole('heading', { name: '训练计划', level: 1 })).toBeVisible();

    // 点击返回
    const backButton = page.locator('header').first().getByRole('button').first();
    await backButton.click();

    // 回到应用页
    await expect(page.getByRole('heading', { name: '应用', level: 1 })).toBeVisible();
    await expect(page.getByRole('navigation')).toBeVisible();
  });

  test('P3-3: 子页间切换:成长报告 → 训练计划', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();

    // 进入成长报告
    await page.getByText('成长报告', { exact: true }).first().click();
    await expect(page.getByRole('heading', { name: '成长报告', level: 1 })).toBeVisible();

    // pop 回应用
    const backButton = page.locator('header').first().getByRole('button').first();
    await backButton.click();
    await expect(page.getByRole('heading', { name: '应用', level: 1 })).toBeVisible();

    // 再进训练计划
    await page.getByText('训练计划', { exact: true }).first().click();
    await expect(page.getByRole('heading', { name: '训练计划', level: 1 })).toBeVisible();
  });

  test('P3-4: 训练计划 — 数据加载状态', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
    await page.getByText('训练计划', { exact: true }).first().click();

    // Vite 环境无 IPC,显示空态或加载态（任一即可）
    const loadingOrEmpty = page.getByText('暂无阶段数据').or(page.getByText('加载中…'));
    await expect(loadingOrEmpty.first()).toBeVisible();
  });

  test('P3-5: 应用页完整渲染', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();

    // 所有子页图标
    await expect(page.getByText('成长报告', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('训练计划', { exact: true }).first()).toBeVisible();

    // 工具项
    await expect(page.getByText('设定管理', { exact: true })).toBeVisible();

    // 设置分割标题
    await expect(page.getByText('设置', { exact: true })).toBeVisible();
  });
});
