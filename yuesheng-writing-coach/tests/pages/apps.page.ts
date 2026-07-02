/**
 * AppsPage — 应用中心 Page Object
 *
 * 4 个图标(成长报告/训练计划/技法库/素材库)+ 工具列表
 * div onClick 导航 → push 路由
 */

import { Locator, expect } from '@playwright/test';
import { BasePage } from './base.page';

const GRID_ITEMS = [
  { label: '成长报告', route: 'growth-report' },
  { label: '训练计划', route: 'training-plan' },
  { label: '技法库', route: 'technique-library' },
  { label: '素材库', route: 'material-library' },
] as const;

const TOOL_ITEMS = ['结构拆解', '设定管理', '导出作品'] as const;

export class AppsPage extends BasePage {
  // ─── Locators ───

  get navbarTitle(): Locator {
    return this.page.getByRole('heading', { name: '应用', level: 1 });
  }

  get gridItem(): (label: string) => Locator {
    return (label: string) => this.page.getByText(label, { exact: true }).first();
  }

  get toolItem(): (label: string) => Locator {
    return (label: string) => this.page.getByText(label, { exact: true }).first();
  }

  // ─── Actions ───

  async clickGridItem(label: typeof GRID_ITEMS[number]['label']): Promise<void> {
    await this.gridItem(label).click();
  }

  // ─── Assertions ───

  async expectOnApps(): Promise<void> {
    await expect(this.navbarTitle).toBeVisible();
    await expect(this.tabBar).toBeVisible();
  }

  async expectAllGridItemsVisible(): Promise<void> {
    for (const item of GRID_ITEMS) {
      await expect(this.gridItem(item.label)).toBeVisible();
    }
  }

  async expectAllToolItemsVisible(): Promise<void> {
    for (const label of TOOL_ITEMS) {
      await expect(this.toolItem(label)).toBeVisible();
    }
  }
}
