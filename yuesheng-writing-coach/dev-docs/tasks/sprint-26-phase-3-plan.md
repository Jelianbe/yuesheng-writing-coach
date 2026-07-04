# Sprint 26 阶段 3 — IPC 通道移除（双轨过渡）

> **范围**: 把渲染层 8 个 service 从「纯 IPC 走 typedInvoke」改为「Electron 走 IPC，Android 走直接 import service」
> **依据**: ADR-010（IPC 移除策略）+ Sprint 26 plan §2.2
> **前置**: 阶段 1+2 已完成（5 张表迁移 + StorageAdapter 抽象 + APK 构建）
> **校正**: ADR-010 估算"27 个 IPC 通道"，实际 **75 个** invoke 通道 + 7 个 event 通道

---

## 0. 目标与边界

### 0.1 目标

- 渲染层 8 个 service（除 `ipc-client.ts` + 已双轨的 `session.service.ts`）实现双轨
- main 端 16 个 IPC handler 评估：保留 wrapper（薄）还是删除
- preload 白名单从 75 通道缩减为 0
- typedInvoke 收尾（D-DEBT-34）
- **Android 验证**改为**可选**（用户工具链不熟）

### 0.2 不在范围

- ❌ AVD 模拟器验证（用户设备环境未就绪，延期到 S27+）
- ❌ 业务逻辑重构（R-010 最小化不顺手）
- ❌ 新功能添加
- ❌ 22 张非核心表迁移

---

## 1. 现状快照

| 文件 | 状态 | 备注 |
|:-----|:-----|:-----|
| `src/shared/services/session.service.ts` | ✅ 异步化 | 5 个方法 |
| `src/shared/services/project.service.ts` | ✅ 异步化 | 5 个方法 |
| `src/shared/services/teaching-state.service.ts` | ✅ 异步化 | 6 个方法 |
| `src/shared/services/training-record.service.ts` | ✅ 异步化 | 4 个方法 |
| `src/shared/services/active-training.service.ts` | ✅ 异步化 | 5 个方法 |
| `src/renderer/services/session.service.ts` | ✅ **双轨** | 可作模板 |
| `src/renderer/services/active-training.service.ts` | ❌ 纯 IPC | 需改造 |
| `src/renderer/services/chat.service.ts` | ❌ 纯 IPC | 需改造 |
| `src/renderer/services/diagnosis.service.ts` | ❌ 纯 IPC | 需改造 |
| `src/renderer/services/student-context.service.ts` | ❌ 纯 IPC | 需改造 |
| `src/renderer/services/teaching-state.service.ts` | ❌ 纯 IPC | 需改造 |
| `src/renderer/services/training.service.ts` | ❌ 纯 IPC | 需改造 |
| `src/renderer/services/app-controller.ts` | ⚠️ 评估 | 可能是包装层 |
| `src/main/ipc/` (16 handler) | ❌ 待评估 | 哪些删/留 |
| `src/preload/index.ts` | ❌ 待删 | 白名单全清 |
| `src/shared/constants.ts` | ⚠️ 75 通道 | 评估删除 |

---

## 2. 阶段拆解

### 阶段 3.1: 双轨模板抽取（0.5 天）

**目标**: 把 `session.service.ts` 的双轨模式抽成可复用 helper

**实施**:
- 新文件 `src/renderer/services/_dual-track.ts`
- 导出 `withDualTrack<T>(electronFallback, directService, methodName, args): Promise<T>`
- 模板：检测 `window.Capacitor` → 有则调 direct service → 无则走 IPC
- 错误处理：try/catch + console.error + 返回 fallback（参考 B-2 D-DEBT-34）

**DoD**:
- helper 单元测试覆盖：3 路径（direct 成功 / direct 失败 / 非 Capacitor 走 IPC）
- typecheck 0 error
- `session.service.ts` 改用 helper（验证模板有效）

### 阶段 3.2: 渲染层 7 个 service 加双轨（3-4 天）

**目标**: 7 个 service 文件从纯 IPC 改为双轨

| Service | 主要方法 | 工作量 |
|:--------|:---------|:------:|
| `active-training.service.ts` | start/advanceStep/evaluate/complete/abort/updateDraft | 1 天 |
| `teaching-state.service.ts` | get/confirm/getPrompt/updateSummary | 0.5 天 |
| `chat.service.ts` | send/stop/handleTurn | 0.5 天 |
| `diagnosis.service.ts` | query/submitRewrite/getComparison | 0.5 天 |
| `student-context.service.ts` | 视实现而定 | 0.5 天 |
| `training.service.ts` | recommend/assign/complete 等 10 通道 | 0.5 天 |
| `app-controller.ts`（如果独立）| 评估后决定 | 0.5 天 |

**DoD**:
- 7 个 service 全部通过 `withDualTrack` 调用
- 单元测试：mock direct service + 验证 IPC fallback
- typecheck 0 error
- 现有 Electron 端功能不破坏（手工 smoke 或 E2E）

### 阶段 3.3: typedInvoke 收尾（D-DEBT-34，1 天）

**目标**: 13 处 `if (!success) throw` 改为 `console.error + return fallback`

**DoD**:
- 0 处 `throw new Error('IPC failed')` 模式
- D-DEBT-34 在决策日志中关闭
- 单测覆盖降级路径

### 阶段 3.4: main IPC handlers 评估 + 收尾（1 天）

**目标**: 16 个 handler 文件评估：保留 wrapper / 删除 / 替换为 service 直调

**判定规则**:
- 如果 handler 只做 `args → service.method → return` → **删除**（调用方已迁双轨，不再走 IPC）
- 如果 handler 做参数转换 / 权限校验 / 多步编排 → **保留**为薄包装
- 估计删除 ~10 个，保留 ~6 个

**DoD**:
- 删除清单（10 个） + 保留清单（6 个）记录到 plan §4
- 删除的 handler 文件实际从 src/main/ipc/ 移除
- 保留的 handler 改为「单行直调」: `return await xxxService.method(args)`

### 阶段 3.5: preload + constants 收尾（0.5 天）

**目标**:
- `src/preload/index.ts` 移除所有 `ALLOWED_INVOKE_CHANNELS` 暴露（仅留 window 控制）
- `src/shared/constants.ts` `IPC_CHANNELS` 中已删除的通道同步移除
- `ALLOWED_INVOKE_CHANNELS` 数组清空

**DoD**:
- `grep -r "ipcMain.handle\|ipcRenderer.invoke" src/` 0 命中
- `preload/index.ts` 仅暴露 window control
- typecheck 0 error
- Electron 端无回归（保留的 wrapper 仍可用）

---

## 3. 总 DoD

1. ✅ 7 个 renderer service 完成双轨（除 session 已完成）
2. ✅ 16 个 main IPC handler 评估完成，~10 个删除
3. ✅ preload 白名单清空
4. ✅ typedInvoke 13 处降级（D-DEBT-34 关闭）
5. ✅ typecheck 0 error
6. ✅ 单测覆盖率 ≥ 90%（service + helper）
7. ✅ Electron 端回归通过
8. ✅ Android 端代码层验证（编译通过 + 启动不报错）
9. ✅ 决策日志 D-075（阶段 3 完工）+ D-DEBT-34 关闭

---

## 4. 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| 双轨模板抽错 | 8 个 service 改坏 | 先用 session.service.ts 验证，再批量改 |
| handler 误删 | 启动报错 | typecheck + 立即 git 回滚 |
| Capacitor 检测漏 | Android 走 IPC 失败 | helper 加 `console.warn` 日志 |
| 异步遗漏 | 链式 await 缺 | strict TypeScript + typecheck |

---

## 5. 时间盒

| 子阶段 | 工时 | 累计 |
|:-------|:----:|:----:|
| 3.1 双轨模板 | 0.5 天 | 0.5 |
| 3.2 7 个 service 双轨 | 3-4 天 | 4.5 |
| 3.3 typedInvoke 收尾 | 1 天 | 5.5 |
| 3.4 main handler 收尾 | 1 天 | 6.5 |
| 3.5 preload + constants | 0.5 天 | 7 |
| **总计** | **7 工作日（1.4 周）** | |

---

## 6. 决策点（用户已确认 2026-07-04）

| # | 决策 | 决定 |
|:--|:-----|:----:|
| D1 | Android 模拟器验证降级为"可选" | ✅ AVD 验证推 S27+ |
| D2 | 16 个 handler 评估后删除 vs 保留 wrapper | ✅ 用 §3.4 规则（删 10 / 留 6） |
| D3 | typedInvoke 是否完全删除 | ✅ 保留 utility 备用 |
| D4 | 264 warnings 是否合并 | ✅ 拆独立 Sprint 27 专项 |

---

## 7. 状态

**✅ 用户已审批（2026-07-04）**。决策：D1-D4 全部采纳推荐项。

实施顺序：
1. commit 本文档到 `feature/sprint-26` ← **当前步骤**
2. 启动阶段 3.1（双轨模板抽取 0.5 天）
3. 按 3.1 → 3.5 顺序执行
4. 每完成 1 子阶段 commit 1 次
5. 阶段 3 全部完工后写 D-075
