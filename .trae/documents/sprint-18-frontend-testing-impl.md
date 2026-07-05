# Sprint 18 — 前端测试基础设施落地

> **计划文件**: `d:\ai-teacher\.trae\documents\sprint-18-frontend-testing-impl.md`
> **状态**: 待用户审批
> **关联文档**: `sprint-18-frontend-testing-infrastructure.md`(已通过的设计方案)

## 1. Summary

完成 Sprint 18 前端测试基础设施的端到端落地:运行现有 Playwright/E2E/a11y/视觉套件摸底,修复阻碍测试通过和 a11y critical 违规的代码问题,创建首批视觉回归基线,扩展 a11y 扫描到 components 层,最后把 `test:e2e + test:a11y` 串入 `ci` 脚本。

工作区根: `d:\ai-teacher\yuesheng-writing-coach/`

## 2. Current State Analysis

### 2.1 已完成(无需再做)

| 模块 | 状态 | 关键文件 |
|------|------|---------|
| Playwright 配置 | ✅ Firefox 桌面 + Mobile | `playwright.config.ts` |
| Page Object 基类 | ✅ BasePage + 4 子页 | `tests/pages/*.ts` |
| E2E 测试 | ✅ 5 个 spec | `tests/e2e/{navigation,pages,a11y,visual}/*.spec.ts` |
| a11y 扫描集成 | ✅ axe-core + WCAG 2.1 AA | `tests/e2e/a11y/all-pages.spec.ts` |
| 视觉回归套件 | ✅ toHaveScreenshot 配 100px 容差 | `tests/e2e/visual/snapshots.spec.ts` |
| 浏览器 | ✅ Firefox 1522 已下载 | `C:\Users\月笙如歌\AppData\Local\ms-playwright\firefox-1522` |
| npm scripts | ✅ 7 个新脚本 | `package.json:30-36` |

### 2.2 已识别的待修复问题

#### 2.2.1 代码 a11y 问题(阻碍 a11y 测试 critical 违规)

| 文件 | 行 | 问题 | 修复方向 |
|------|---|------|---------|
| `BookshelfPage.tsx:62-71` | Search/Plus 装饰性 SVG,无交互 role | 拆分为 `<button aria-label>` |
| `BookshelfPage.tsx:124-136` | 虚线"新建学习项目"是 `div onClick` | 改 `<button>` |
| `BookshelfPage.tsx:92-120` | 书卡是 `div onClick` | 改 `<button>` 或加 `role="button" tabIndex={0}` + Enter handler |
| `ConversationsPage.tsx:62-68` | Plus 装饰性 SVG 有点击事件 | 改为 `<button aria-label="新建对话">` |
| `ConversationsPage.tsx:84-110` | 对话卡片是 `div onClick` | 改 `<button>` |
| `AppsPage.tsx:50-71` | 4 个图标是 `div onClick` | 改 `<button>` |
| `AppsPage.tsx:83-98` | 工具项是 `div` 不可点 | 改 `<button>` 或仅 div(若占位) |
| `BookshelfPage.tsx / ConversationsPage.tsx` | Navbar 是 `<div>` 无 `<header>` landmark | 包 `<header role="banner">` |
| `AppsPage.tsx:45-72` | 4 网格容器无 `role="group" aria-label` | 加语义化标签 |

#### 2.2.2 测试用例需对齐代码

| spec | 假设 | 实际 | 处理 |
|------|------|------|------|
| `bookshelf.spec.ts:26-29` | navbar 有 2 个 `<button>` | 当前无 button | 修代码 + 测试均可工作 |
| `bookshelf.spec.ts:31-44` | 点击触发 `window.prompt` | 需确保 Plus 元素可点 | 修代码后通过 |
| `a11y/all-pages.spec.ts` | 假设基本无 critical | 预计 5-10 critical | 修复后重跑 |

#### 2.2.3 视觉基线未创建

`snapshots/` 目录尚无基线,需执行 `npm run test:visual` 生成。

#### 2.2.4 components 层未覆盖 a11y 扫描

`all-pages.spec.ts` 仅覆盖 5 个页面,未扫 8+ 个 components(`TabBar` / `MoreMenu` / `InputBar` / `WelcomeGuide` 等)。需扩展为 component-level fixtures。

## 3. Proposed Changes

### 3.1 Phase 1: 摸底运行(2 步)

**目的**: 看清当前状态,获取 a11y 报告数据基线。

**步骤**:
1. `cd d:\ai-teacher\yuesheng-writing-coach; npm run test:e2e -- --project=firefox-mobile --reporter=list 2>&1 | tail -100`
2. `cd d:\ai-teacher\yuesheng-writing-coach; npm run test:a11y 2>&1 | tail -80`

**输出**: E2E 失败列表 + a11y JSON 报告(写入 `test-results/`)

### 3.2 Phase 2: 修复阻碍性 a11y 违规(2 文件)

**目的**: 修复上面 2.2.1 中列出的 critical 违规。原则:
- 装饰性 SVG 不动
- 可交互元素必须是 `<button>` 或 `<a>`
- 列表/卡片用 `<button>` 全宽重置默认样式
- 弹窗/菜单用 `role="menu"` `role="menuitem"`(MoreMenu 已合规,不动)

**文件 1**: `src/renderer/pages/BookshelfPage.tsx`
- 改 Navbar div → `<header role="banner">`
- Search SVG → `<button aria-label="搜索">`
- Plus SVG → `<button aria-label="新建作品">`
- 虚线 div → `<button class="dashedCreate">`
- 书卡 div → `<button class="bookCard">`
- 全局样式 inline → 抽出到 `BookshelfPage.module.css`(避免 R-019 内联样式禁令,虽然项目实际允许页面级 inline)

**文件 2**: `src/renderer/pages/ConversationsPage.tsx`
- 改 Navbar div → `<header role="banner">`
- Plus SVG → `<button aria-label="新建对话">`
- 对话卡片 div → `<button>`

**文件 3**: `src/renderer/pages/AppsPage.tsx`
- 改 Navbar div → `<header role="banner">`
- 4 网格 div → `<button class="gridItem">`
- 工具项 div → 移除点击态保留静态,或加 `<button>`(等 Phase C 决定)

**门禁**: 重跑 `npm run test:a11y`,critical 违规 = 0

### 3.3 Phase 3: 修复书架/对话 Page Object + E2E 预期

**目的**: 让 E2E 真正能通过。BookshelfPage 修完后有真 button,page object 的 `getByRole('button')` 才能找到。

**改动**:
- `tests/pages/bookshelf.page.ts`: `searchButton` 改用 `getByRole('button', { name: '搜索' })`
- `tests/pages/bookshelf.page.ts`: `addButton` 改用 `getByRole('button', { name: '新建作品' })`
- `tests/pages/apps.page.ts`: `clickGridItem` 用 `getByRole('button', { name: label })`
- `tests/e2e/navigation/tabbar.spec.ts` 保持不动(原本就对)
- `tests/e2e/navigation/routing.spec.ts` 中返回按钮选择器需验证

**门禁**: `npm run test:e2e -- --project=firefox-mobile` 全绿

### 3.4 Phase 4: 创建视觉基线(1 步)

**命令**:
```bash
cd d:\ai-teacher\yuesheng-writing-coach; npm run test:visual
```

**产物**:
- `tests/e2e/visual/snapshots/desktop-firefox/root-书架.png`
- `tests/e2e/visual/snapshots/desktop-firefox/root-对话.png`
- `tests/e2e/visual/snapshots/desktop-firefox/root-应用.png`
- `tests/e2e/visual/snapshots/desktop-firefox/sub-growth-report.png`
- 同样 4 个 mobile-firefox 版本

**门禁**: 基线生成无错误;`npm run test:visual:check` 第二轮跑通

### 3.5 Phase 5: 扩展 a11y 到 components(1 新文件)

**目的**: 用户明确要求"全项目扫描(pages + components)"。

**新文件**: `tests/e2e/a11y/components.spec.ts`
- 覆盖: `TabBar`, `MoreMenu`, `InputBar`, `WelcomeGuide`, `MessageBubble`(ChatPage 内嵌)
- 策略: 通过 `page.setContent` 渲染 isolated HTML fixture + axe 扫描
- 或: 在每个页面 spec 末尾追加 component-level axe

**采用第二种**(更现实): 修改 `all-pages.spec.ts`,为每个 page 多扫一次 component 状态(打开 MoreMenu/有消息时)

**门禁**: 再次跑 `npm run test:a11y` 输出 0 critical/serious

### 3.6 Phase 6: 串入 CI 脚本

**文件**: `package.json`
- 修改 `scripts.ci` 末尾追加 `&& npm run test:e2e -- --project=firefox-mobile`(可选,因 E2E 慢,默认不串)
- 新增 `scripts.ci:full` 包含 E2E + a11y,留给 CI 触发
- 文档: `dev-docs/CI.md` 说明默认 `ci` 不含 E2E,需用 `ci:full`

**门禁**: `npm run typecheck && npm run test` 零错误

## 4. Files to Change / Create

| 类型 | 路径 | 操作 |
|------|------|------|
| 修改 | `src/renderer/pages/BookshelfPage.tsx` | div→button 改造 + header landmark |
| 修改 | `src/renderer/pages/ConversationsPage.tsx` | div→button 改造 + header landmark |
| 修改 | `src/renderer/pages/AppsPage.tsx` | div→button 改造 + header landmark |
| 修改 | `tests/pages/bookshelf.page.ts` | locator 重写 |
| 修改 | `tests/pages/apps.page.ts` | locator 重写 |
| 修改 | `tests/e2e/a11y/all-pages.spec.ts` | 增加 component-level 扫描点 |
| 修改 | `package.json` | ci 脚本扩展 |
| 新建 | `dev-docs/CI.md` | CI 触发说明 |
| 产物 | `tests/e2e/visual/snapshots/**/*.png` | 视觉基线 |

## 5. Assumptions & Decisions

1. **a11y 修复范围**: 仅修 critical/serious,moderate/minor 记录到 todo 不修
2. **页面级 inline style**: 保持现状不抽 CSS Module(R-019 在本项目实际豁免页面级 inline)
3. **E2E 默认不串 ci**: E2E 慢(30s+),只在 PR label 含 `e2e` 时触发
4. **视觉基线只覆盖 firefox-mobile**: 桌面版视觉基线价值低,移动端是核心场景
5. **测试不依赖 electronAPI**: 浏览器无 IPC 时通过 `success=false` 优雅降级,store 不抛错

## 6. Verification Checklist

执行完毕后必须验证:

```
□ Phase 1: E2E + a11y 摸底完成,报告存档到 test-results/
□ Phase 2: BookshelfPage/ConversationsPage/AppsPage 修复完成
  □ typecheck 通过 (npm run typecheck)
  □ 重跑 test:a11y critical=0
□ Phase 3: E2E 全绿
  □ npm run test:e2e -- --project=firefox-mobile 0 failed
□ Phase 4: 视觉基线生成
  □ npm run test:visual 0 failed
  □ npm run test:visual:check 0 failed (二轮)
□ Phase 5: a11y 扩展
  □ npm run test:a11y 0 critical/serious
□ Phase 6: CI 集成
  □ npm run ci (默认) 通过
  □ npm run ci:full 文档存在
```

## 7. Risk & Rollback

| 风险 | 影响 | 回退 |
|------|------|------|
| 页面重构引入新 bug | 中 | git revert 单个 commit |
| 视觉基线不准(微小差异) | 低 | `npm run test:visual` 重新生成 |
| Firefox 启动失败(环境) | 高 | 切换到 `chromium` project(需重新下载)|
| E2E 跑太久 CI timeout | 中 | 默认 `ci` 不含 E2E,`ci:full` 单独跑 |

## 8. Out of Scope

- Phase B(IPC 管道优化)、Phase C(交互优化)、D-DEBT-29(前端审计重跑)
- vitest 单元测试覆盖率提升
- 性能测试(Lighthouse/Web Vitals)
- 跨浏览器测试(只 Firefox)
- 桌面/平板 viewport
