# T26-2.4 Plan: training_records 表迁移(主进程 → StorageAdapter 共享)

> **目标**: 把 `TrainingRecordService`(同步 better-sqlite3)的数据访问逻辑抽离到 `src/shared/services/training-record.service.ts`,实现异步 + 双端共用
> **依据**: T26-2.1/2.2/2.3 模式 + Sprint 26 plan §1.2
> **R-010**: 最小化,只新建 1 个 service + 修正 1 个 schema + 新增 1 个测试

---

## 1. 现状分析

### 1.1 表现状(混乱)
- **生产表名**:`user_training_records`(被 `src/main/domains/04-validation/training/training-record.service.ts` 使用)
- **better-sqlite.adapter.ts**:定义了 `training_records` 表(简化的字段:id, session_id, challenge_id, flow_type, passed, score, feedback, started_at, completed_at)— **与生产 schema 不一致,从未被使用**
- **app-initializer.ts ensureBaseSchema**:定义 `user_training_records` 表(字段:id, session_id, task_id, syndrome_id, status, assigned_at, completed_at, user_response, ai_feedback, effectiveness, score)— **无 task_type 字段**(020_db_add_task_type.sql 才加)
- **TrainingRecordService 的 INSERT/SELECT**:包含 `task_type` 字段(020_db_add_task_type.sql 后)

### 1.2 字段需求对齐
| 字段 | TrainingRecordService | app-initializer schema | 020_db_add_task_type.sql | 统一后(better-sqlite.adapter)|
|------|----------------------|----------------------|-------------------------|------------------------------|
| id | TEXT PK | TEXT PK | - | TEXT PK |
| session_id | TEXT NOT NULL | TEXT NOT NULL | - | TEXT NOT NULL |
| task_id | TEXT NOT NULL | TEXT NOT NULL | - | TEXT NOT NULL |
| syndrome_id | TEXT NOT NULL | TEXT NOT NULL | - | TEXT NOT NULL |
| status | TEXT CHECK | TEXT CHECK | - | TEXT NOT NULL CHECK |
| assigned_at | TEXT NOT NULL | TEXT NOT NULL | - | TEXT NOT NULL |
| completed_at | TEXT NULL | TEXT NULL | - | TEXT NULL |
| user_response | TEXT NULL | TEXT NULL | - | TEXT NULL |
| ai_feedback | TEXT NULL | TEXT NULL | - | TEXT NULL |
| effectiveness | INTEGER (1-5) | INTEGER (1-5) | - | INTEGER |
| score | INTEGER NULL | INTEGER NULL | - | INTEGER NULL |
| **task_type** | TEXT NOT NULL | (未定义) | TEXT NOT NULL DEFAULT 'writing' | TEXT NOT NULL DEFAULT 'writing' CHECK |

**结论**:better-sqlite.adapter.ts 需重命名为 `user_training_records` 并采用 020 migration 后的完整 schema。

---

## 2. 实施步骤

### 2.1 步骤 1: 修正 better-sqlite.adapter.ts schema
- 把 `training_records` 表(简化)删除/重命名为 `user_training_records`
- 字段对齐 TrainingRecordService 的实际使用(包括 `task_type`)
- 添加 3 个索引(session_id+assigned_at / task_id / session_id+status)
- **R-010 最小化**:只改 1 个文件,不改其他表

### 2.2 步骤 2: 新建 src/shared/services/training-record.service.ts
参考 teaching-state.service.ts 模式:
- 类签名:`class TrainingRecordService`
- 构造函数:`constructor(private readonly adapter: StorageAdapter)`
- 核心方法(异步):
  - `assign(input: Omit<TrainingRecord, 'id' | 'status' | 'assignedAt' | 'completedAt'>): Promise<TrainingRecord>` — INSERT
  - `complete(id, updates): Promise<TrainingRecord | null>` — UPDATE
  - `skip(id): Promise<TrainingRecord | null>` — UPDATE
  - `getById(id): Promise<TrainingRecord | null>` — SELECT
  - `getBySession(sessionId): Promise<TrainingRecord[]>` — SELECT
  - `getAll(): Promise<TrainingRecord[]>` — SELECT
  - `deleteBySession(sessionId): Promise<number>` — DELETE(返回删除行数)
- rowToRecord / recordToRow 投影函数
- 生成 ID:`${sessionId}_${taskId}_${Date.now()}`(沿用主进程原逻辑)
- 防御性:INSERT 缺失字段(allowPartialUpdates)沿用主进程 COALESCE 模式

### 2.3 步骤 3: 编写 src/shared/services/__tests__/training-record.service.test.ts
- 8 个测试用例(≥ 6 是 plan 要求):
  1. `assign`: 创建新记录,返回 id 格式正确
  2. `getById`: 找到/找不到
  3. `getBySession`: 返回该 session 全部记录
  4. `getAll`: 跨 session 聚合
  5. `complete`: 标记完成,更新字段
  6. `complete`: 找不到时返回 null
  7. `skip`: 标记跳过
  8. `deleteBySession`: 批量删除,返回行数
- 预创建 session 满足 FK 约束

### 2.4 步骤 4: 验证门禁
- `npx vitest run src/shared/services/__tests__/training-record.service.test.ts` 全绿
- `npm run typecheck` 0 错误
- `npm run lint` 0 errors(warnings 可接受,属 D-073 治理范围)

---

## 3. 范围与边界(R-010)

### 3.1 范围内
- ✅ 修正 better-sqlite.adapter.ts 的 training_records → user_training_records(表名 + schema)
- ✅ 新建 src/shared/services/training-record.service.ts(异步 + 双端共用)
- ✅ 编写 8 个测试用例
- ✅ 新建本 plan 文档

### 3.2 范围外(明确不做)
- ❌ 不动 src/main/domains/04-validation/training/training-record.service.ts(主进程同步版,主进程侧状态机逻辑保留)
- ❌ 不动 app-initializer.ts(生产 schema 仍由 ensureBaseSchema 维护,本轮不强制统一)
- ❌ 不改造 training.handler.ts(主进程 IPC handler 暂保持调用同步 service)
- ❌ 不动 T26-2.3 之前的 4 张表(sessions / projects / teaching_state / active_training)
- ❌ 不动其他依赖 training-record.service 的代码(避免连带改造)

### 3.3 风险
- **schema 不一致**:better-sqlite.adapter.ts 改 user_training_records 后,与 app-initializer.ts 的 ensureBaseSchema 存在差异(缺 task_type)。两处 schema 都执行 `IF NOT EXISTS`,所以不会冲突,但需要明确这是 T26 的开发态。
  - **缓解**:在 better-sqlite.adapter.ts 注释中明确"开发态,生产 schema 由 ensureBaseSchema 维护"
  - **S27+ 治理**:统一两处 schema(独立任务)

---

## 4. DoD

```
T26-2.4 完成判定:
□ 1. better-sqlite.adapter.ts 中表名 + schema 与 020_db_add_task_type.sql 后对齐
□ 2. src/shared/services/training-record.service.ts 新建,7 个核心方法
□ 3. 8 个测试用例全绿
□ 4. npm run typecheck 0 错误
□ 5. npm run lint 0 errors
□ 6. 主进程 service-config.ts 不动(暂不强制主进程切换)
□ 7. plan 文档提交
```

---

## 5. 后续任务

- **T26-2.5**: active_training 表迁移(最复杂,Sprint 24 A 轨刚做完)
- **T26-阶段 3**: 集成测试 + UI 验证 + E2E
- **T26-阶段 4**: 27 个 IPC 通道移除
- **S27+ 治理**: D-073 (warnings 治理) + 双端 schema 统一

---

## 6. 决策依据

- **D-074**: Sprint 26 战略转向 — Electron → Capacitor Android 双端复用
- **R-010**: 最小化范围,只做 1 张表迁移
- **R-020**: 循环依赖零容忍
- **R-029**: 安全与隐私(无密钥处理)
- **plan §1.2**: 5 张核心表迁移步骤
