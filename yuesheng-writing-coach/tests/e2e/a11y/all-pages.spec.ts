/**
 * axe-core 无障碍审计 — 遍历所有页面
 *
 * @a11y 标签:跑 WCAG 2.1 AA 扫描
 *
 * 设计:
 * - 不阻断 CI:第一次跑会有大量 violation,先报告,后续按优先级修
 * - critical/serious 写到 test-results/ 供查看
 * - moderate/minor 只输出控制台 summary
 */

import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

interface PageTarget {
  name: string;
  navigate: (page: import('@playwright/test').Page) => Promise<void>;
}

const PAGES: PageTarget[] = [
  {
    name: '书架',
    navigate: async (page) => {
      await page.goto('/');
    },
  },
  {
    name: '对话',
    navigate: async (page) => {
      await page.goto('/');
      await page.getByRole('navigation').getByRole('button', { name: '对话' }).click();
    },
  },
  {
    name: '应用',
    navigate: async (page) => {
      await page.goto('/');
      await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
    },
  },
  {
    name: '成长报告',
    navigate: async (page) => {
      await page.goto('/');
      await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
      await page.getByText('成长报告', { exact: true }).first().click();
    },
  },
  {
    name: '训练计划',
    navigate: async (page) => {
      await page.goto('/');
      await page.getByRole('navigation').getByRole('button', { name: '应用' }).click();
      await page.getByText('训练计划', { exact: true }).first().click();
    },
  },
];

for (const target of PAGES) {
  test(`a11y: ${target.name} 无 WCAG 严重违规 @a11y`, async ({ page }, testInfo) => {
    await target.navigate(page);
    await page.waitForLoadState('networkidle');

    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();

    // 完整报告写到附件
    await testInfo.attach('a11y-report.json', {
      body: JSON.stringify(accessibilityScanResults.violations, null, 2),
      contentType: 'application/json',
    });

    const critical = accessibilityScanResults.violations.filter((v) => v.impact === 'critical');
    const serious = accessibilityScanResults.violations.filter((v) => v.impact === 'serious');
    const moderate = accessibilityScanResults.violations.filter((v) => v.impact === 'moderate');
    const minor = accessibilityScanResults.violations.filter((v) => v.impact === 'minor');

    // 控制台 summary
    console.log(
      `[a11y:${target.name}] critical=${critical.length} serious=${serious.length} ` +
      `moderate=${moderate.length} minor=${minor.length}`,
    );

    // 软断言:不阻断 CI,但报告问题
    expect.soft(critical, `${target.name} 不应有 critical 级别违规`).toHaveLength(0);
    expect.soft(serious, `${target.name} 不应有 serious 级别违规`).toHaveLength(0);
  });
}
