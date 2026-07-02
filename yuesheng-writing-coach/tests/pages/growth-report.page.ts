/**
 * GrowthReportPage — 成长报告子页 Page Object
 *
 * 子页面(隐藏 TabBar,显示返回箭头 + 标题 + 占位内容)
 *
 * 其他 3 个子页面(TrainingPlan/TechniqueLibrary/MaterialLibrary)结构相同,
 * 此 Page 通用化用于覆盖 4 个子页
 */

import { Locator, expect, Page } from '@playwright/test';
import { BasePage } from './base.page';

const SUB_PAGE_TITLES = [
  '成长报告',
  '训练计划',
  '技法库',
  '素材库',
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
