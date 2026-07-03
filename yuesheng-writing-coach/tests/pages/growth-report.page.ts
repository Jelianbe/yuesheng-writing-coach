/**
 * GrowthReportPage / TrainingPlanPage — 子页 Page Object
 *
 * 通用子页结构(隐藏 TabBar,显示返回箭头 + 标题 + 内容)
 *
 * Sprint 19 重划后,只剩 2 个子页:成长报告 / 训练计划
 */

import { Locator, expect, Page } from '@playwright/test';
import { BasePage } from './base.page';

const SUB_PAGE_TITLES = [
  '成长报告',
  '训练计划',
] as const;

export type SubPageTitle = typeof SUB_PAGE_TITLES[number];

export class GrowthReportPage extends BasePage {
  // ─── Locators ───

  protected expectedTitle: SubPageTitle = '成长报告';

  get navbarTitle(): Locator {
    return this.page.getByRole('heading', { name: this.expectedTitle, level: 1 });
  }

  get loadingPlaceholder(): Locator {
    return this.page.getByText('数据加载中…');
  }

  // ─── Assertions ───

  async expectOnSubPage(): Promise<void> {
    await expect(this.navbarTitle).toBeVisible();
    // TabBar 在子页面应隐藏
    await expect(this.tabBar).toHaveCount(0);
  }

  async expectLoadingPlaceholder(): Promise<void> {
    await expect(this.loadingPlaceholder).toBeVisible();
  }

  // ─── 工厂方法:创建指定标题的子页 Page ───

  static forTitle(page: Page, title: SubPageTitle): GrowthReportPage {
    const inst = new GrowthReportPage(page);
    inst.expectedTitle = title;
    return inst;
  }
}
