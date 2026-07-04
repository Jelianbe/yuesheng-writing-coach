# T26-2.1 Plan: sessions 表迁移(主进程 SessionService → StorageAdapter)

> **目标**: 把主进程 `SessionService`(同步 better-sqlite3)切到 `src/shared/services/session.service.ts`(异步 StorageAdapter)
> **依据**: Issue #46 / Issue #47 / commit 7f45afb 阶段 1
> **R-010**: 最小化,只改 4 个文件,其他不动

---

## 0. 现状

### 0.1 同步版本
- `src/main/shared/services/session.service.ts` — 108 行,`SessionService` 接收 `Database.Database`
- 方法:listSessions / createSession / deleteSession / renameSession / saveMessage / getMessages / getMessagesPaged / getLastMessage / searchMessages / autoGenerateTitle / getOrCreateDefaultSession
- 调用方: `src/main/ipc/session.handler.ts` (11 个 createHandler)
- DI 入口: `src/main/core/service-config.ts:58` `new SessionService(db)`
- 测试: `src/main/shared/services/session.service.test.ts`

### 0.2 异步版本(已有)
- `src/shared/services/session.service.ts` — 162 行,`SessionService` 接收 `StorageAdapter`
- 所有方法已经是 async
- 渲染层在使用: `src/renderer/services/session.service.ts`

---

## 1. 实施步骤

### Step 1: DI 改造(`src/main/core/service-config.ts`)

```diff
- import { SessionService } from '../shared/services/session.service';
+ import { SessionService } from '../../shared/services/session.service';
+ import { BetterSqliteAdapter } from '../../shared/storage/adapters/better-sqlite.adapter';

  container.register<Database.Database>('db', () => db);
+ container.register<BetterSqliteAdapter>('storageAdapter', () => new BetterSqliteAdapter({ db }));
- container.register<SessionService>('sessionService', () => new SessionService(db));
+ container.register<SessionService>('sessionService', (c) => new SessionService(c.get<BetterSqliteAdapter>('storageAdapter')));
```

### Step 2: IPC handler 异步化(`src/main/ipc/session.handler.ts`)

- import SessionService from `../../shared/services/session.service`
- 11 个 createHandler 全部改为 `async (_event, args) => { ... }` + `await`
- 标 @deprecated 给旧 `src/main/shared/services/session.service.ts`(保留以兼容其他引用)

### Step 3: 标 @deprecated(`src/main/shared/services/session.service.ts`)

文件顶部加:
```
/**
 * @deprecated Sprint 26 阶段 2 后,主进程应使用 src/shared/services/session.service.ts(异步 + StorageAdapter)
 * 本文件保留至 S26 阶段 4(IPC 完全移除)
 */
```

### Step 4: 单测(`src/shared/services/__tests__/session.service.test.ts`)

- 使用 `MemoryAdapter`(已存在 `src/shared/storage/adapters/memory.adapter.ts`)
- 覆盖 listSessions / createSession / deleteSession / renameSession / saveMessage(事务) / getMessagesPaged
- ≥ 6 用例

### Step 5: 4 道门禁

```bash
npm run typecheck && npm run test && npm run lint
```

---

## 2. 范围与边界

### 在范围内
- service-config.ts DI 改造
- session.handler.ts async 化
- src/main/shared/services/session.service.ts 标 @deprecated
- 新增 src/shared/services/__tests__/session.service.test.ts

### 不在范围内
- ❌ 改 src/shared/services/session.service.ts(已 OK)
- ❌ 改 src/renderer/services/session.service.ts(已 OK)
- ❌ 改其他 4 张表
- ❌ 移除 src/main/shared/services/session.service.ts(S26 阶段 4 才做)
- ❌ 改 src/main/shared/services/session.service.test.ts(旧测试可保留,标 deprecated)
- ❌ 改 IPC channel 协议

---

## 3. DoD(完成标准)

- [ ] DoD-1: service-config.ts 切到 BetterSqliteAdapter + shared SessionService
- [ ] DoD-2: session.handler.ts 11 个 handler 全部 await
- [ ] DoD-3: 旧 session.service.ts 标 @deprecated
- [ ] DoD-4: 新增单测 ≥ 6 用例(MemoryAdapter 跑通)
- [ ] DoD-5: typecheck 0 errors
- [ ] DoD-6: lint 0 errors
- [ ] DoD-7: test 全绿(包含新单测 + 旧单测不退化)
- [ ] DoD-8: 提交干净,无 console error

---

## 4. 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| 同步→异步遗漏某 handler | IPC 调用返回 undefined | 严格 typecheck(IPC handler 强制返回 Promise) |
| ChatOrchestratorService 内部仍用旧 sessionService | 调用栈断裂 | ChatOrchestrator 接收 SessionService 接口,异步方法签名不变 |
| better-sqlite3.transaction 同步 vs adapter.transaction 异步 | saveMessage 行为变化 | 已使用 adapter.transaction(BetterSqliteAdapter 用 BEGIN/COMMIT 手动控制) |
| 旧测试 src/main/shared/services/session.service.test.ts 失败 | 阻塞门禁 | 保留旧测试,不删(其依赖旧 SessionService,会自动跟 @deprecated 走) |

---

## 5. 预估工作量

- Step 1: 5 分钟(3 行 diff)
- Step 2: 15 分钟(11 个 handler await 化)
- Step 3: 2 分钟(@deprecated 注释)
- Step 4: 30 分钟(单测)
- Step 5: 5 分钟(门禁)

总计: ~1 小时
