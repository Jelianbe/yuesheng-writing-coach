/**
 * app.fixture — 共享 E2E Fixtures
 *
 * 自动加载 Page Object 实例,避免每个 spec 重复 new。
 *
 * 用法:
 *   test('bookshelf 显示', async ({ bookshelfPage }) => {
 *     await bookshelfPage.expectEmptyState();
 *   });
 */

import { test as base } from '@playwright/test';
import { BookshelfPage } from '../pages/bookshelf.page';
import { AppsPage } from '../pages/apps.page';

type AppFixtures = {
  bookshelfPage: BookshelfPage;
  appsPage: AppsPage;
};

export const test = base.extend<AppFixtures>({
  bookshelfPage: async ({ page }, use) => {
    const bookshelfPage = new BookshelfPage(page);
    await bookshelfPage.goto();
    await use(bookshelfPage);
  },

  appsPage: async ({ page }, use) => {
    const appsPage = new AppsPage(page);
    await use(appsPage);
  },
});

export { expect } from '@playwright/test';
