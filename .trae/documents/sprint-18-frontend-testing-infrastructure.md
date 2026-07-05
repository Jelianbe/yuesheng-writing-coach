# 前端测试基础设施搭建

## Context

项目当前仅 34 个 vitest 单元测试，主要覆盖后端业务逻辑（IPM/状态机/证据系统等），**前端渲染层、E2E 用户旅程、a11y 合规、视觉回归** 全部缺失。

用户在 Sprint 18 端到端验证时发现：
- dev 启动需手动 `verify 5 pages`（vite + 浏览器人工）
- 没有任何自动化保护阻止 UI 退化
- a11y 现状：5 个核心页面均无 `aria-label`、`role`、`lang` 属性
- 视觉变化完全靠"肉眼对比"，无法量化

**目标**：建立完整的测试基础设施，让代码变更可以自动验证 UI 行为、a11y 合规、视觉一致性。

## 设计方案

### Phase 1：基础配置（4 文件）

1. **安装 Playwright 浏览器**（一次性，~150MB）
   ```bash
   npx playwright install chromium
   ```

2. **新建 `playwright.config.ts`**：参考项目已有 `.trae/rules/playwright-e2e/SKILL.md` 规范
   - `testDir: './tests/e2e'`
   - `baseURL: 'http://localhost:5173'`
   - `webServer.command: 'npm run dev:vite'`（Vite only,不需要 Electron）
   - `projects`: chromium + mobile-chrome (Pixel 5)
   - 截图配置：仅失败时自动截图，视觉基线按需

3. **修改 `package.json` scripts**
   - `test:e2e`: `playwright test`
   - `test:e2e:ui`: `playwright test --ui`
   - `test:a11y`: `playwright test --grep @a11y`
   - `test:visual`: `playwright test --grep @visual --update-snapshots`
   - `test:visual:check`: `playwright test --grep @visual`
   - `test:all`: 跑 vitest + playwright

4. **新增依赖**：`@axe-core/playwright ^4.10.0`
   - axe-core 通过 Playwright 注入到页面
   - 扫描所有 WCAG 2.1 AA 违规

5. **修改 `.gitignore`**：
   - `test-results/`
   - `playwright-report/`
   - `playwright/.auth/`
   - 保留：`tests/e2e/**/*-snapshots/`（视觉基线入仓）

### Phase 2：E2E 测试（按 SKILL 规范）

**目录结构**：
```
tests/
  e2e/
    navigation/
      tabbar.spec.ts          @smoke
      routing.spec.ts         @smoke
    pages/
      bookshelf.spec.ts       @critical
      apps.spec.ts            @critical
      growth-report.spec.ts   @regression
    a11y/
      all-pages.spec.ts       @a11y
    visual/
      snapshots.spec.ts       @visual
  pages/                       # Page Object Model
    base.page.ts
    bookshelf.page.ts
    apps.page.ts
    growth-report.page.ts
  fixtures/
    app.fixture.ts
  utils/
    test-data.ts
    helpers.ts
```

**关键规范**（沿用 SKILL.md）：
- 选择器优先级：`getByRole` > `getByLabel` > `getByText` > `getByTestId`
- 测试标签：`@smoke` / `@critical` / `@regression` / `@a11y` / `@visual`
- 不使用 `waitForTimeout`，靠 auto-waiting
- 每个 spec 独立，beforeEach 重置路由

**关键测试用例**：
- `tabbar.spec.ts`：3 tab 切换、`aria-current="page"` 检查
- `routing.spec.ts`：push 隐藏 TabBar、pop 恢复、成长报告/训练计划/技法库/素材库 4 子页可达
- `bookshelf.spec.ts`：空状态显示、"新建学习项目"按钮点击 → 创建流程
- `apps.spec.ts`：4 图标 + 3 工具项渲染
- `growth-report.spec.ts`：返回按钮、加载占位

### Phase 3：axe-core a11y 审计

`tests/e2e/a11y/all-pages.spec.ts`：
```typescript
const PAGES = [
  { name: '书架', tab: '书架' },
  { name: '对话', tab: '对话' },
  { name: '应用', tab: '应用' },
  { name: '成长报告', path: 'growth-report' },
  { name: '训练计划', path: 'training-plan' },
  { name: '技法库', path: 'technique-library' },
  { name: '素材库', path: 'material-library' },
];

for (const p of PAGES) {
  test(`a11y: ${p.name} 无 WCAG 严重违规 @a11y`, async ({ page }, testInfo) => {
    // 导航到页面
    // 注入 axe.run()
    // 断言：violations.filter(v => v.impact === 'critical' || v.impact === 'serious').length === 0
    // 附件：完整 violation 列表写到 testInfo.outputPath
  });
}
```

**预期发现**（基于摸底）：
- 缺少 `lang="zh-CN"` 在根 html
- 缺少 `aria-label` 在多个图标按钮
- 颜色对比度可能不足（暖紫 + 浅灰文字）
- div onClick 缺 keyboard 支持

**输出**：
- `test-results/a11y-report.json` - 详细违规
- 控制台 summary：critical/serious/moderate 计数
- 不阻断 CI，但产出报告供后续修

### Phase 4：视觉回归基线

用 Playwright 内置 `toHaveScreenshot()`（不需额外库）：

`tests/e2e/visual/snapshots.spec.ts`：
- 3 个根页：书架/对话/应用
- 1 个子页：成长报告
- 每个页面在 mobile-chrome (Pixel 5) 视口下截图
- maxDiffPixels: 100（容忍微差异）

**首次运行**：`npm run test:visual` 创建 baseline
**后续运行**：`npm run test:visual:check` 对比 baseline

### Phase 5：CI 集成

修改 `ci` script：
```json
"ci": "npm run sync:ipc && npm run typecheck && npm run test && npm run test:e2e && npm run scan:hardcode && npm run build"
```

注意：CI 跑 E2E 前需先 `npx playwright install --with-deps chromium`。

## 关键文件清单

**新建**（14 个）：
- `playwright.config.ts`
- `tests/e2e/navigation/tabbar.spec.ts`
- `tests/e2e/navigation/routing.spec.ts`
- `tests/e2e/pages/bookshelf.spec.ts`
- `tests/e2e/pages/apps.spec.ts`
- `tests/e2e/pages/growth-report.spec.ts`
- `tests/e2e/a11y/all-pages.spec.ts`
- `tests/e2e/visual/snapshots.spec.ts`
- `tests/pages/base.page.ts`
- `tests/pages/bookshelf.page.ts`
- `tests/pages/apps.page.ts`
- `tests/pages/growth-report.page.ts`
- `tests/fixtures/app.fixture.ts`
- `tests/utils/test-data.ts`

**修改**（3 个）：
- `package.json`：加 5 个 scripts + 1 个 dep
- `.gitignore`：加 3 个排除
- `tsconfig.json`：包含 `tests/` 目录（如果当前未包含）

## 复用与依赖

- **复用 SKILL**：完全遵循 `.trae/rules/playwright-e2e/SKILL.md` 规范（已在项目里）
- **复用 a11y 工具**：项目已有 `scripts/check-a11y-colors.ts`（颜色合规扫描），axe-core 是补充
- **依赖**：`@playwright/test 1.60.0` 已装，只需装 `@axe-core/playwright` + 下载 chromium
- **不要重复**：不写自定义测试运行器、不引入 Cypress/Storybook

## 实施顺序

1. `npx playwright install chromium`（先下载）
2. 写 `playwright.config.ts` + 修改 `package.json` + `.gitignore`
3. 写 fixtures + base page + 3 个 page object
4. 写 E2E specs（5 个 spec）
5. 装 `@axe-core/playwright` + 写 a11y spec
6. 跑 `test:visual` 创建 baseline
7. 全量跑一次确认全绿
8. 修改 `ci` script 集成 E2E
9. 提交（按 R-016 规范）

## 验证

**门禁**（必须全绿）：
```bash
npm run typecheck              # 0 错误
npm run test                   # vitest 全绿
npm run test:e2e               # playwright 全绿（chromium）
npm run test:a11y              # 无 critical/serious violation
```

**人工验证**：
- 启动 `npm run dev:vite`，访问 http://localhost:5173
- 用 Playwright UI 模式 `npx playwright test --ui` 浏览 trace
- 视觉 baseline 文件可在 PR diff 中查看

**不覆盖**（明确声明）：
- IPC 真实数据流（需 Electron 窗口，单独 E2E）
- 主进程业务逻辑（已有 34 个 vitest）
- 性能/内存（不属于 E2E 范围）

## 风险与权衡

| 决策 | 理由 |
|:-----|:-----|
| **Vite only 而非 Electron 全栈跑 E2E** | 启动快 10x，渲染层独立可测；IPC 需 Electron 由 vitest + manual 覆盖 |
| **chromium + mobile-chrome 两个 project** | 桌面/移动双视口，移动端是核心场景；3+ 浏览器会让 CI 太慢 |
| **a11y 不阻断 CI** | 现状会有大量 violation，第一次跑会全部失败；先报告，后续按优先级修 |
| **视觉基线入仓** | 让 PR 能 diff 截图，避免外部服务依赖（Chromatic/Percy） |
| **不引入 axe-core CLI** | 用 Playwright 注入运行时跑更准确，覆盖 SPA 动态路由 |
