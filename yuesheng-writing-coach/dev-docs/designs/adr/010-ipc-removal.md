# ADR-010: IPC 通道移除策略

> **状态**: Accepted
> **日期**: 2026-07-04
> **关联**: Sprint 26 Issue #44 / dev-docs/tasks/sprint-26-plan.md §1.3
> **决策者**: AI 架构师（用户确认）

## 背景

Sprint 26 战略转向：Electron → Capacitor Android 双端复用（D-074）。

**当前问题**：
- 27 个 IPC 通道桥接 main ↔ renderer
- 通道全部依赖 Electron 的 `ipcMain.handle` / `ipcRenderer.invoke`
- 在 Android（WebView）中**无 IPC 概念**

**目标**：
- 移除全部 27 个 IPC 通道
- WebView 内部直接 import service 调用
- R-020 边界从"main ↔ renderer"变成"store ↔ adapter"

## 决策

**分阶段移除，先标记后删除**。

### 阶段 A（阶段 4 早期）：标记 @deprecated

**目标**: 全部 27 个 IPC 通道添加 `@deprecated` 注释，但**不删除**。

**实施**:
- 通道常量定义（`shared/constants.ts` `IPC_CHANNELS`）添加 `@deprecated` 注释
- handler 文件（`src/main/ipc/*.handler.ts`）添加 `@deprecated` 注释
- preload (`src/preload/index.ts`) 暴露的方法添加 `@deprecated` 注释
- 注释明确："Sprint 26 移除，调用方需迁移到直接 import service"

**风险**：
- 未发现调用方 → 调用方仍依赖 → 行为不变
- 调用方需在阶段 B 迁移

### 阶段 B（阶段 4 中期）：迁移调用方

**目标**: 把 27 个 IPC 通道的**所有调用方**迁移到直接 import service。

**实施**:
- renderer 端：删除 `getInvoke()(channel, args)` 调用，改为 `await sessionService.getById(id)` 直接调用
- service 端：保持现状，但调用方不再走 IPC
- 阶段 B 完成后，IPC 通道**无任何调用方**（仅定义存在）

**风险**：
- 调用方遗漏 → 启动报错 → 修复
- 异步适配遗漏 → TypeError → 修复

### 阶段 C（阶段 4 后期）：物理删除

**目标**: 删除全部 27 个 IPC 通道定义、handler、preload 暴露。

**实施**:
- 删除 `IPC_CHANNELS` 数组中相应常量
- 删除 `src/main/ipc/*.handler.ts` 文件
- 删除 `src/preload/index.ts` 暴露的方法
- 删除 `typedInvoke` 工具（如不再使用）
- 删除 `D-DEBT-34` 治理（typedInvoke 收尾债务一并解决）

**风险**：
- 误删被引用的常量 → 编译报错 → 立即回滚

## 关键决策点

### 决策 1: 状态机 / 事件总线如何处理？

**背景**: Sprint 22-24 的状态机改造基于主进程侧事件总线（OrchestratorEvent），IPC 用于推送 renderer。

**决策**: 
- 主进程侧事件总线保留（内部机制，services 订阅）
- renderer 订阅通过 Zustand store 包装（main → store 直接调用，WebView 无 IPC 概念）
- 事件名保留英文 PascalCase（不重命名）

**理由**:
- 事件总线是主进程内部机制，跨端无关
- WebView 内部调用是直接函数调用，不需要事件机制

### 决策 2: 异步 vs 同步的迁移

**背景**: 当前 main 进程是同步（better-sqlite3），services 改造后需异步。

**决策**: 全部 services 异步化。

**理由**:
- 双端统一（Capacitor SQLite 天然异步）
- TypeScript async/await 链式调用清晰
- 性能：WebView 桥接是异步，强行同步会卡 UI

**实施**:
- 所有 service 公共方法加 `async`
- 所有 caller 加 `await`
- typecheck 强制（`strict: true`）

### 决策 3: 错误处理

**背景**: IPC 错误通过 IPC 通道返回，service 错误直接 throw。

**决策**: 统一 throw，renderer 端 try/catch。

**理由**:
- 双端一致
- TypeScript 类型推断友好（Promise reject 自动类型）
- 调试链短

### 决策 4: 5 张表迁移期间的双轨期

**背景**: 5 张表迁移不是一次性完成，期间 Windows 和 Android 行为需保持一致。

**决策**: StorageAdapter 阶段一次性上线，5 张表分批迁移但都走 adapter。

**理由**:
- 避免双轨（IPC + adapter 同时存在）
- 一致性：5 张表都用 adapter，行为一致
- 测试：单 adapter 实现可单测 5 张表

## 27 个 IPC 通道分类

按 domain 分类（实际数量需以 `IPC_CHANNELS` 数组为准）：

| 类别 | 通道示例 | 数量（估）|
|------|---------|:--------:|
| 会话 | session:list, session:get, session:create, ... | ~5 |
| 项目 | project:list, project:get, project:create, ... | ~5 |
| 章节 | chapter:list, chapter:get, chapter:create, ... | ~3 |
| 诊断 | diagnosis:save, diagnosis:list, ... | ~3 |
| 教学 | teachingState:confirm, ... | ~2 |
| 训练 | training:assign, training:complete, ... | ~4 |
| 文档 | document:read, document:write, ... | ~2 |
| 配置 | config:get, config:set, ... | ~3 |
| **合计** | | **~27** |

具体清单在实施时导出（`git grep IPC_CHANNELS`）。

## 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| 调用方遗漏 | 启动报错 | 阶段 B 用 typecheck + 单测覆盖 |
| 异步适配遗漏 | TypeError | 严格 TypeScript + 单测 |
| 状态机事件丢失 | UI 过期 | store 订阅模式 + 冷启动 fetch（参考 Sprint 24 A 轨） |
| preload 残留 | 死代码 | 阶段 C 一次性清 |
| Windows 横幅未显示 | 用户困惑 | README + 启动弹窗（独立任务） |

## 备选方案

- **方案 B**: 保留 IPC，Android 端模拟 IPC（不推荐：架构污染）
- **方案 C**: 用 Capacitor 的事件机制替代 IPC（不推荐：Capacitor 事件无主进程概念）

## 关联

- Sprint 26 plan: dev-docs/tasks/sprint-26-plan.md §1.3
- Issue #44 Sprint 26 容器
- D-074 Sprint 26 战略转向
- ADR-009 StorageAdapter 接口设计
- D-073 推 S26 治理（264 warnings，typedInvoke 收尾债务）
- Sprint 24 A 轨 ActiveTrainingService（事件总线基础）
