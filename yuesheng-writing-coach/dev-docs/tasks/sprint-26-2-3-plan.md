# T26-2.3 Plan: teaching_state 表迁移(主进程 → StorageAdapter 共享)

> **目标**: 把 `TeachingStateStore`(同步 better-sqlite3)的数据访问逻辑抽离到 `src/shared/services/teaching-state.service.ts`,实现异步 + 双端共用
> **依据**: T26-2.1/2.2 模式 + Sprint 26 plan §1.2
> **R-010**: 最小化,只新建 1 个 service + 修正 1 个 schema + 新增 1 个测试

---

## 0. 现状

### 0.1 主进程 store(同步 better-sqlite3)
- `src/main/domains/03-teaching/state/teaching-state.store.ts` — 6 个方法(getBySession/create/update/confirmAndAdvance/delete/getOrCreate)
- 接收 `Database.Database`(同步 better-sqlite3)
- JSON 字段(已处理):completed_actions / completed_tasks / active_problems / next_suggested_actions / locked_syndromes / active_training_meta
- 状态机在 `teaching-state-machine.ts`(本任务**不动**状态机)
- 调用方众多:TeachingStateService、teaching-state-subscriber、各 domain

### 0.2 shared 端(待新建)
- `src/shared/services/teaching-state.service.ts` — 尚不存在
- 渲染层不直接调 service,通过 IPC 走主进程

### 0.3 表结构(实际生产环境,跨多 migration 累积)
```sql
-- app-initializer.ensureBaseSchema 中创建
-- 后续 025_teaching_state_active_training.sql 增加 active_training_meta 列
CREATE TABLE IF NOT EXISTS teaching_state (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL UNIQUE,
  current_phase TEXT NOT NULL DEFAULT 'P0_INIT',
  current_subphase TEXT,
  completed_actions TEXT DEFAULT '[]',         -- JSON
  completed_tasks TEXT DEFAULT '[]',            -- JSON
  active_problems TEXT DEFAULT '[]',            -- JSON
  next_suggested_actions TEXT DEFAULT '[]',     -- JSON
  current_task_id TEXT,
  diagnosis_summary TEXT DEFAULT '',
  last_user_confirmation TEXT,
  focus_area TEXT DEFAULT NULL,
  transition_offered INTEGER DEFAULT 0,
  locked_syndromes TEXT DEFAULT '[]',           -- JSON
  active_training_meta TEXT DEFAULT NULL,       -- JSON (Sprint 23 G-1)
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);
```

### 0.4 BetterSqliteAdapter 当前 schema(不匹配,需修正)
```sql
-- src/shared/storage/adapters/better-sqlite.adapter.ts (当前简版,字段不足)
CREATE TABLE IF NOT EXISTS teaching_state (
  session_id TEXT PRIMARY KEY,
  current_phase TEXT NOT NULL DEFAULT 'idle',
  active_training_id TEXT,
  last_event_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);
```

---

## 1. 实施步骤

### Step 1: 修正 `src/shared/storage/adapters/better-sqlite.adapter.ts` teaching_state schema

按 0.3 实际 schema 修正 initSchema,保证双端 schema 一致。

### Step 2: 新建 `src/shared/services/teaching-state.service.ts`

```typescript
export class TeachingStateService {
  constructor(private readonly adapter: StorageAdapter) {}

  async getBySession(sessionId: string): Promise<TeachingState | null> { ... }
  async create(input: CreateTeachingStateInput): Promise<TeachingState> { ... }
  async update(sessionId: string, updates: Partial<...>): Promise<TeachingState | null> { ... }
  async getOrCreate(sessionId: string): Promise<TeachingState> { ... }
  async delete(sessionId: string): Promise<boolean> { ... }
}
```

要点:
- 内部行类型 `TeachingStateRow` 用 snake_case
- 公开返回 `TeachingState` 用 camelCase
- JSON 字段在 service 层自动 parse/stringify
- 使用 `new Date().toISOString()` 作为 updatedAt
- `currentPhase` 默认 `'P0_INIT'`(对齐生产)
- `currentSubphase` 默认 `'S1_PROTAGONIST'`
- `transitionOffered` 用 boolean ↔ INTEGER 0/1 转换

### Step 3: 单测 `src/shared/services/__tests__/teaching-state.service.test.ts`

- 使用 `BetterSqliteAdapter(:memory:)`
- 覆盖 getBySession(空表/有表) / create / update(部分字段) / getOrCreate / delete
- JSON 字段验证:写入后读回是 object
- ≥ 6 用例

### Step 4: 4 道门禁

```bash
npm run typecheck && npm run test && npm run lint
```

### Step 5: 主进程对接(可选,R-010 最小化原则下不强制)

**不在 T26-2.3 范围内**。现有主进程 TeachingStateStore(同步)继续工作,共享 service 作为"未来 Android WebView 入口"。

理由:TeachingStateStore 调用方众多(20+ 处),同步改异步是侵入性变更。S26 阶段 4(IPC 移除)时再统一迁移。

---

## 2. 范围与边界

### 在范围内
- 修正 BetterSqliteAdapter teaching_state schema
- 新建 src/shared/services/teaching-state.service.ts
- 新增 src/shared/services/__tests__/teaching-state.service.test.ts

### 不在范围内
- ❌ 改主进程 TeachingStateStore(同步版保留,标 @deprecated,推 S26 阶段 4)
- ❌ 改主进程 TeachingStateService / 状态机(本任务不动)
- ❌ 改 IPC handler(仍走 TeachingStateService → TeachingStateStore)
- ❌ 改其他 2 张表(training_records / active_training)
- ❌ 改 BetterSqliteAdapter 其他 4 张表

---

## 3. DoD(完成标准)

- [ ] DoD-1: BetterSqliteAdapter teaching_state schema 与实际生产一致
- [ ] DoD-2: src/shared/services/teaching-state.service.ts 新建完成
- [ ] DoD-3: 单测 ≥ 6 用例全部通过
- [ ] DoD-4: typecheck 0 errors
- [ ] DoD-5: lint 0 errors
- [ ] DoD-6: test 全绿(包含新单测 + 旧单测不退化)
- [ ] DoD-7: 提交干净,无 console error

---

## 4. 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| teaching_state 字段多(JSON 数组) | 测试覆盖不全 | 至少 1 个用例验证 JSON 字段读写 |
| 现有主进程仍用 sync TeachingStateStore | 新旧并存,理解负担 | service 文件顶部明示"shared 版,主进程暂未切换" |
| updatedAt 时间格式(ISO TEXT vs INTEGER) | 跨端不一致 | 保持 ISO TEXT(对齐生产) |
| 状态机耦合 | 共享 service 只做 CRUD | 不暴露 confirmPhase 之类状态机方法 |

---

## 5. 预估工作量

- Step 1: 5 分钟(schema 修正)
- Step 2: 30 分钟(service + 类型 + JSON 转换)
- Step 3: 25 分钟(单测)
- Step 4: 5 分钟(门禁)

总计: ~1 小时
