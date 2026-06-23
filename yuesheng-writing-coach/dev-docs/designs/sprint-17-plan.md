# Sprint 17 Plan: 前端审计整改 + Sprint 16 验收闭环

> Issue 集：#28-#33 (6 P1) + 验收任务 (BL-22/BL-19)
> 依据: D-046 Sprint 16 Reflect + 2026-06-23 前端审计 (11/20)
> 上游: PR #24 (Sprint 16) 已合到 main @ 9ccd82d (v1.1.0)

## 现状分析

### Sprint 16 验收状态（PR 合 ≠ 计划验收）

PR #24 合并完成，本地门禁全绿（typecheck 0 / test 629 / lint 0），但 plan 6 条 DoD 中：
- ✅ #3 injectTechniquePool 过滤
- ✅ #4 降级到 3 步流
- ✅ #5 门禁
- ✅ #6 步数指示器
- ⏳ **#1 用户可走完五步流** — 受 BL-22 (better-sqlite3 dual target) 阻塞 Electron E2E
- ⏳ **#2 fillTemplate 覆盖 P001-P007** — 偏离原 plan (challengeId → CATEGORY)，需 ADR 解释

### 2026-06-23 前端审计发现（11/20 Acceptable）

| # | 严重度 | 问题 | Issue |
|:--:|:---:|---|:--:|
| 1 | **P0** | FiveStepFlow + 6 Step 组件无 CSS，className `flow-panel*` 全部裸 DOM | (P1-#28 相关) |
| 2 | P1 | CenterPanel Zustand 整 state 订阅 14 字段，训练 stream 触发全树 re-render | #28 |
| 3 | P1 | AppShell 收起栏 6 个 emoji 按钮违反 PRODUCT.md anti-reference | #29 |
| 4 | P1 | CenterPanel empty state 3 个 emoji | #30 |
| 5 | P1 | AppShell 硬编码 `#D6CEC0` + 拖拽 layout thrashing | #33 |
| 6 | P1 | Tailwind 工具类 + CSS Modules 混用 | #31 |
| 7 | P1 | FiveStepFlow 4 个测试 skip (核心禁用逻辑 0 覆盖) | #32 |
| - | P2 | 内联 style 7+ 文件、R-019 违规、ghost-card 风险 | (P1 backlog) |
| - | P2 | blockquote border-left 装饰条违反 codex 禁令 | (P1 backlog) |
| - | P2 | `--transition-bounce` token 残留 | (P1 backlog) |
| - | P3 | 注释引用未来 Sprint、aria-live 缺失 | (P1 backlog) |

### 现有债务（来自 D-046 / D-035）

- **BL-22** (P0 阻塞): better-sqlite3 单一目标，dev/Electron 二选一，需 electron-rebuild
- **BL-23** (P1): preload 共享白名单硬编码副本与 `shared/constants.ts` 需手动同步
- **BL-19** (P1): 7 个 workspace 组件文件未创建（Sprint 18 backlog，但 Sprint 17 至少要恢复 import）
- **D-DEBT-17** (P1): attitude 透传链路（T15-1 任务）

## 架构决策

### ADR-006: Sprint 17 范围锁定为「审计整改 + 验收闭环」

**背景**: 项目连续 Sprint 都在交付新功能，前端债务堆积到 11/20 分。Sprint 17 决定**暂停新功能**，专攻审计整改 + Sprint 16 验收。

**决策**:
1. **新功能全部暂停**（T15-1 attitude 透传、T15-2 conditions 字段、T15-3 A/B 灰度 全部推迟到 Sprint 18）
2. **6 个 P1 Issue 全部走完**（按依赖关系排序，非按编号）
3. **Sprint 16 验收闭环**（ADR-007 解释 CATEGORY 偏离 + BL-22 修复 + Electron E2E）

### ADR-007: 训练流 mapping 用 CATEGORY 模式而非 challengeId 模式

**背景**: 原 plan §BL-01a 写的是 challengeId → {syndromeId, techniqueName, userLevel, category} 映射，实际实现改成了「5 个 CATEGORY + 5 步 FLOW_TEMPLATES」分离结构。

**决策**:
- 选 CATEGORY 模式（已实现），不退回 challengeId
- 理由 1：5 步模板是教学动作（解说→例证→确认→尝试→反馈），与具体 challengeId 解耦后**可复用**
- 理由 2：6 类挑战 ↔ 5 步模板已经是笛卡尔积爆炸，CATEGORY 模式按"开篇/人物/节奏/语言/..."分组更可持续
- 理由 3：用户原话「技法库膨胀按当前缺口必定导致训练库膨胀，转为五步教学动作流程才是正确解决方案」

**待办**:
- 写 ADR-007 详细文档（5 步 + 5 模板 vs 6 challengeId 决策矩阵）
- 验收 DoD #2 改成"5 个 CATEGORY 至少各覆盖 1 个 challengeId"（更宽松的指标）

## 任务清单（按执行顺序）

### Phase 1: 验收前置（必须先完成）

| 任务 | 描述 | DoD | 阻塞 |
|:---|:---|:---|:---|
| **T17-1** | ADR-007 写 CATEGORY vs challengeId 决策 | 文档 ≥50 行 + 决策矩阵 | 无 |
| **T17-2** | BL-22 修复 better-sqlite3 dual target | 配 electron-rebuild + postinstall | T17-3 |
| **T17-3** | Electron E2E 验证 Sprint 16 | 走完 5 步流程录屏 | T17-2 |
| **T17-4** | 恢复 BL-19 7 个 workspace import | 注释掉的 import 恢复或建空组件 | 无 |

### Phase 2: 审计 P0（CSS 闭环）

| 任务 | 描述 | DoD | 阻塞 |
|:---|:---|:---|:---|
| **T17-5** | 写 `training/flow/flow.module.css` | ≥200 行，5 步容器 + 进度条 + 步骤面板三态 | T17-3 |
| **T17-6** | AppShell preventDefault 修复（已 uncommitted） | 1 commit，符合 R-016 | 无 |

### Phase 3: 审计 P1 整改（6 个 Issue）

| 任务 | Issue | 描述 | 依赖 |
|:---|:--:|---|:---|
| **T17-7** | #28 | CenterPanel Zustand 整 state 订阅拆为独立 selector | 无 |
| **T17-8** | #29 | AppShell 收起栏 emoji → lucide-react (Plus/Settings/Maximize2/Minus/Square/X) | 无 |
| **T17-9** | #30 | CenterPanel empty state emoji → lucide-react (PenLine/Sprout/MessageCircle) | 无 |
| **T17-10** | #32 | 启用 FiveStepFlow 4 个 skip 测试（引入 user-event） | T17-5 |
| **T17-11** | #33 | AppShell 硬编码颜色 → token + 拖拽 layout thrashing 优化 | 无 |
| **T17-12** | #31 | 移除 Tailwind 依赖，统一 CSS Modules | T17-7/8/9/10/11 完成后做最后清理 |

### Phase 4: 验证 + 收尾

| 任务 | 描述 |
|:---|:---|
| **T17-13** | 重跑 `$impeccable audit`，目标 ≥14/20 |
| **T17-14** | 更新 CHANGELOG → [1.2.0] - 2026-06-23 |
| **T17-15** | 写 D-047 Reflect（验收闭环 + 审计整改总结） |

## DoD 验证

### 必需（不通过不进 Sprint 18）

1. **T17-1 / T17-2 / T17-3 / T17-4 全部完成**（验收闭环）
2. **T17-5 训练流 CSS 落地**（P0）
3. **T17-6 / T17-7 / T17-8 / T17-9 / T17-10 / T17-11 6 个 P1 全部完成**
4. **门禁**：typecheck 0 / vitest 633 (含 4 skip 启用) / lint 0
5. **审计重跑得分 ≥14/20**

### 加分

6. **T17-12 移除 Tailwind 依赖**（产物体积 -30KB）
7. **D-047 决策日志更新**（含 4 个新债务）

## 边界定义

### 包括（Sprint 17 范围）

- Sprint 16 验收闭环（BL-22 + ADR-007 + Electron E2E）
- 6 个 P1 审计整改 Issue
- 1 个 P0 CSS 修复
- 1 个 P1 修复（AppShell preventDefault）
- 1 个 P1 改造（移除 Tailwind）

### 不包括（顺延到 Sprint 18）

- T15-1 attitude 透传改造（D-DEBT-17）
- T15-2 SKILL 文件补充 conditions 字段
- T15-3 v5 vs dispatcher v2 A/B 灰度发布
- BL-19 7 个 workspace 实际组件实现（仅恢复 import）
- 训练效果数据持久化增强
- 新功能/新 UI 模块

### 永久不包括（已剔除）

- 新增 per-症候训练任务（D-046 决策）
- per-症候 CSS 模板
- 任何超出"审计整改 + 验收"范围的需求

## 数据流

```
Sprint 17 启动
    ↓
Phase 1: T17-1 ADR → T17-2 BL-22 → T17-3 E2E → T17-4 恢复 import
    ↓ (验收通过)
Phase 2: T17-5 CSS → T17-6 AppShell fix
    ↓
Phase 3: T17-7 ~ T17-12 6 P1 整改
    ↓
Phase 4: T17-13 audit 重跑 → T17-14 CHANGELOG → T17-15 D-047
    ↓
Sprint 18 启动
```

## 文件清单

### 新建

| 文件 | 任务 | 预估 |
|---|:---:|:---:|
| `dev-docs/designs/adr/007-training-flow-category-mode.md` | T17-1 | 0.2d |
| `src/renderer/components/training/flow/flow.module.css` | T17-5 | 0.4d |
| `src/renderer/components/training/flow/__tests__/FiveStepFlow.integration.test.tsx` | T17-10 | 0.3d |

### 修改

| 文件 | 任务 | 预估 |
|---|:---:|:---:|
| `package.json` (electron-rebuild 钩子) | T17-2 | 0.2d |
| `src/main/domains/01-diagnosis/orchestrator/diagnosis-orchestrator.service.ts` | T17-3 端点 | 0.1d |
| `src/renderer/components/AppShell/index.tsx` + `index.module.css` | T17-6/11 | 0.2d |
| `src/renderer/components/center/CenterPanel/index.tsx` | T17-7/9 | 0.2d |
| `src/renderer/components/training/flow/*.tsx` | T17-10 启用 skip | 0.1d |
| `src/renderer/styles/globals.css` (移除 @tailwind) | T17-12 | 0.1d |
| `package.json` (移除 tailwind 依赖) | T17-12 | 0.1d |
| `dev-docs/audits/2026-06-23-frontend-audit-v2.md` (T17-13 重跑) | T17-13 | 0.2d |
| `CHANGELOG.md` ([1.2.0]) | T17-14 | 0.1d |
| `docs/decision-log.md` (D-047) | T17-15 | 0.2d |

| **合计** | | **~2.4d** |

## 风险与回退

| 风险 | 概率 | 影响 | 回退 |
|:---|:---:|:---:|:---|
| BL-22 electron-rebuild 配错 | 中 | 高 | 保留 npm rebuild 现状，T17-3 退化为 vitest + 手动 UI 录屏 |
| CSS 写错破坏 FiveStepFlow 布局 | 低 | 中 | 用 CSS Module 隔离，影响范围仅 1 组件 |
| Tailwind 移除导致现有样式崩坏 | 高 | 高 | 分批迁移，每迁移 1 个文件跑一次门禁；保留 tailwind 包 1 个 sprint 观察 |
| 启用 4 skip 测试发现真 bug | 中 | 中 | 修复 bug 而非继续 skip，符合 R-027 门禁精神 |

## 与其他 Sprint 的关系

```
Sprint 15 (D-035): 诊断库漏洞修复 → 3 债务全清
Sprint 16 (D-046): 五步训练流贯通 → PR #24 已合，但验收缺 E2E
Sprint 17 (本): 审计整改 + 验收闭环 → 目标 ≥14/20 + Sprint 16 验收签字
Sprint 18 (计划): 新功能恢复 + T15-1/2/3 + BL-19 workspace 组件化
```

## 依据

- `dev-docs/audits/2026-06-23-frontend-audit.md` (11/20 评分 + 15 issues)
- `docs/decision-log.md` D-046 (Sprint 16 Reflect)
- 6 个 GitHub Issue (#28-#33)
- `dev-docs/designs/sprint-16-plan.md` (DoD 对照)
- R-010 最小化范围 / R-014 配置外置 / R-027 四道门禁
