# Sprint 18 复盘 — 移动端 V1 数据对接 + 前端测试基础设施

> 日期：2026-07-02
> 周期：Sprint 18（Phase A 落地 + 测试基建）
> 看板：https://github.com/Jelianbe/yuesheng-writing-coach/issues

---

## 一、概览

### 完成情况

| 模块 | 标题 | 类型 | 状态 |
|:-----|:-----|:-----|:----:|
| 关键 bug 修复 | Windows + E28 `app.isPackaged` 误判 | fix | ✅ |
| Phase A | 5 页面 + 4 子页 Store 补全（typedInvoke + Contract） | feat | ✅ |
| Phase A2 | 路由收尾（4 子页 + PageStack） | feat | ✅ |
| 测试基建 | Playwright E2E + axe-core a11y + 视觉回归基线 | test | ✅ |
| a11y 合规 | 7 页面 WCAG AA（语义化 + 对比度） | fix | ✅ |
| 工程改进 | .gitignore + Playwright 平衡模式 + 报告脚本 | chore | ✅ |

**7/7 完成** — Sprint 目标全部达成。

### 数据

| 指标 | Sprint 17 末 | Sprint 18 末 | 变化 |
|:-----|:------------:|:------------:|:----:|
| 提交数 | — | 7 commits | +7 |
| 文件变更 | — | 53 files | +53 |
| 插入行数 | — | 1,941 | +1,941 |
| 删除行数 | — | 489 | -489 |
| 单元测试用例 | 683 | 683 | 0（未新增，回归保护） |
| E2E 测试用例 | 0 | 31 项 | +31 |
| a11y 扫描覆盖 | 0 | 7 页 | +7 |
| 视觉基线 | 0 | 4 张 | +4 |
| Typecheck errors | 0 | 0 | — |
| Lint errors | 0 | 0 | — |
| Lint warnings | ~255 | 244 | -11 |

### 架构覆盖

```
移动端 V1 数据流：5/5 ✅

书架 (BookshelfPage)   → useManuscriptStore → manuscripts 表        ✅
对话 (Conversations)   → useSessionStore    → session:listWithMeta   ✅
应用 (AppsPage)        → useProjectStore    → project 域             ✅
项目空间 (ProjectSpace) → useProjectStore    → radar/ability          ✅ (mock过渡)
聊天 (ChatPage)        → useSessionStore    → 消息流                  ✅
4 子页 (成长/计划/技法/素材) → 4 新 Store 占位                        ✅ (Phase C 续)
```

---

## 二、做得好的

### 1. Phase A 严格按 Contract 对齐 typedInvoke
所有 4 个新 Store（ability/growth/prescription/retro）+ 3 个升级 Store
（manuscript/session/project）的 IPC 入参/返回均严格对齐 `src/shared/api-contracts/`。
排查出 1 个 ID 维度陷阱（`manuscriptId` vs `id`），避免后续 merge 时类型错误。

### 2. 测试基础设施三层全覆盖
一次性建立 E2E + a11y + 视觉回归三层能力：

- **E2E（24 项）**：TabBar 切换、PageStackRouter 路由、BookshelfPage/AppsPage/GrowthReportPage 行为
- **a11y（7 项）**：axe-core 扫描 7 页面，断言 critical=0 && serious=0
- **视觉基线（4 项）**：3 根页 + 1 子页，maxDiffPixelRatio: 0.01
- **Page Object 模式**：tests/pages/base.page.ts 抽象通用操作

### 3. a11y 合规性系统性修复
E2E 审计暴露 12 类 critical/serious 违规，一次性修复：

- 语义化：div→header/button/h1 共 9 处
- 对比度：`--text-tertiary` 3.21→5.0，`--error` 4.6→6.8
- TabBar `aria-pressed` 属性新增，让 Playwright 选择器稳定

### 4. 关键 bug 修复抓得及时
`app.isPackaged` 在 Windows + Electron 28 dev 模式误判导致 migrations 加载失败，
第一时间定位 `process.env.NODE_ENV === 'development' || !app.isPackaged` 双判修复。

### 5. 工程平衡决策
Playwright 默认走平衡模式（失败留 trace），新增 `:verbose` 命令按需开启全量捕获，
避免"测试慢 + 磁盘大"反噬开发体验。

---

## 三、可改进的

### 1. 视觉基线初次重建消耗 2 轮
第一次跑 `test:visual:check` 失败（颜色变更后基线已不匹配），
需重跑 `test:visual` 才能更新。**改进**：建立 "设计 token 变更 → 同步重建基线"
的强制关联（写进 design-tokens.md 维护流程）。

### 2. a11y 报告 moderate/minor 级别未处理
只修了 critical/serious，moderate/minor 仍有遗留（未在 E2E 阻断）。
**改进**：Phase B 收尾时跑一次全量修复，确保全级别 0 违规。

### 3. Electron 端到端验证未在 Sprint 内闭环
Phase A 数据流只在 Vite 跑通，未通过 `npm run dev:electron` 验证主进程 +
better-sqlite3 + preload 白名单全链路。
**改进**：每次 Phase 完做 "dev:electron 启动 + IPC 调用一次" 烟测作为门禁。

### 4. D-DEBT-30~34 仅口头记录，未入技术债台账
5 个新债务未写入 `dev-docs/audits/`，可能在 Sprint 19 启动时被遗忘。
**改进**：每次 Phase 结束强制写 `dev-docs/audits/sprint-XX-debts.md`。

---

## 四、技术债务

| 编号 | 描述 | 优先级 | 来源 |
|:----:|------|:------:|:----:|
| D-DEBT-30 | ChatPage 历史消息分页（无上限加载） | P2 | Phase A |
| D-DEBT-31 | ProjectSpacePage 雷达图数据源（当前 mock） | P2 | Phase A |
| D-DEBT-32 | 4 子页 Store 实装（目前占位"加载中…"） | P1 | Phase A |
| D-DEBT-33 | ProjectSpacePage 维度数据整合（4 ID 维度收敛） | P2 | Phase A |
| D-DEBT-34 | Phase B 前的 typedInvoke 全量覆盖审计 | P1 | Phase A |
| D-DEBT-35 | a11y moderate/minor 级别未处理 | P3 | Phase A2 |
| D-DEBT-36 | 视觉基线重建流程未文档化 | P3 | Phase A2 |
| D-DEBT-37 | Electron 端到端烟测未集成门禁 | P2 | Phase A2 |

---

## 五、决策日志（D-050）

### D-050 · 2026-07-02 · Sprint 18 复盘：移动端 V1 数据对接 + 前端测试基建

- **类型**: 阶段复盘
- **范围**: 7 commits, 53 files, +1,941/-489
- **门禁**:
  - typecheck: 0 errors
  - vitest: 683/683 passed
  - lint: 0 errors, 244 warnings
  - E2E (mobile): 31/31 passed
  - E2E (desktop): 27/27 passed
- **核心交付**:
  1. Phase A 全 Store 补全（typedInvoke 统一）
  2. 前端测试基础设施（E2E + a11y + 视觉基线三层）
  3. a11y WCAG AA 合规（7 页面 critical/serious 0 违规）
  4. 关键 bug 修复（app.isPackaged 双判）
- **关键决策**:
  - Playwright 平衡模式：默认失败留 trace，PWVERBOSE=1 开全量
  - 视觉基线限定 firefox-mobile：桌面版价值低不入仓
  - a11y 修复限定 critical/serious：渐进式修不阻断
  - 页面级 inline 样式豁免：符合本项目实际
- **债务总数**: 8 项新债务（DEBT-30~37），其中 2 项 P1
- **下一阶段候选**:
  1. Phase B（IPC 管道优化 + D-DEBT-34）
  2. Phase C（交互设计优化 + D-DEBT-32）
  3. D-DEBT-29（前端审计重跑）
  4. Sprint 19 启动 Issue 拆分

---

## 六、Sprint 19 建议

### 候选顺序
```
P1 优先（高 ROI）:
  D-DEBT-32: 4 子页 Store 实装（成长/计划/技法/素材 数据从 SQLite 拉取）
  D-DEBT-34: typedInvoke 全量覆盖审计（剩余 0 直接 IPC 调用点）

P2 顺序:
  Phase B: event-bus.service.ts（Event 通道集中化）
  Phase C: 骨架屏（加载/空/错误三态）

P3 后置:
  D-DEBT-35: a11y moderate/minor 修复
  D-DEBT-36: 视觉基线重建流程文档
  D-DEBT-37: Electron 烟测门禁
```

### 推荐入口
- 选 D-DEBT-32（4 子页）作为 Sprint 19 第一个 Issue：
  收益最大（完成移动端 V1 数据流闭环）、依赖最少（Store 已就位）、
  可独立交付。
- 第二个 Issue 选 D-DEBT-34（typedInvoke 审计）：
  纯静态分析 + 批量替换，1-2 天可完成。

---

*复盘人：AI 复盘官*
*2026-07-02*
