/**
 * BookshelfPage 书架页
 *
 * @critical 标签:核心功能
 *
 * Sprint 39 增强:弹窗创建 + 新版空态文案 + header 按钮
 */

import { test, expect } from '@playwright/test';

test.describe('BookshelfPage 书架 @critical', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('书架 tab 初始激活并显示空状态', async ({ page }) => {
    await expect(page.getByRole('button', { pressed: true })).toContainText('书架');
    await expect(page.getByRole('heading', { name: '书架', level: 1 })).toBeVisible();
    await expect(page.getByText('暂无作品,点击右上角 + 创建')).toBeVisible();
  });

  test('navbar 显示搜索和新建按钮', async ({ page }) => {
    const header = page.locator('header').first();
    await expect(header.getByRole('button', { name: '搜索' })).toBeVisible();
    await expect(header.getByRole('button', { name: '新建作品' })).toBeVisible();
  });

  test('点击新建按钮打开弹窗(浏览器无 electronAPI 时不报错)', async ({ page }) => {
    // 点击 navbar 中的新建按钮
    await page.getByRole('button', { name: '新建作品' }).click();

    // 弹窗出现
    await expect(page.getByRole('heading', { name: '新建作品' })).toBeVisible();
    await expect(page.getByPlaceholderText('作品名称 *')).toBeVisible();

    // 填入名称并点击创建（create IPC 会优雅降级）
    await page.getByPlaceholderText('作品名称 *').fill('测试作品');
    await page.getByRole('button', { name: '创建' }).click();

    // 弹窗应关闭（即使 IPC 失败）
    await expect(page.getByRole('heading', { name: '新建作品' })).not.toBeVisible();
  });

  test('搜索按钮切换搜索栏', async ({ page }) => {
    // 初始搜索栏隐藏
    await expect(page.getByPlaceholderText('搜索作品名或类型…')).not.toBeVisible();

    // 点击搜索按钮 → 显示
    await page.getByRole('button', { name: '搜索' }).click();
    await expect(page.getByPlaceholderText('搜索作品名或类型…')).toBeVisible();

    // 再次点击 → 隐藏
    await page.getByRole('button', { name: '搜索' }).click();
    await expect(page.getByPlaceholderText('搜索作品名或类型…')).not.toBeVisible();
  });
});
