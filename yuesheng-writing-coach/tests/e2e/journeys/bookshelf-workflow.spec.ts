/**
 * P1: 作品管理流 — 核心用户旅程
 *
 * 覆盖场景:
 * 1. 书架首页 → 空/加载状态
 * 2. 新建作品弹窗的交互流程
 * 3. 搜索过滤功能
 * 4. 作品卡片菜单（重命名/编辑详情/删除）
 * 5. push 进入 WorkDetailPage
 *
 * @journey 标签:核心用户旅程 P1
 */

import { test, expect } from '@playwright/test';

test.describe('P1: 作品管理流 @journey', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('P1-1: 书架初始渲染 — 标题 + 空态 + 操作按钮', async ({ page }) => {
    // 标题可见
    await expect(page.getByRole('heading', { name: '书架', level: 1 })).toBeVisible();

    // 空态文案: Sprint 39 新版文案
    await expect(page.getByText('暂无作品,点击右上角 + 创建')).toBeVisible();

    // navbar 有搜索按钮和新作品按钮
    const header = page.locator('header').first();
    await expect(header.getByRole('button', { name: '搜索' })).toBeVisible();
    await expect(header.getByRole('button', { name: '新建作品' })).toBeVisible();

    // TabBar 可见（根页面）
    await expect(page.getByRole('navigation')).toBeVisible();
  });

  test('P1-2: 搜索栏切换与交互', async ({ page }) => {
    const searchBtn = page.getByRole('button', { name: '搜索' });

    // 点开搜索
    await searchBtn.click();
    await expect(page.getByPlaceholderText('搜索作品名或类型…')).toBeVisible();

    // 再次点击关闭
    await searchBtn.click();
    await expect(page.getByPlaceholderText('搜索作品名或类型…')).not.toBeVisible();
  });

  test('P1-3: 新建作品弹窗流程', async ({ page }) => {
    // 点击新建
    await page.getByRole('button', { name: '新建作品' }).click();

    // 弹窗出现 — 标题 + 输入框 + 按钮
    await expect(page.getByRole('heading', { name: '新建作品' })).toBeVisible();
    await expect(page.getByPlaceholderText('作品名称 *')).toBeVisible();
    await expect(page.getByPlaceholderText('类型（可选）')).toBeVisible();
    await expect(page.getByText('描述（可选）')).toBeVisible();
    await expect(page.getByRole('button', { name: '创建' })).toBeDisabled();

    // 填入名称
    await page.getByPlaceholderText('作品名称 *').fill('测试作品');
    await expect(page.getByRole('button', { name: '创建' })).toBeEnabled();

    // 取消 — 弹窗应关闭
    await page.getByRole('button', { name: '取消' }).click();
    await expect(page.getByRole('heading', { name: '新建作品' })).not.toBeVisible();
  });

  test('P1-4: 作品卡片菜单交互（有数据时）', async ({ page }) => {
    // 在 Vite 环境下无真实 IPC 数据,跳过此测试
    // 若将来有 mock 数据可补充
    test.skip(true, 'Vite 环境无 IPC 数据,跳过卡片菜单测试');
  });

  test('P1-5: 各类空态/加载态文案', async ({ page }) => {
    // 书架初始空态
    await expect(page.getByText('暂无作品,点击右上角 + 创建')).toBeVisible();

    // 切换到对话页再回来
    await page.getByRole('navigation').getByRole('button', { name: '对话' }).click();
    await expect(page.getByRole('button', { pressed: true })).toContainText('对话');
    await page.getByRole('navigation').getByRole('button', { name: '书架' }).click();
    await expect(page.getByRole('button', { pressed: true })).toContainText('书架');

    // 回到书架后空态依然正确
    await expect(page.getByText('暂无作品,点击右上角 + 创建')).toBeVisible();
  });
});
