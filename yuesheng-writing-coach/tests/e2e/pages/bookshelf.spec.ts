/**
 * BookshelfPage 书架页
 *
 * @critical 标签:核心功能
 */

import { test, expect } from '@playwright/test';

test.describe('BookshelfPage 书架 @critical', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('书架 tab 初始激活并显示空状态', async ({ page }) => {
    await expect(page.getByRole('button', { pressed: true })).toContainText('书架');
    await expect(page.getByRole('heading', { name: '书架', level: 1 })).toBeVisible();
    await expect(page.getByText('暂无作品,点击下方按钮创建')).toBeVisible();
  });

  test('显示"+ 新建学习项目"虚线按钮', async ({ page }) => {
    const createBtn = page.getByText('+ 新建学习项目');
    await expect(createBtn).toBeVisible();
    await expect(createBtn).toHaveCSS('border-style', 'dashed');
  });

  test('navbar 显示搜索和新建按钮', async ({ page }) => {
    const navbar = page.locator('header, [class*="navbar"]').first();
    await expect(navbar.getByRole('button')).toHaveCount(2);
  });

  test('点击新建按钮触发 window.prompt(浏览器无 electronAPI 时不报错)', async ({ page }) => {
    // 拦截 prompt 防止弹窗
    page.on('dialog', async (dialog) => {
      expect(dialog.type()).toBe('prompt');
      await dialog.accept('测试作品');
    });

    const createBtn = page.getByText('+ 新建学习项目');
    await createBtn.click();

    // 因为浏览器无 electronAPI,create 失败但不抛错(typedInvoke 优雅降级)
    // 等待一下让 store action 执行完成
    await page.waitForTimeout(500);
  });
});
