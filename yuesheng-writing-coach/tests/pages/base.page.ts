/**
 * BasePage — 所有 Page Object 的基类
 *
 * 规范:.trae/rules/playwright-e2e/SKILL.md (Base Page Class)
 *
 * 职责:
 * - 通用导航 + 等待
 * - 通用截图
 * - TabBar 共享操作(书架/对话/应用 3 个根页都依赖)
 */

import { Page, Locator, expect } from '@playwright/test';

export abstract class BasePage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  // ─── 通用导航 ───

  async goto(path = '/'): Promise<void> {
    await this.page.goto(path);
  }

  async waitForPageLoad(): Promise<void> {
    await this.page.waitForLoadState('networkidle');
  }

  async getTitle(): Promise<string> {
    return this.page.title();
  }

  async takeScreenshot(name: string): Promise<Buffer> {
    return this.page.screenshot({ path: `test-results/screenshots/${name}.png`, fullPage: true });
  }

  // ─── TabBar 共享操作 ───

  /**
   * 移动端 375px 容器内的 TabBar(根页面才显示,子页面隐藏)
   * 选择器:nav > button[aria-label]
   */
  get tabBar(): Locator {
    return this.page.getByRole('navigation').getByRole('button');
  }

  /**
   * 当前活跃 tab(aria-current="page")
   */
  get activeTab(): Locator {
    return this.page.getByRole('button', { pressed: true });
  }

  async switchTab(label: '书架' | '对话' | '应用'): Promise<void> {
    await this.tabBar.filter({ hasText: label }).click();
    await expect(this.activeTab).toContainText(label);
  }

  // ─── 子页面通用 ───

  /**
   * 返回按钮(子页面 navbar 左侧的 ← 图标按钮)
   */
  get backButton(): Locator {
    return this.page.getByRole('button').filter({ has: this.page.locator('svg').first() }).first();
  }

  async goBack(): Promise<void> {
    await this.backButton.click();
  }

  // ─── 工具方法 ───

  /**
   * 等待文本出现(代替 waitForTimeout)
   */
  async waitForText(text: string | RegExp): Promise<void> {
    await expect(this.page.getByText(text).first()).toBeVisible();
  }
}
