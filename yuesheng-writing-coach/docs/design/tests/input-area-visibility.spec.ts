import { test, expect } from '@playwright/test';
import path from 'path';

const HTML_FILE = path.resolve(__dirname, '../preview-warm-v2.html');
const FILE_URL = `file://${HTML_FILE}`;

test.describe('对话栏可见性验证', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(FILE_URL);
  });

  test('初始加载时输入框应该可见', async ({ page }) => {
    const inputArea = page.locator('.input-area');
    await expect(inputArea).toBeVisible();
    
    const box = await inputArea.boundingBox();
    expect(box).not.toBeNull();
    expect(box.y).toBeLessThan(800);
    
    const textarea = page.locator('#messageInput');
    await expect(textarea).toBeVisible();
    await textarea.fill('测试输入');
    await expect(textarea).toHaveValue('测试输入');
  });

  test('点击新建会话后输入框仍然可见', async ({ page }) => {
    await page.click('.btn-new-chat');
    await expect(page.locator('#welcomeEmpty.visible')).toBeVisible();
    
    const inputArea = page.locator('.input-area');
    await expect(inputArea).toBeVisible();
    
    const textarea = page.locator('#messageInput');
    await expect(textarea).toBeVisible();
    await textarea.fill('新会话测试');
    await expect(textarea).toHaveValue('新会话测试');
  });

  test('加载已有会话后输入框仍然可见', async ({ page }) => {
    await page.click('.chat-item');
    await expect(page.locator('#chatArea')).toBeVisible();
    
    const inputArea = page.locator('.input-area');
    await expect(inputArea).toBeVisible();
    
    const textarea = page.locator('#messageInput');
    await expect(textarea).toBeVisible();
    await textarea.fill('已有会话测试');
    await expect(textarea).toHaveValue('已有会话测试');
  });

  test('发送消息后输入框仍然可见', async ({ page }) => {
    await page.click('.chat-item');
    
    const textarea = page.locator('#messageInput');
    await textarea.fill('这是一条测试消息');
    await page.click('.input-send-btn');
    
    await expect(textarea).toBeVisible();
    await expect(textarea).toHaveValue('');
    
    await textarea.fill('第二条消息');
    await expect(textarea).toHaveValue('第二条消息');
  });

  test('切换侧边栏折叠状态后输入框仍然可见', async ({ page }) => {
    await page.click('#sidebarToggle');
    await expect(page.locator('.sidebar.collapsed')).toBeVisible();
    await expect(page.locator('.input-area')).toBeVisible();
    
    await page.click('#sidebarToggle');
    await expect(page.locator('.sidebar')).not.toHaveClass(/collapsed/);
    await expect(page.locator('.input-area')).toBeVisible();
  });

  test('切换右侧面板折叠状态后输入框仍然可见', async ({ page }) => {
    await page.click('#rightPanelToggle');
    await expect(page.locator('.right-panel.collapsed')).toBeVisible();
    await expect(page.locator('.input-area')).toBeVisible();
    
    await page.click('#rightPanelToggle');
    await expect(page.locator('.right-panel')).not.toHaveClass(/collapsed/);
    await expect(page.locator('.input-area')).toBeVisible();
  });
});
