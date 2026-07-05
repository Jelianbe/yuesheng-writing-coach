# Sprint 32 — IPC 层重构：移除 serviceBridge / dual-track，直接 typedInvoke

> **范围**: 去掉 `serviceBridge` 中间层和 `_dual-track.ts` 双轨调度，renderer 直接 `typedInvoke` 调 main handler
> **动机**: Sprint 31 修复 IPC 白名单时发现 8 处 `result.xxx` 解包 BUG，根因是 serviceBridge + dual-track 增加了不必要的类型模糊层
> **原则**: 不改 handler 实现、不改 contract 类型定义、不改 store 调用方
> **前置澄清**: Sprint 31 讨论的"彻底换掉 IPC"仅指去掉 serviceBridge/dual-track 这一层 renderer 端的包装，**不是替换 Electron IPC 本身**。

---

## 0. 阻塞点先决：chat:send 的流式支持

**`typedInvoke` 本身不支持流式**（它是标准 `ipcRenderer.invoke` / `ipcMain.handle` request/response），但 **chat:send 不构成阻塞**。当前架构已是**双通道设计**：

```
chat:send invoke ──→ main handler ──→ 触发 AI 调用 → 立即返回 { messageId }
                                            │
                                            └── webContents.send('chat:stream:data', {chunk})  ◄── 独立事件推送
                                            └── webContents.send('chat:stream:end', {fullResponse})
```

**迁移后不变**：
- invoke 通道（`chat:send` / `chat:handleTurn`）→ 替换为 `typedInvoke`，仍然只拿 `{ messageId }` / `{ streamId }`
- 事件通道（`chat:stream:data` / `chat:stream:end` / `chat:event`）→ 走 `typedOn`，**完全不受影响**

**结论：stream 不是块。** 不需要 `chat:stream` 事件通道的适配。

---

## 1. 当前架构痛点

```
renderer page → store → service.xxx() → runDualTrack()
                                          ├── direct (Capacitor, never used in Electron)
                                          └── electron → serviceBridge.invoke()
                                                          └── typedInvoke(BRIDGE_INVOKE_CHANNEL, { method, args })
                                                              └── main: handleBridgeInvoke → handler
```

问题：
1. **双轨从未同时用** — `direct` 分支只用于 Capacitor（Android），Electron 永远走 `electron` 分支
2. **类型契约与实际不匹配** — contract 定义 `{ sessions: [...] }`，main handler 返回 `[...]`，serviceBridge 解 `ApiResponse` 后 `result` 是裸数据，但类型系统不知道 → 8 个解包 BUG
3. **每个 electron handler 都要写重复的 try/catch + 日志** — 20+ 个方法各有一套
4. **Capacitor 端已有独立实现**（`capacitor-*.ts`）— 不需要 dual-track 来分派

---

## 2. 目标架构

```
renderer page → store → service.xxx() → typedInvoke('session:list', {})
                                          └── main: registerMethod handler
```

Capacitor（保持独立文件，职责隔离）：
```
renderer page → store → service.xxx() → isCapacitor() ?
                                          ├── yes → capacitor-xxx.ts direct impl
                                          └── no  → typedInvoke(...)
```

---

## 3. 迁移步骤

### Phase 0: chat 流式专项确认 ✅

已完成（见 §0）。`chat:send` / `chat:handleTurn` 的 invoke 通道只返回初始元数据，流式 token 完全走独立事件通道。迁移后双通道均正常工作。

### Phase 1: 新建 `_invoke.ts`（公共 invoke 包装器）

消除所有 service 中重复的 try/catch + 日志：

```typescript
import { typedInvoke } from '../../shared/ipc/typed-invoke';

export async function invoke<Res>(
  channel: string,
  args: Record<string, unknown>,
): Promise<Res | null> {
  try {
    const result = await typedInvoke(channel, args);
    return result as Res | null;
  } catch (err) {
    console.error(`[invoke] ${channel} failed`, err);
    return null;
  }
}
```

**类型安全**：返回类型为 `Promise<Res | null>`，不隐藏 null。调用方通过 `??` 运算符自行决定 fallback：

```typescript
const sessions = await invoke<SessionInfo[]>('session:list', {}) ?? [];
const session = await invoke<SessionInfo>('session:create', { title }) ?? null;
```

### Phase 2: 逐个 Service 迁移

每个 service 去掉 `runDualTrack`、去掉 `serviceBridge`，用 `invoke` + `isCapacitor()` 分支：

```typescript
import { invoke } from './_invoke';
import { isCapacitor } from './_platform';
import * as capacitorImpl from './capacitor-session';

export const sessionService = {
  async list(): Promise<SessionInfo[]> {
    if (isCapacitor()) return capacitorImpl.list();
    return invoke<SessionInfo[]>('session:list', {}) ?? [];
  },
  async create(title?: string): Promise<SessionInfo | null> {
    if (isCapacitor()) return capacitorImpl.create(title);
    return invoke<SessionInfo>('session:create', { title });
  },
  // ... 其余方法同理
};
```

### Phase 3: 清理

- **删除** `src/renderer/services/service-bridge.ts`
- **删除** `src/renderer/services/_dual-track.ts`
- **保留** 5 个 capacitor 文件（`capacitor-*.ts`）— 职责隔离，不合并

---

## 4. 涉及的 Service 文件

| 文件 | 方法数 | 迁移量 | 注意事项 |
|:-----|:------:|:------|:---------|
| `session.service.ts` | 10 | ~40 行改 | 除 `getMessagesPaged` 外全部换掉 |
| `project.service.ts` | 5 | ~20 行改 | 简单 |
| `config.service.ts` | 1 | ~5 行改 | 简单 |
| `chat.service.ts` | 2 | ~10 行改 | invoke 只拿 `{ messageId }`，stream 事件不受影响 |
| `diagnosis.service.ts` | 3 | ~15 行改 | 简单 |
| `training.service.ts` | 10 | ~50 行改 | 逻辑分支多，逐个检查 |
| `active-training.service.ts` | 4 | ~15 行改 | 简单 |
| `development-path.service.ts` | 2 | ~10 行改 | 简单 |
| `teaching-state.service.ts` | 5+ | ~30 行改 | 含 Capacitor fallback |
| `student-context.service.ts` | 3 | ~10 行改 | 部分降级 |
| **小计** | **45+** | **~205 行改** | |

### 额外改动

| 文件 | 改动量 | 原因 |
|:-----|:------:|:-----|
| 新建 `_invoke.ts` | +15 行 | 公共 invoke 包装器 |
| 新建 `_platform.ts`（如不存在） | +5 行 | `isCapacitor()` 提取 |
| 测试 mock 适配 | +120 行 | ~10 个测试文件 mock 路径从 `serviceBridge` 改为 `typedInvoke` |
| **合计** | **~345 行** | **含测试适配** |

---

## 5. Capacitor 文件策略

**保留独立文件，不合并到主 service**：

- 职责隔离清晰 — 主 service 管 invoke，capacitor 管本地实现
- 5 个 capacitor 文件 (`capacitor-chat.ts`, `capacitor-config.ts`, `capacitor-diagnosis.ts`, `capacitor-teaching-state.ts`, `capacitor-training.ts`) **全部保留**
- 删除项只限 `service-bridge.ts` 和 `_dual-track.ts`

---

## 6. 验收标准

- [ ] `_invoke.ts` 返回 `Res | null`，类型安全，不隐藏 null
- [ ] 所有 service 方法去掉 `runDualTrack` 和 `serviceBridge`
- [ ] 每个 service 内显式 `??` 处理 null fallback
- [ ] `chat:send` invoke 返回 `ChatSendResponse | null`，stream 事件通道不变
- [ ] `service-bridge.ts` 和 `_dual-track.ts` 被删除
- [ ] 5 个 capacitor 文件保留，未被合并
- [ ] 全量测试通过（renderer: 245+ tests）
- [ ] Electron 窗口各页面交互无报错

---

## 7. 估算

| Phase | 文件 | 改动量 |
|:------|:-----|:------|
| P1: `_invoke.ts` | 1 新建 | +15 行 |
| P2: 迁移 services | 10 文件 | ~205 行改 |
| P3: 清理 | 2 删除 | — |
| 测试适配 | ~10 文件 | ~120 行改 |
| **合计** | **~23 文件** | **~340 行** |
