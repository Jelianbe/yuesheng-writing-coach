# 工作区分批提交/清理计划

## Context

### 当前状态
最近两个 commit 已提交（`ff64b2d` D-DEBT-28 + `d8ba88d` BL-23），但工作区仍堆积 292 个未提交改动（D 204 / M 42 / ?? 46）。这些是之前几次会话的混合遗留，未分批入仓，影响后续开发与 diff 评审。

### 本次目标
将 292 个未提交改动按"单一职责、可独立回退"原则分批提交，并保留必要的文档/计划文件不丢。

### 盘点结果
- **D (204)**: 主要在 `src/renderer/components/**`（上次桌面端归档 150 个）+ `src/renderer/components_archived/v1/**`（v1 历史归档）+ `src/renderer/components_archived/**`（archived 内部清理）
- **M (42)**: 散布在 `CHANGELOG.md` / `decision-log.md` / `App.tsx` / `variables.css` / `right-panel.store.ts` / `components_archived/**`（Sprint 17 Tailwind→CSS Modules 历史工作）/ `components_archived/v1/**`（v1 删除导致的引用调整）
- **?? (46)**: 新增的移动端 V1 / LLM 网关 / 意图路由 / 文档

### 关键设计原则
- **不混"重构/feat/chore/docs"** — 单一职责 commit
- **新模块独立成组** — LLM 网关 / 意图路由 / 移动端 V1 三组分别
- **归档/删除合并** — D 状态按主题合并（archived 整体 vs v1 archived），不分 8 个 commit
- **docs 与代码同组** — dev-docs 文档随主任务一起提交（保证 commit message 完整），但单独 docs 报告类独立

---

## 提交组（共 9 个 commit）

### Commit 1: `docs(release): v1.5.0 changelog + 移动端 V1 决策记录`
- **范围**: docs
- **文件**:
  - `CHANGELOG.md`（M — 已有 v1.5.0 条目）
  - `docs/decision-log.md`（M — D-049 移动端 V1 完工）
- **依据**: 文档先入库，确保后续 commit 的"为什么"有据可查
- **回退难度**: 低

### Commit 2: `feat(renderer): 移动端 V1 路由 + 5 页面 + 暖紫色板`
- **范围**: renderer
- **文件**:
  - `src/renderer/routing/**`（?? PageStackRouter + TabBar 容器）
  - `src/renderer/pages/**`（?? 5 页面：BookshelfPage / ConversationsPage / ProjectSpacePage / ChatPage / AppsPage）
  - `src/renderer/stores/page-stack.store.ts`（??）
  - `src/renderer/components/navigation/**`（?? TabBar + MoreMenu + 容器）
  - `src/renderer/styles/variables.css`（M — V3.0 暖紫柔棕色板）
  - `src/renderer/App.tsx`（M — 接入 PageStackRouter）
- **依据**: 移动端 V1 主体——前端重构的核心交付
- **依赖**: 无
- **回退难度**: 中（但前端路由整体性高，单文件回退可能引入运行时错误）

### Commit 3: `refactor(renderer): 归档桌面端组件 + 抽离 drawer-constants`
- **范围**: renderer
- **文件**:
  - `src/renderer/components/**` 删除（150 个 D，19 个目录）
  - `src/renderer/shared/drawer-constants.ts`（?? 新建）
  - `src/renderer/stores/right-panel.store.ts`（M — 改 import 路径）
- **依据**: 桌面端 → 移动端转换的最后清理。drawer-constants 移动是为了在 archived 引用时仍能正常 import
- **依赖**: 强依赖 Commit 2（移动端先有 router 才能删 AppShell）
- **回退难度**: 高（移动端先 commit 才能删桌面端；逆向回退易断引用）

### Commit 4: `chore(archive): 清理 v1 历史 + archived 内部引用同步`
- **范围**: archive
- **文件**:
  - `src/renderer/components_archived/v1/**` 删除（约 90 个 D）
  - `src/renderer/components_archived/**` 修改（M 状态约 30 个文件，主要是 Sprint 17 Tailwind→CSS Modules）
  - `src/renderer/components_archived/**` 内部删除（D 状态约 15 个）
- **依据**: v1 历史是更老的版本，归档内文件 Sprint 17 已部分改写为 tokens 风格。统一清理归档
- **依赖**: 弱依赖 Commit 3（drawer-constants 移动后 archived 内 import 路径才一致）
- **回退难度**: 中（archived 不在编译路径，回退影响小；但文件量大）

### Commit 5: `feat(renderer): shared 模块化（drawer-constants 共享）`
- **范围**: renderer
- **说明**: 此提交并入 Commit 3
- **状态**: 跳过（已在 Commit 3）

### Commit 6: `feat(ai): LLM 网关 + 技法加载器`
- **范围**: ai
- **文件**:
  - `src/main/shared/llm/**`（?? types/gateway/adapters/cache/middleware + 4 个测试）
  - `src/main/shared/services/llm-gateway.service.ts`（??）
  - `src/main/shared/services/technique-loader.ts`（??）
  - `src/main/test/setup.ts`（?? vitest setup）
- **依据**: Sprint 18 P0 提前实现——LLM 容错/限流/重试/缓存的基础设施
- **依赖**: 无
- **回退难度**: 中（基础设施类，未来开发会引用，删除成本高）

### Commit 7: `feat(ai): 意图路由（intent-router）`
- **范围**: ai
- **文件**:
  - `src/main/domains/03-teaching/chat/intent-router.ts`（??）
  - `src/main/domains/03-teaching/chat/intent-router.types.ts`（??）
  - `src/main/domains/03-teaching/chat/__tests__/**`（??）
  - `src/main/domains/01-diagnosis/orchestrator/rule-based-diagnosis-engine.ts`（??）
  - `resources/config/intent-router-keywords.json`（??）
- **依据**: 用户消息类型分发到不同处理路径（重构自原 LLM 直接处理）
- **依赖**: 弱依赖 Commit 6（可能用 LLM 网关）
- **回退难度**: 中

### Commit 8: `docs(architecture): 移动端 V1 方案 + 用户旅程 + 架构图谱`
- **范围**: docs
- **文件**:
  - `dev-docs/architecture/mobile-v1-plan.md`（??）
  - `dev-docs/architecture/user-journey-v1.md`（??）
  - `dev-docs/architecture/project-arch-map.md`（??）
  - `dev-docs/architecture/frontend-reconstruction-v1.md`（??）
  - `dev-docs/designs/prd-v1-three-layer-architecture.md`（??）
  - `dev-docs/designs/mobile-v1-ipc-plan.md`（??）
  - `dev-docs/designs/intent-router-v1.md`（??）
  - `dev-docs/designs/sprint-18-plan.md`（??）
  - `dev-docs/tasks/phase-a-tasks.md`（??）
  - `dev-docs/tasks/intent-router-tasks.md`（??）
  - `dev-docs/designs/backend-audit-report-2026-06-24.md`（??）
  - `dev-docs/designs/early-vision-gap-analysis-2026-06-24.md`（??）
  - `dev-docs/research/**`（5 个 ??）
  - `dev-docs/architecture/`（4 个 ??）
- **依据**: 设计文档集中入库
- **依赖**: 无
- **回退难度**: 低

### Commit 9: `docs(design): 设计稿 HTML + 健康扫描`
- **范围**: docs
- **文件**:
  - `docs/design/demol/full-app-flow-V1.html`（??）
  - `docs/design/demol/teaching-loop-V1.html`（??）
  - `docs/reports/daily-health/scan_2026-06-23.json`（??）
  - `../.trae/documents/`（不提交，留在本地）
- **依据**: 设计稿与日扫报告
- **依赖**: 无
- **回退难度**: 低

---

## 跳过/不提交

- **`../.trae/documents/`**（计划文件目录） — 本地 AI 工作产物，不入仓

---

## Critical Files（按 commit 列出精确路径）

### Commit 1
- `CHANGELOG.md`
- `docs/decision-log.md`

### Commit 2
- `src/renderer/routing/index.ts`
- `src/renderer/routing/PageStackRouter.tsx`
- `src/renderer/routing/PageStackRouter.module.css`
- `src/renderer/pages/index.ts`
- `src/renderer/pages/BookshelfPage.tsx`
- `src/renderer/pages/BookshelfPage.module.css`
- `src/renderer/pages/ConversationsPage.tsx`
- `src/renderer/pages/ConversationsPage.module.css`
- `src/renderer/pages/ProjectSpacePage.tsx`
- `src/renderer/pages/ProjectSpacePage.module.css`
- `src/renderer/pages/ChatPage.tsx`
- `src/renderer/pages/ChatPage.module.css`
- `src/renderer/pages/AppsPage.tsx`
- `src/renderer/pages/AppsPage.module.css`
- `src/renderer/stores/page-stack.store.ts`
- `src/renderer/components/navigation/TabBar.tsx`
- `src/renderer/components/navigation/TabBar.module.css`
- `src/renderer/components/navigation/MoreMenu.tsx`
- `src/renderer/components/navigation/MoreMenu.module.css`
- `src/renderer/styles/variables.css`
- `src/renderer/App.tsx`

### Commit 3
- `src/renderer/components/**`（整目录删除，~150 个）
- `src/renderer/shared/drawer-constants.ts`
- `src/renderer/stores/right-panel.store.ts`

### Commit 4
- `src/renderer/components_archived/v1/**`（整目录删除，~90 个）
- `src/renderer/components_archived/**` 修改（M + D，~45 个）

### Commit 6
- `src/main/shared/llm/**`（整个 LLM 网关 + 4 个测试）
- `src/main/shared/services/llm-gateway.service.ts`
- `src/main/shared/services/technique-loader.ts`
- `src/main/test/setup.ts`

### Commit 7
- `src/main/domains/03-teaching/chat/intent-router.ts`
- `src/main/domains/03-teaching/chat/intent-router.types.ts`
- `src/main/domains/03-teaching/chat/__tests__/**`
- `src/main/domains/01-diagnosis/orchestrator/rule-based-diagnosis-engine.ts`
- `resources/config/intent-router-keywords.json`

### Commit 8
- `dev-docs/architecture/**`（4 个）
- `dev-docs/designs/{prd-v1, mobile-v1-ipc-plan, intent-router-v1, sprint-18-plan, backend-audit, early-vision-gap}.md`（6 个）
- `dev-docs/tasks/**`（2 个）
- `dev-docs/research/**`（5 个）

### Commit 9
- `docs/design/demol/full-app-flow-V1.html`
- `docs/design/demol/teaching-loop-V1.html`
- `docs/reports/daily-health/scan_2026-06-23.json`

---

## 复用现有工具/模式

- **commit message 格式**: 已遵守 R-016（`<type>(<scope>): <subject>`）
- **`npx tsx` 跑 scripts**: 已用，跑 docs check 工具不需要
- **每个 commit 后跑 `npm run typecheck && npm run test`** — 验证无回归

---

## Verification

### 每个 commit 后的标准验证
```bash
cd d:\ai-teacher\yuesheng-writing-coach

# 1. typecheck
npm run typecheck         # 必须 0 错误

# 2. test（注意：dev:electron 在跑时会锁 better-sqlite3，需先停 dev server）
npm run test              # 48 文件 / 683 测试全绿
```

### 关键 checkpoint
- **Commit 2 后**: 浏览器打开 http://localhost:5173/ 应能看到 5 页面移动端
- **Commit 3 后**: 启动 dev server，UI 仍正常
- **Commit 4 后**: archived 不在编译路径，无需额外验证
- **Commit 6 后**: vitest 应跑过 LLM 网关 4 个测试
- **Commit 7 后**: vitest 应跑过 intent-router 测试
- **Commit 8/9 后**: 纯文档，无功能影响

### 最终总验证
```bash
git log --oneline -10                              # 看到所有 9 个 commit
git status                                         # 应清空或只剩 .trae/documents/
npm run typecheck && npm run test && npm run lint  # 三门禁全绿
```

---

## 风险评估

| 风险 | 概率 | 缓解 |
|------|------|------|
| `right-panel.store.ts` 在 Commit 3 改路径后 archived 引用断裂 | 低 | Commit 4 跟在 Commit 3 之后，archived 修改已含 import 调整 |
| Commit 2 跑 typecheck 不过（移动端页面未引用某旧 store） | 中 | typecheck 跑不过即停止，先修 |
| Commit 6 LLM 网关有循环依赖（与 intent-router 互引） | 中 | 顺序 6→7，Commit 7 引用 Commit 6 时 typecheck 会暴露 |
| 大量删除 D 文件在 Commit 3/4 期间搞错 | 低 | 分批前用 `git rm --cached` 预演，确认无误再 commit |
| 历史 archived 文件 Sprint 17 改动有未独立成组的（如 OnboardingFlow M + v1 引用） | 中 | 全部归到 Commit 4，回退时整体回退 |

### 回退方案
- 任何 commit 可独立 `git revert HEAD` 或 `git reset --hard HEAD~1`（commit 前先确认）

---

## 执行顺序（依赖图）

```
Commit 1 (docs) ──────┐
                       │
Commit 6 (LLM) ───────┼─→ Commit 7 (intent-router)
                       │
                       ├─→ Commit 2 (mobile v1) ──→ Commit 3 (归档 + drawer) ──→ Commit 4 (v1 archive)
                       │                              ↓
                       │                            (none)
                       └─→ Commit 8 (docs) ──→ Commit 9 (设计稿)
```

**简化**：实际上 Commit 1/2/6/8/9 无依赖，可并发思路；3/4/7 强依赖前序。建议**串行**按编号执行（避免 git add 选文件时混乱）：
1 → 2 → 3 → 4 → 6 → 7 → 8 → 9

每个 commit 完成后做 typecheck+test，再下一个。

---

## 范围外（明确不做）

- 不动 `../.trae/documents/`（本地 AI 工作产物）
- 不重构未提交文件（只搬运不优化）
- 不为意图路由或 LLM 网关新建 ADR（任务外）
- 不改 README / CLAUDE.md
- 不跑 audit（D-DEBT-29 另开任务）
