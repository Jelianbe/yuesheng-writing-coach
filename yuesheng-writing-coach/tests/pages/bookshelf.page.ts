/**
 * BookshelfPage — 书架首页 Page Object
 *
 * 选择器优先级:getByRole > getByText(div onClick 不能 getByRole)
 *
 * 注意:书架/对话/应用根页面显示 TabBar;子页面隐藏
 */

import { Locator, expect } from '@playwright/test';
import { BasePage } from './base.page';

export class BookshelfPage extends BasePage {
  // ─── Locators ───

  get navbarTitle(): Locator {
    return this.page.getByRole('heading', { name: '书架', level: 1 });
  }

  get searchButton(): Locator {
    return this.page.locator('header').first().getByRole('button').first();
  }

  get addButton(): Locator {
    return this.page.locator('header').first().getByRole('button').nth(1);
  }

  get createButton(): Locator {
    return this.page.getByText('+ 新建学习项目');
  }

  get loadingState(): Locator {
    return this.page.getByText('加载中…');
  }

  get emptyState(): Locator {
    return this.page.getByText('暂无作品,点击下方按钮创建');
  }

  get errorBanner(): Locator {
    return this.page.locator('[class*="color-error"]').first();
  }

  // ─── Actions ───

  async clickCreate(): Promise<void> {
    await this.createButton.click();
  }

  async clickAddButton(): Promise<void> {
    await this.addButton.click();
  }

  // ─── Assertions ───

  async expectOnBookshelf(): Promise<void> {
    await expect(this.navbarTitle).toBeVisible();
    await expect(this.tabBar).toBeVisible();
  }

  async expectEmptyState(): Promise<void> {
    await expect(this.emptyState).toBeVisible();
    await expect(this.createButton).toBeVisible();
  }
}
