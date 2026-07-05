# Sprint 26 阶段 3.4 — IPC Handler 评估报告

**日期**: 2026-07-04
**评估范围**: `src/main/ipc/*.handler.ts` 共 16 个文件
**评估依据**: plan §3.4 — 区分"业务编排" vs "args → service.method → return 直通"

---

## 评估矩阵

| # | Handler | 行数 | 业务复杂度 | 决策 | 理由 |
|:--|:--------|:----:|:----------|:-----|:-----|
| 1 | `ability-profile.handler.ts` | 33 | ⬜ 简单直调 | **保留** | 1 个 channel;虽可直调,但需在 config-store 集成测试覆盖 |
| 2 | `active-training.handler.ts` | 287 | 🟥 复杂 | **保留** | 状态机订阅 + 多窗口广播 + 5 步分步提交;核心链路不可删除 |
| 3 | `chat.handler.ts` | 116 | 🟧 中等 | **保留** | `ChatHandleTurnBridge` 订阅式入口 + 流式控制 + bridge 协调 |
| 4 | `config.handler.ts` | 123 | 🟧 中等 | **保留** | SEC-DEBT-1 白名单 + 运行时值校验 + reading-library 资源读取 |
| 5 | `development-path.handler.ts` | 106 | ⬜ 简单 | 🟡 **评估中** | 3 个 channel,1 个有数据转换,2 个纯直调;`getAllStages/getStageById` 可考虑删除 |
| 6 | `diagnosis.handler.ts` | 204 | 🟥 复杂 | **保留** | `processDiagnosisFromAI` 跨域编排 + 载荷脱敏 + mainWindow 推送 |
| 7 | `evidence.handler.ts` | 90 | ⬜ 简单 | **保留** | 5 个 channel,有 `apiError/apiSuccess` 错误包装(短期内重写性价比低) |
| 8 | `growth.handler.ts` | 59 | ⬜ 简单 | **保留** | 字段映射 `GrowthGlobalSyndromeTrend`;短期保留 |
| 9 | `manuscript.handler.ts` | 140 | 🟧 中等 | **保留** | 11 个 channel 全部 SQL 直调(主进程 SQLite);Android 端用 StorageAdapter 后再考虑 |
| 10 | `project.handler.ts` | 105 | ⬜ 简单直调 | 🟢 **删除候选** | 5 个 channel 全部 `args → projectService.method(args) → return` 直通;renderer 已有 `shared/services/project.service.ts`(S26-2 迁移完成) |
| 11 | `retro.handler.ts` | 37 | ⬜ 简单 | **保留** | 2 个 channel,但 `generateRetroSummary` 是 AI 编排(短期保留) |
| 12 | `session.handler.ts` | 111 | ⬜ 简单直调 | 🟢 **删除候选** | 10 个 channel 几乎全 `args → sessionService.method → return` 直通;`SESSION_LIST_WITH_META` 唯一有列表+最后消息组装 |
| 13 | `teaching-note.handler.ts` | 79 | 🟧 中等 | **保留** | 含 `flatToTree` 树形转换(64 行) |
| 14 | `teaching-state.handler.ts` | 204 | 🟥 复杂 | **保留** | SEC-DEBT-2 字段白名单 + 状态机推进 + mainWindow 跨域事件 |
| 15 | `training.handler.ts` | 379 | 🟥 复杂 | **保留** | 12 个 channel;`evaluateTraining` 多步编排 + mastery 门控 + 5 步分步提交 |
| 16 | `window.handler.ts` | 44 | ⟦ 平台 | **保留** | BrowserWindow 窗口控制;Android 端 WebView 无此概念 |

---

## 决策汇总

| 决策 | 数量 | 列表 |
|:-----|:----:|:-----|
| 🟢 **删除候选** | **2** | project, session |
| 🟡 **部分删除** | **1** | development-path(2/3 可删) |
| ⚪ **保留** | **13** | ability-profile, active-training, chat, config, diagnosis, evidence, growth, manuscript, retro, teaching-note, teaching-state, training, window |

**删除总收益**:
- 删 2 个完整 handler + 2 个 channel(development-path 中 2 个)
- preload 白名单减少 12 个 entry
- IPC_CHANNELS 减少 12 个常量
- renderer 端调用方改为 `shared/services/*.service.ts` 直调(已在 S26-2 完成)

---

## 阶段 3.4 执行计划(分 3 批)

### 批次 A: 删除 project.handler.ts(本日)
- 调用方扫:`grep -r "project:list\|project:get\|project:create\|project:update\|project:delete" src/renderer`
- 改 renderer 端 5 个调用点 → `shared/services/project.service.ts` 直调
- 删 `project.handler.ts` 文件
- 删 `IPC_CHANNELS` 中 PROJECT_* 5 个常量
- 删 `preload/index.ts` 中 PROJECT_* 5 个白名单
- 删 `ipc-registry.ts` 中 `registerProjectHandlers()` 调用
- 跑 typecheck + test + lint(0 增量)

### 批次 B: 删除 session.handler.ts 中 8 个直调(本日)
- 保留:`SESSION_LIST_WITH_META`(有列表+消息组装,38 行)
- 删除:其余 8 个 channel(全部直调)
- 调用方改 → `shared/services/session.service.ts` 直调
- 同步清理 IPC_CHANNELS + preload + ipc-registry

### 批次 C: 删除 development-path 中 2 个直调(本日)
- 保留:`PRESCRIPTION_GET_STAGE_PROGRESS`(有 StudentModelService 数据转换)
- 删除:`PRESCRIPTION_GET_ALL_STAGES`, `PRESCRIPTION_GET_STAGE_BY_ID`
- 调用方(如果有)改直调;或确认无 renderer 调用后直接删

---

## DoD 验收(本日)

- [ ] 12 个 channel 全部从 IPC_CHANNELS 移除
- [ ] 12 个 channel 从 preload 白名单移除
- [ ] 2 个完整 handler 文件 + 1 个部分 handler 缩减
- [ ] ipc-registry 减少 12 行 register 调用
- [ ] renderer 调用方全量迁移到 `shared/services/*.service.ts`
- [ ] typecheck 0 error
- [ ] test 全绿(预计 ~28 个新单测覆盖直调路径)
- [ ] lint 0 增量 warning
- [ ] Sprint 26 阶段 3.4 完工

---

## 风险与回退

| 风险 | 缓解 |
|:-----|:-----|
| renderer 调用方遗漏迁移导致白屏 | typecheck 报错时立即发现;不要 fallback throw |
| `SESSION_LIST_WITH_META` 调用方多 | 保留本期;下批再处理 |
| development-path 可能在未来需要 | 保留 `PRESCRIPTION_GET_STAGE_PROGRESS` 复杂版 |

---

## 不动项(本批不做)

- `manuscript.handler.ts` 11 个 SQL 直调 → 等 Android 端 StorageAdapter 完整化再统一迁移
- `active-training.handler.ts` 状态机推送 → 核心业务,不能删
- `window.handler.ts` 平台特定 → Android 端不适用但 Windows 仍需
