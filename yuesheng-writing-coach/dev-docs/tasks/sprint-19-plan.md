# Sprint 19 — 子页面范围重划 + 训练计划 + 成长报告

> 日期：2026-07-02
> Sprint: sprint-19
> 状态: 🔵 Think 阶段

---

## 一、问题重述

Sprint 18 留下 4 个子页空壳：
- 成长报告（growth-report）— 0% 实装
- 训练计划（training-plan）— 0% 实装
- 技法库（technique-library）— 0% 实装
- 素材库（material-library）— 0% 实装

加上 AppsPage 工具区 3 个空按钮，共 7 个虚假入口。E2E 测试只测了导航可达，未测数据流。

**核心矛盾**：开发资源 vs 用户价值对齐。
- 当前是"教学系统"而非"写作工具"
- 技法库/素材库不在核心教学链路
- 成长报告（验证进步）是教学闭环最薄弱的环节
- 训练计划（制定训练）次重要

## 二、决策（D-051）

### D-051 · Sprint 19 子页范围重划

**V1 (Sprint 19) 必做**：
1. **实装 训练计划**（1.5 天）
2. **实装 成长报告**（1.5 天）

**V1 入口清理**（0.5 天）：
- AppsPage 移除 4 个空壳入口：技法库、素材库、工具的结构拆解、导出作品
- 保留 工具：设定管理（未来功能占位）

**V2 缓做**：
- 技法库：合并到诊断面板的"展开全部"按钮，不做独立页
- 素材库：先做用户调研决定去留
- 工具区 3 个：暂全部删除

**理由**：
- 集中资源到教学链路关键环节（验证进步 + 制定训练）
- 避免用户点击空壳造成信任流失
- 把"工具"概念从"写作辅助"转为"教学辅助"对齐定位

## 三、Issue 拆分（按 R-004 DoD）

### Issue 19-1: AppsPage 虚假入口清理

**DoD（至少 3 条可验证）**：
- [ ] 移除 GRID_ITEMS 中 技法库、素材库 2 个入口
- [ ] 移除 TOOL_ITEMS 中 结构拆解、导出作品 2 个入口
- [ ] 仅保留 成长报告、训练计划、设定管理 3 个入口
- [ ] E2E 测试 `apps.spec.ts` 4 图标断言改为 2 图标
- [ ] typecheck/test/lint 零错误

**依赖**：无

---

### Issue 19-2: 训练计划实装（P0）

**DoD（至少 3 条可验证）**：
- [ ] `src/main/domains/02-prescription/development-path/` 域服务暴露 `getAllStages` 方法
- [ ] 主进程 IPC handler `prescription:getAllStages` 注册到 `ipc-registry.ts`
- [ ] 训练计划页面调用 `usePrescriptionStore.fetchAllStages()` 替换"数据加载中…"
- [ ] 页面渲染：3-5 个发展阶段卡片（stage1 → stage5），每个含标题/描述/进度条
- [ ] E2E 新增 1 项测试验证页面能渲染 stage 列表
- [ ] typecheck/test/lint 零错误

**依赖**：19-1（避免用户访问到但页面已删除）

**前端改动**：
- `src/renderer/pages/TrainingPlanPage.tsx` — 接入 Store + UI 渲染
- `src/renderer/stores/prescription.store.ts` — 已有 fetchAllStages，确认正确

**后端改动**：
- `src/main/domains/02-prescription/development-path/development-path.service.ts` — 确认 getAllStages 方法存在
- `src/main/ipc/development-path.handler.ts` — 确认 handler 注册

**风险**：
- 阶段数据可能为 mock（mock-data-injector.ts）
- 真实数据需 SQLite 表 `development_stages` 存在（migration 应已创建）

---

### Issue 19-3: 成长报告实装（P0）

**DoD（至少 3 条可验证）**：
- [ ] 主进程 IPC handler `growth:getGlobalTrends` 注册
- [ ] 成长报告页面调用 `useGrowthStore.fetchGlobalTrends()` 替换占位
- [ ] 页面渲染：5 个能力维度雷达图（教学/结构/语言/情感/创新）+ 趋势线
- [ ] 真实数据走 SQLite，mock 数据兜底
- [ ] E2E 新增 1 项测试验证页面能渲染雷达图
- [ ] typecheck/test/lint 零错误

**依赖**：19-1

**前端改动**：
- `src/renderer/pages/GrowthReportPage.tsx` — 接入 Store + 雷达图
- `src/renderer/stores/growth.store.ts` — 已有 fetchGlobalTrends

**后端改动**：
- `src/main/domains/03-teaching/growth/` 域服务暴露 getGlobalTrends
- `src/main/ipc/growth.handler.ts` — 新建 handler（可能不存在）

**风险**：
- 雷达图组件可能要新建（recharts 或纯 SVG）
- 全局趋势可能依赖 5 个能力维度的历史数据

---

## 四、依赖图

```
19-1 (入口清理, 0.5 天)
  ├── 19-2 (训练计划, 1.5 天)
  │     └── 19-2-E2E (新测试)
  └── 19-3 (成长报告, 1.5 天)
        └── 19-3-E2E (新测试)
```

总工作量：3.5 天，可串行或 19-2/19-3 部分并行。

## 五、门禁（R-027）

```
□ npm run typecheck  — 0 errors
□ npm run test       — 683/683 + 新增
□ npm run lint       — 0 errors
□ npm run test:e2e -- --project=firefox-mobile  — 全绿
□ npm run dev:electron  — 手动验证主进程启动
□ 4 道门禁通过 → 提交 → 更新 decision-log.md
```

## 六、Sprint 19 启动顺序

按用户决策：**先 19-1 → 19-2（训练计划）→ 19-3（成长报告）**

---

## 依据

- D-050 Sprint 18 Reflect（发现 D-DEBT-32 实际为 P0）
- R-004 DoD 定义 / R-022 过程可见 / R-027 AI 代码质量门禁
- 用户决策 2026-07-02："采用拆分方案" + "先 训练计划"
