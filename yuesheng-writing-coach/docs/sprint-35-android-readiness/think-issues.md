# Sprint 35 — Android 端就绪度修复

> GStack Think 阶段产出。基于代码级审计，将 6 项缺陷结构化为 Issue 定义。
> 审计依据：`capacitor-*.ts` / `useOrchestrator.ts` / `training.service.ts` / `service-bridge.ts` / `useStartTraining.ts` 逐行阅读。

---

## 分类原则

| 类别 | 含义 | GStack 流程 |
|------|------|-------------|
| **A 类** | 方案唯一、无架构决策、可直接修 | Think → 直接 Build |
| **B 类** | 方案明确但需写适配层 | Think → Plan 确认方案 → Build |
| **C 类** | 需架构决策（降级策略 / 业务下沉） | Think → Plan 必须决策 → Build |

---

## Issue #1 — capacitor.config.ts 缺 plugins 配置【A 类·致命】

### 现状
`capacitor.config.ts` 全文 9 行，仅声明 `appId` / `appName` / `webDir`，**无任何 plugins 配置**。

### 影响
- `@capacitor-community/sqlite` 在 Android 端不会被正确初始化（缺 `androidDatabaseLocation`）
- `CapacitorSqliteAdapter.initialize()` 抛 `StorageError`
- 连锁崩溃：会话、消息、教学状态、训练记录——所有依赖 DB 的功能全挂
- **应用启动即崩**

### 根因
Sprint 26 配置 Capacitor 时，只写了最小壳配置，未声明插件运行时参数。

### 修复策略
直接补 plugins 配置，参照 `@capacitor-community/sqlite` 官方文档。

### DoD
1. `capacitor.config.ts` 声明 `CapacitorSQLite` 插件配置（含 `androidDatabaseLocation`）
2. `npx cap copy` 后 Android 工程的 `android/app/src/main/assets/capacitor.config.json` 包含插件配置
3. typecheck 通过（config 类型符合 `CapacitorConfig`）

---

## Issue #2 — useOrchestrator 事件订阅在 Android 端断点【B 类·致命】

### 现状
`useOrchestrator.ts` L76-90 `ensureGlobalSubscription()` 直接调 `typedOn(IPC_CHANNELS.CHAT_EVENT, ...)`。Android 端 `typedOn` 因 `window.electronAPI` 不存在返回空 cleanup（`ipc-client.ts` L32），**订阅静默失效**。

### 影响
- Android 端 ChatPage 使用 `useOrchestrator.subscribe()` 收不到任何 orchestrator 事件
- 流式 token、phase 转换、done/error 信号全部丢失
- **UI 对话界面不更新**（即使 LLM 在正常流式输出）

### 根因（比预期更复杂）
不是简单"加 isCapacitor() 分支"能解决。**事件结构不匹配**：

| 路径 | 事件结构 | 触发源 |
|------|---------|--------|
| useOrchestrator 期望 | `OrchestratorEventEnvelope { streamId, sessionId, event: OrchestratorEvent }` | Electron main 的 orchestrator |
| capacitor-chat emit 的 | `{ sessionId, chunk: string }` (STREAM_DATA) / `{ sessionId, fullResponse, messageId }` (STREAM_END) | capacitor-chat.ts 内存总线 |

两套事件**结构完全不同**。capacitor-chat 只有"裸 token 流"，没有 orchestrator 的 `phase_transition` / `intent` / `training_triggered` / `diagnosis_extracted` 等语义事件。

### 修复策略（需 Plan 确认）
在 `capacitor-chat.ts` 与 `useOrchestrator` 之间加一层**事件适配器**：
- 监听 `capacitorOnStreamData` → 转 `{ type: 'token', content: chunk }` envelope
- 监听 `capacitorOnStreamEnd` → 转 `{ type: 'done' }` envelope
- Android 端**不支持**的 orchestrator 事件（phase_transition / intent / training_triggered / diagnosis_extracted）——明确降级，不伪造

### DoD
1. `useOrchestrator.ts` 在 Android 端走 capacitor 事件总线，能收到 token/done/error 三类事件
2. 不支持的 orchestrator 事件类型有明确降级（不伪造、不静默吞）
3. Electron 端行为零变化（`isCapacitor() === false` 走原路径）
4. 单元测试覆盖适配层的事件转换

---

## Issue #3 — useStartTraining 调 serviceBridge 未传 directFallback【B 类·高风险】

### 现状
`useStartTraining.ts` 两处调用：
- L38: `serviceBridge.invoke('training:catalog', {})` — 查技法目录
- L74: `serviceBridge.invoke('training:assign', {...})` — 分配训练

均**未传 `directFallback`**。`service-bridge.ts` L45 逻辑：`if (isCapacitor() && directFallback)` 才走直调，否则走 `typedInvoke` → Android 端返回 `{ success: false }` → 最终返回 `null`。

### 影响
- Android 端训练启动流程完全断链：找不到技法 → 无法创建训练会话
- 即使 Issue #6（Training 5 noop）修了，这个入口也走不到

### 根因
`useStartTraining` 是 Sprint 20 的旧代码，Sprint 33 Training Android 激活时**只改了 service 层，没改 hook 层**。

### 修复策略
两处调用补 `directFallback`：
- `training:catalog` → 直调本地技法目录（需确认数据源：硬编码目录 or StorageAdapter 读取）
- `training:assign` → 调 `trainingService.assign()` 的 capacitor 分支（依赖 Issue #6）

### DoD
1. `useStartTraining.ts` 两处 invoke 均传 directFallback
2. Android 端能拿到技法目录（非 null）
3. Android 端能走通 assign 流程（非 null，依赖 Issue #6）
4. Electron 端行为零变化

---

## Issue #4 — Training 5 个方法在 Android 端 noop【C 类·高风险·需架构决策】

### 现状
`training.service.ts` L69-136，5 个方法在 `isCapacitor()` 时返回 `null`：
- `recommend` — 推荐训练
- `assign` — 分配训练
- `complete` — 完成训练
- `skip` — 跳过训练
- `history` — 查询历史

注释（L20-22）明确说："业务全在主进程，shared 端无等价 service"。

### 影响
Android 端"10 通道训练协调"功能完全不可用。用户无法获取推荐、分配任务、完成/跳过训练、查历史。

### 根因
Training 业务逻辑（推荐算法、分配策略、状态流转）**硬编码在 main process 的 domains/03-teaching/**，依赖教学状态机 + SQLite。shared 层没有等价 service。

### 修复策略（Plan 阶段三选一）

| 方案 | 描述 | 工作量 | 代价 |
|------|------|--------|------|
| **C4-a 真实下沉** | 把 training 业务从 main 迁到 shared，双端共用 | 大（3-5 天） | 架构变动大，但一劳永逸 |
| **C4-b LLM 降级** | Android 端用 LlmClient + prompt 模拟推荐/分配逻辑 | 中（1-2 天） | 推荐质量不稳定，但能跑 |
| **C4-c 明确降级** | 5 方法返回明确"不支持"标记 + UI 提示，不伪造 | 小（2 小时） | Android 端训练功能不可用，但诚实 |

### DoD（按方案不同）
- C4-a：shared 层有 training service，双端调用一致，测试覆盖
- C4-b：5 方法有 LlmClient 实现，返回结构符合 contract，降级日志清晰
- C4-c：5 方法返回明确 `{ supported: false }` 标记，UI 有降级提示，不返回 null 让调用方猜测

---

## Issue #5 — diagnosis getComparison 是 noop【C 类·高风险·需架构决策】

### 现状
`capacitor-diagnosis.ts` L198-205，`capacitorDiagnosisGetComparison` 返回 `{ hasHistory: false }`，注释说"需要 diagnosis_records 表（未迁移）"。

### 影响
Android 端诊断对比功能不可用，用户看不到历史症候变化趋势。

### 根因
`diagnosis_records` 表的 29 个 SQLite 迁移文件**从未在 Capacitor SQLite 上验证过**。即使补了表迁移，对比逻辑也在 main process。

### 修复策略（Plan 阶段二选一）

| 方案 | 描述 | 依赖 |
|------|------|------|
| **C5-a 补迁移** | 验证 29 个迁移在 Capacitor SQLite 跑通，补对比逻辑 | 需先验证 Issue #1 修完后 SQLite 能初始化 |
| **C5-b localStorage 降级** | 用 localStorage 存历史诊断快照，做简化对比 | 无依赖，但对比能力弱 |

### DoD
- C5-a：迁移跑通，getComparison 返回真实历史对比
- C5-b：localStorage 存快照，getComparison 返回最近 N 次对比（能力受限但可用）

---

## Issue #6 — teaching-state getPrompt 是 noop【C 类·高风险·需架构决策】

### 现状
`capacitor-teaching-state.ts` L79-84，`capacitorTeachingStateGetPrompt` 返回 `null`，注释说"PromptBuilder + TeachingStateMachine 拼接逻辑在 main process，无法移植"。

### 影响
- Android 端 AI 响应**缺失教学状态上下文**
- 教练人设、态度档位、阶段信息、学生画像——全部不注入 prompt
- **Android 端的对话是"裸 LLM"，教练人设丢失**

### 根因
`PromptBuilder` + `TeachingStateMachine`（5 文件状态机）硬编码在 `src/main/domains/03-teaching/`。状态机的 navigation / locking / reflection / guide 四个子模块依赖 main process 的完整上下文。

### 修复策略（Plan 阶段三选一）

| 方案 | 描述 | 工作量 | 代价 |
|------|------|--------|------|
| **C6-a 状态机下沉** | 把 TeachingStateMachine + PromptBuilder 迁到 shared | 极大（5+ 天） | 架构级改动，但根本解决 |
| **C6-b 极简 prompt** | Android 端用简化 prompt（固定 system + 基础上下文），不走状态机 | 小（半天） | 教学能力大幅降级，但人设在 |
| **C6-c 接受缺失** | 明确标记 Android 端不支持 prompt 注入，文档记录 | 0 | Android 端无教练人设 |

### DoD
- C6-a：shared 层有 TeachingStateMachine + PromptBuilder，双端一致
- C6-b：Android 端有简化 system prompt（含人设 + 态度档位），注入 LLM 调用
- C6-c：文档明确标记，capacitor-teaching-state.ts 有明确降级注释

---

## 修复优先级与依赖关系

```
Issue #1 (config plugins) ──┐
                             ├─→ 解锁 SQLite 初始化
Issue #2 (orchestrator 适配) ──→ 解锁对话 UI 更新
Issue #3 (useStartTraining) ──┬─→ 依赖 Issue #6 (assign)
                              └─→ 依赖技法目录数据源
Issue #4 (Training 5 noop)  ──→ 依赖 Plan 决策
Issue #5 (diagnosis compare)──→ 依赖 Plan 决策 + Issue #1
Issue #6 (teaching prompt) ──→ 依赖 Plan 决策
```

### 建议执行顺序
1. **Plan 阶段**：先决策 Issue #4 / #5 / #6 的方案（C4-? / C5-? / C6-?）
2. **Build 阶段**：
   - 第一批：Issue #1 + Issue #2（致命，解锁"能起"）
   - 第二批：Issue #3 + Issue #4（高风险，解锁"训练能用"）
   - 第三批：Issue #5 + Issue #6（高风险，解锁"教学能用"）

---

## Sprint 35 范围声明

本 Sprint **目标是"Android 端代码能起、核心链路能跑"**，不包含：
- AVD 环境修复（工具链问题，独立处理）
- 真机验证（需真机设备，独立任务）
- 29 个 SQLite 迁移在 Capacitor 上的完整验证（依赖 Issue #1 修完后单独排期）

---

## 下一步

→ **Plan 阶段**：需用户对 Issue #4 / #5 / #6 选定方案后，锁定架构边界，进入 Build。
