# T26-2.5 Plan: active_training 表迁移(主进程 → StorageAdapter 共享)

> **目标**: 把 `ActiveTrainingStore`(同步 better-sqlite3)的数据访问逻辑抽离到 `src/shared/services/active-training.service.ts`,实现异步 + 双端共用
> **依据**: T26-2.1/2.2/2.3/2.4 模式 + Sprint 26 plan §1.2
> **R-010**: 最小化,只新建 1 个 service + 新增 1 个测试
> **状态**: T26 阶段 2 最后一张表(5/5)

---

## 1. 现状分析

### 1.1 已对齐
- better-sqlite.adapter.ts 中 active_training 表 schema 已对齐生产(195-224 行,026 + 027 migration)
- 字段:id, session_id, challenge_id, challenge_name, mode, current_step_index, steps_json, user_draft, flow_type, training_flow_json, record_id, syndrome_id, original_quote, constraint_text, submission_result_json, step_responses_json, status, started_at, updated_at, completed_at
- 索引:idx_active_training_status(单 status 列)

### 1.2 主进程 store 接口(需迁移)
src/main/domains/03-teaching/state/active-training.store.ts 暴露 6 个方法:
- `getBySession(sessionId)` — 最新一行(任意状态,按 id DESC)
- `getActiveBySession(sessionId)` — status = in_progress
- `create(input)` — INSERT + 业务规则(同 session 已有 in_progress 则先 abort)
- `update(sessionId, updates)` — UPDATE 部分字段
- `delete(sessionId)` — 硬删除(特殊场景)
- `updateStepResponses(sessionId, stepResponses)` — C-4 5 步分步回答整数组替换
- `listActive()` — 全局 in_progress 查询
- `findBySyndrome(syndromeId)` — 按症候查询

### 1.3 JSON 字段
- `steps_json` TEXT NOT NULL DEFAULT '[]' → TrainingStep[]
- `training_flow_json` TEXT NULL → TrainingFlow | null
- `submission_result_json` TEXT NULL → SubmissionResultSnapshot | null
- `step_responses_json` TEXT NOT NULL DEFAULT '[]' → StepResponse[]

服务层负责 parse/stringify(防御性:解析失败回退默认值 + console.warn)

---

## 2. 实施步骤

### 2.1 步骤 1: 新建 src/shared/services/active-training.service.ts
参考 teaching-state.service.ts / training-record.service.ts 模式:
- 类签名:`class ActiveTrainingService`
- 构造函数:`constructor(private readonly adapter: StorageAdapter)`
- 核心方法(异步,8 个):
  - `getBySession(sessionId): Promise<ActiveTraining | null>` — 最新一行
  - `getActiveBySession(sessionId): Promise<ActiveTraining | null>` — in_progress
  - `create(input: CreateActiveTrainingInput): Promise<ActiveTraining | null>` — INSERT
  - `update(sessionId, updates): Promise<ActiveTraining | null>` — UPDATE
  - `updateStepResponses(sessionId, stepResponses): Promise<ActiveTraining | null>`
  - `delete(sessionId): Promise<boolean>`
  - `listActive(): Promise<ActiveTraining[]>` — 全局 in_progress
  - `findBySyndrome(syndromeId): Promise<ActiveTraining[]>`
- rowToActiveTraining / activeTrainingToRow 投影(独立于主进程 store)
- safeParseJson 防御性解析(失败回退 + warn)
- 异常隔离:方法不抛错,失败返回 null/空数组 + console.error(R-028)

### 2.2 步骤 2: 编写 src/shared/services/__tests__/active-training.service.test.ts
- 8 个测试用例(≥ 6 是 plan 要求):
  1. `create`: 创建 in_progress 行,返回 id 自增
  2. `getBySession`: 找到/找不到
  3. `getActiveBySession`: 找到 in_progress
  4. `getActiveBySession`: 状态 completed 应返回 null
  5. `update`: 部分更新 + updatedAt 推进
  6. `updateStepResponses`: C-4 5 步回答整数组替换
  7. `listActive`: 全局 in_progress 查询
  8. `findBySyndrome`: 按症候查询
  9. `delete`: 成功/二次删除
- 预创建 session 满足 FK 约束
- 验证 JSON 字段(steps / stepResponses)自动 parse/stringify

### 2.3 步骤 3: 验证门禁
- `npx vitest run src/shared/services/__tests__/active-training.service.test.ts` 全绿
- `npm run typecheck` 0 错误
- `npm run lint` 0 errors(warnings 维持 282 不变)

---

## 3. 范围与边界(R-010)

### 3.1 范围内
- ✅ 新建 src/shared/services/active-training.service.ts(异步 + 双端共用,仅 CRUD)
- ✅ 编写 9 个测试用例
- ✅ 新建本 plan 文档
- ✅ better-sqlite.adapter.ts 中 active_training schema 已在 T26 阶段 1 落地,本任务不动

### 3.2 范围外(明确不做)
- ❌ 不动 src/main/domains/03-teaching/state/active-training.store.ts(主进程同步版,状态机入口 store 仍由主进程调用)
- ❌ 不动 src/main/domains/03-teaching/state/active-training.service.ts(状态机业务逻辑:start/advanceStep/submitFlowStep/updateDraft/evaluate/complete/abort + onStateChange 全部保留)
- ❌ 不动 app-initializer.ts(生产 schema 仍由 ensureBaseSchema 维护)
- ❌ 不改造 training handler / active-training.handler.ts(主进程 IPC handler 仍调用主进程 service)
- ❌ 不动其他 4 张已迁移表

### 3.3 风险
- **JSON 字段一致性**:新 service 的 rowToActiveTraining 必须与主进程 store 保持完全一致(字段映射、默认值、null 守卫)。不一致会导致 Android 端数据失真。
  - **缓解**:复制主进程 rowToActiveTraining 逻辑,保留 `safeParseJson` 防御性 + `isValidActiveTrainingStatus` 守卫
  - **测试覆盖**:JSON 字段(steps/stepResponses)读写一致性
- **状态机不复制**:本任务仅做 CRUD,**不**包含 start/advanceStep 等状态机方法。Android 端需要时由 Android 侧 controller 自行编排,或后续 Sprint 提供状态机移植。
  - **决策**: Android 端训练流 UI 可直接调用 service 的 create/update/list,状态机由 renderer 侧 store 维护(Sprint 24 A-4 已有先例)

---

## 4. DoD

```
T26-2.5 完成判定:
□ 1. src/shared/services/active-training.service.ts 新建,8 个核心方法(纯 CRUD)
□ 2. 9 个测试用例全绿
□ 3. npm run typecheck 0 错误
□ 4. npm run lint 0 errors
□ 5. 主进程 service-config.ts / active-training.store.ts / active-training.service.ts 不动
□ 6. plan 文档提交
□ 7. 阶段 2 收尾决策:5 张表迁移完毕,准备进入阶段 3(集成测试)
```

---

## 5. 阶段 2 收尾

T26-2.5 完成后,5 张核心表全部迁移完毕:
- ✅ sessions (T26-2.1)
- ✅ projects (T26-2.2)
- ✅ teaching_state (T26-2.3)
- ✅ user_training_records (T26-2.4)
- ✅ active_training (T26-2.5)

**下一步**: 阶段 3(集成测试 + UI 验证 + E2E)+ 阶段 4(27 个 IPC 通道移除)

---

## 6. 决策依据

- **D-074**: Sprint 26 战略转向 — Electron → Capacitor Android 双端复用
- **R-010**: 最小化范围,只做 1 张表迁移
- **R-020**: 循环依赖零容忍(独立定义 TrainingStep/TrainingFlow,不复用主进程)
- **R-028**: 防御性编码(异常隔离 + JSON 解析守卫)
- **plan §1.2**: 5 张核心表迁移步骤
- **Sprint 24 A-2/D-070**: 状态机边界(Complete/Abort 保留行供审计)
