# QA 测试基线文档 — Sprint 41（已完成）

> 目标：建立自动化测试程序 + 内容审核标准基线，精确捕获问题位置和复现步骤。

## 一、覆盖标准

### 1.1 分层覆盖目标

| 层级 | 覆盖率目标 | 当前状态 | 说明 |
|:-----|:----------:|:---------|:-----|
| **主进程 IPC Handler** | ≥ 60% 核心通道 | ✅ `progress.handler` 已覆盖 6 个 SQL 路径 | 基于 better-sqlite3 `:memory:` |
| **渲染进程 Store** | ≥ 80% 新增 store | ✅ `training-plan.store` 10 用例，`writing-progress.store` 5 用例 | 含异常/空数据/Loading |
| **渲染进程 Pages** | 100% 页面渲染 | ✅ WorkDetailPage 13 用例，BookshelfPage 9 用例，GrowthReportPage 6 用例 | 含空态/数据态/错误态/导航 |
| **核心用户旅程** | 3 条 E2E 路径 | ✅ P1 作品管理、P2 诊断训练、P3 训练计划 | Playwright Vite 环境 |
| **TypeScript** | 零 error | ✅ 通过 | `npx tsc --noEmit` |
| **Lint** | 零 error，warnings ≤ 300 | ✅ 通过（13 warnings） | `npx eslint --max-warnings 300` |

### 1.2 门禁流程

```
提交前 → typecheck → test → lint → 门禁全部通过 → 可合并
```

完整门禁命令：

```bash
npm run typecheck && npx vitest run && npx eslint --max-warnings 300 src/
```

---

## 二、测试资产清单（Sprint 41 完成时）

| 维度 | 数量 | 变化 |
|:-----|:----:|:-----|
| Vitest 测试文件 | **97 个** | 新增 4 个（+4） |
| Tests 用例 | **1172 个** | 新增 30+ 个 |
| Playwright E2E 文件 | **11 个** | 新增 3 个（journeys），更新 1 个（bookshelf） |
| Playwright E2E 用例 | **~55 个** | 新增 14 个（journeys）+ 更新 4 个（bookshelf） |

### 2.1 已覆盖模块

#### Pages（8/8 全部覆盖）

- **BookshelfPage** — 空态/加载/错误/搜索/新建弹窗/卡片点击跳转（9 Vitest 用例 + 4 E2E 用例）
- **ChatPage** — 消息渲染/发送/训练触发（13 用例）
- **ConversationsPage** — 会话列表/新建/导航（8 用例）
- **GrowthReportPage** — 加载态/空态/数据态（雷达图/状态卡片/症候列表）/错误态/返回/挂载调用（6 用例）
- **ProjectSpacePage** — 项目空间/章节/统计（20 用例）
- **SettingsPage** — API Key 配置/保存（8 用例）
- **TrainingPlanPage** — 自定义计划/阶段渲染（8 用例）
- **WorkDetailPage** — 元数据/统计卡片/章节 CRUD/编辑弹窗（13 用例）— **新增**

#### Stores（7 个核心 Store 覆盖）

- `chat.store` — 消息管理/AI 交互
- `training.store` — 训练流程（含 22 用例的 retro 测试）
- `progress.store` — 进度数据
- `training-plan.store` — **新增** CRUD/异常（10 用例）
- `writing-progress.store` — **新增** 5 个 IPC 路径（5 用例）
- `manuscript.store` — 在 BookshelfPage/WorkDetailPage 测试中覆盖
- `chapter.store` — 在 WorkDetailPage 测试中覆盖

#### IPC Handler（集成测试，SQLite :memory:）

- `progress.handler` — **新增** 6 个 SQL 聚合路径（字数/连续天数/训练统计/柱状图/空数据库）

#### E2E（Playwright + Vite）

- **Pages**: bookshelf, apps, growth-report, training-plan, snapshots（移动端视觉基线）
- **Navigation**: tabbar 切换, routing push/pop
- **A11y**: axe-core 扫描所有页面
- **Journeys**: 3 条核心用户旅程 — **新增**
  - P1: 书架交互流（渲染/搜索/弹窗/导航）
  - P2: 诊断训练流（对话页渲染/输入/空态/切换）
  - P3: 训练计划流（导航/渲染/返回/子页切换）

### 2.2 已知缺口（Sprint 41 范围外）

| 模块 | 缺口说明 | 建议后续 |
|:-----|:---------|:---------|
| `manuscript.store` | 无独立单元测试 | 如需单独验证可补充 |
| `chapter.store` | 无独立单元测试 | 同上 |
| `page-stack.store` | 无独立单元测试 | 低优先级，路由测试覆盖 |
| `config.store` | 无独立单元测试 | 低优先级 |
| `session.store` | 无独立单元测试 | 低优先级 |
| `training-plan.handler` IPC | 无独立集成测试 | 如 plan 相关 IPC 增改可补充 |
| 其他 IPC Handler | 未覆盖 | 渐进式补充 |
| WorkDetailPage 编辑弹窗保存 | 已覆盖保存后调用 update | 补充保存后 UI 变化的断言 |
| TrainingPlanPage 自定义计划 | UI 测试已覆盖 | 补充 IPC 降级路径测试 |
| GrowthReportPage 进度总览 | 基础渲染已覆盖 | 可补充区块展开/收起细节 |

---

## 三、新增测试用例（已实现）

### 3.1 writing-progress.store.ts（5 个用例 ✅）

| 编号 | 用例 | 状态 |
|:----:|:-----|:----:|
| WP-1 | fetchOverview 成功 | ✅ |
| WP-2 | fetchOverview 异常 | ✅ |
| WP-3 | fetchOverview 数据为空 | ✅ |
| WP-4 | loading 状态 | ✅ |
| WP-5 | 连续两次 fetch | ✅ |

### 3.2 training-plan.store.ts（10 个用例 ✅）

| 编号 | 用例 | 状态 |
|:----:|:-----|:----:|
| TP-1 | fetchPlans 成功 | ✅ |
| TP-2 | fetchPlan 成功 | ✅ |
| TP-3 | createPlan 成功 | ✅ |
| TP-4 | deletePlan 成功 | ✅ |
| TP-5 | addItem 成功 | ✅ |
| TP-6 | removeItem 成功 | ✅ |
| TP-7 | updateItemStatus 成功 | ✅ |
| TP-8 | fetchAvailableChallenges 成功 | ✅ |
| TP-9 | clearError 清除错误 | ✅ |
| TP-10 | 异常路径 | ✅ |

### 3.3 progress.handler.ts — IPC 集成测试（6 个 SQL 路径 ✅）

| 编号 | 用例 | 状态 |
|:----:|:-----|:----:|
| PH-1 | 字数统计 | ✅ |
| PH-2 | 连续天数 | ✅ |
| PH-3 | 连续天数中断 | ✅ |
| PH-4 | 训练统计 | ✅ |
| PH-5 | 每日柱状图 | ✅ |
| PH-6 | 空数据库 | ✅ |

### 3.4 WorkDetailPage（13 个用例 ✅）

| 编号 | 用例 | 状态 |
|:----:|:-----|:----:|
| WD-1 | 未指定 id | ✅ |
| WD-2 | 作品不存在 | ✅ |
| WD-3 | 加载态 | ✅ |
| WD-4 | 渲染元数据 | ✅ |
| WD-5 | 渲染统计卡片 | ✅ |
| WD-6 | 章节列表为空 | ✅ |
| WD-7 | 章节列表有数据 | ✅ |
| WD-8 | 新增章节 | ✅ |
| WD-9 | 删除章节 | ✅ |
| WD-10a | 编辑弹窗打开 | ✅ |
| WD-10b | 编辑弹窗保存后调用 update | ✅ |
| WD-11 | 返回按钮调用 pop | ✅ |
| WD-12 | 加载失败显示错误 | ✅ |

### 3.5 E2E 核心用户旅程（3 条路径，14 个用例 ✅）

| 路径 | 用例 | 状态 |
|:-----|:-----|:----:|
| **P1: 作品管理流** | P1-1 书架初始渲染 / P1-2 搜索栏切换 / P1-3 新建弹窗 / P1-5 空态切换 | ✅ |
| **P2: 诊断训练流** | P2-1 对话页渲染 / P2-2 输入与发送 / P2-3 消息空态 / P2-4 切换保持 | ✅ |
| **P3: 训练计划流** | P3-1 完整导航 / P3-2 返回 / P3-3 子页切换 / P3-4 数据加载 / P3-5 应用页渲染 | ✅ |

---

## 四、测试数据工厂（已实现）

测试中使用的模式（参考各 test 文件）：

```typescript
// manuscript mock factory — 在 BookshelfPage 测试中使用
function makeManuscript(overrides: Partial<{ id: string; title: string; genre: string }> = {}) {
  return {
    id: overrides.id ?? 'm-1',
    title: overrides.title ?? '测试作品',
    genre: overrides.genre ?? '小说',
    description: '',
    status: 'active' as const,
    created_at: Date.now(),
    updated_at: Date.now(),
    sort_order: 0,
  };
}
```

---

## 五、错误捕获与报告规范

### 5.1 Vitest 测试失败信息

所有测试失败时自动输出：

- 测试文件路径和行号
- 断言期望值 vs 实际值（diff 格式）
- DOM 快照（组件测试）
- 调用栈

### 5.2 Playwright 报告

```bash
npm run test:e2e          # 运行 E2E（需 Vite dev server 先行）
npm run test:report       # 查看 HTML 报告
```

Playwright 配置自动生成（失败时）：
- Trace (Playwright Trace Viewer)
- Screenshot
- Video

### 5.3 手动复现步骤记录

遇到 Bug 时，开发人员应记录：

```
## [Bug] 问题简述

**环境**: Electron / Vite 浏览器
**操作步骤**:
1. 进入 XX 页面
2. 点击 XX 按钮
3. 输入 XX 内容
4. 观察到 XX 现象（错误/崩溃/白屏）

**预期行为**: 
**实际行为**:
**截图/日志**:
```

---

## 六、运行命令

```bash
# ── 完整 QA 门禁 ──
npm run typecheck && npx vitest run && npx eslint --max-warnings 300 src/

# ── 仅 Vitest ──
npx vitest run                                           # 全部
npx vitest run src/renderer/pages/__tests__/BookshelfPage.test.tsx  # 单文件
npx vitest run --reporter=verbose                        # 详细输出

# ── E2E (需先启动 dev server: npm run dev:vite) ──
npm run test:e2e                                         # 全部 E2E
npx playwright test tests/e2e/journeys/                  # 仅用户旅程

# ── 覆盖率报告 ──
npm run test:coverage

# ── Playwright 报告 ──
npm run test:report
```
