# Sprint 24 计划 — A 轨：ActiveTrainingSession 完整化

> **核心目标**: 把 Sprint 23 G 轨的"业务元数据"升级为"完整状态机"主进程化,让 ActiveTrainingSession 真正可审计、可恢复、可跨设备同步。
> **依据**: D-069 S24 候选清单 + 用户确认 A 轨
> **开始日期**: 2026-07-03
> **完成日期**: (进行中)
> **R-010**: 每阶段最小化,5 阶段串行交付

---

## 0. 范围与边界

### 0.1 目标
让 `ActiveTrainingSession` 从 renderer-only Zustand store 升级为主进程持久化状态机:
- ✅ 可审计(主进程侧完整状态变化历史)
- ✅ 可恢复(异常退出后能从 SQLite 恢复当前训练会话)
- ✅ 可跨 sessionId 查询(目前训练仅在当前会话)
- ✅ 训练草稿持久化(目前只存 renderer,刷新即失)

### 0.2 不在范围
- ❌ 跨设备同步(网络层)
- ❌ 多训练并发(同一 session 同时多个挑战)— 保持单训练
- ❌ 训练草稿版本历史(只保留最新草稿 + 上次完成时的草稿)
- ❌ 协作训练(多人共编)

### 0.3 当前现状(Sprint 23 G-1 收尾时)
- `TeachingState.activeTrainingMeta: ActiveTrainingMeta` JSON 字段 — 仅记录触发元数据
- `ActiveTrainingSession` 完整状态机仍在 renderer (`renderer/stores/training.store.ts`)
- `userDraft` 训练草稿只存 renderer,刷新即失
- 主进程侧仅承担"哪个 session 进入了训练态 + 关联症候"业务元数据

---

## 1. 阶段划分

### 1.1 A-1: 存储层 — 新增独立 active_training 表

**目标**: 新增 `active_training` 表,替代 `teaching_state.active_training_meta` JSON 字段,支持完整 ActiveTrainingSession 持久化。

**DoD**:
1. ✅ `026_active_training.sql` migration 文件,新增 `active_training` 表
2. ✅ `ActiveTrainingStore` (主进程侧 SQLite 访问层): create/getBySession/update/delete
3. ✅ `ActiveTrainingRow` 类型 + 行↔领域对象转换
4. ✅ 单测覆盖:CRUD 正常路径 + 异常隔离(至少 8 用例)
5. ✅ 集成测试: capability-graph-e2e / student-model-persistence 内存 DB schema 同步添加新表

**字段设计**:
```sql
CREATE TABLE active_training (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL UNIQUE,
  challenge_id TEXT NOT NULL,
  challenge_name TEXT,
  mode TEXT,
  current_step_index INTEGER DEFAULT 0,
  steps_json TEXT NOT NULL,         -- TrainingStep[]
  user_draft TEXT DEFAULT '',       -- 训练草稿(持久化核心)
  flow_type TEXT,                   -- 'flow5' | 'legacy'
  training_flow_json TEXT,          -- TrainingFlow (S8 通用流)
  record_id TEXT,                   -- 关联 training_records.id
  syndrome_id TEXT,
  original_quote TEXT,
  constraint TEXT,
  submission_result_json TEXT,     -- 上次评估结果
  status TEXT NOT NULL DEFAULT 'in_progress', -- in_progress | completed | aborted
  started_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);
```

**R-010 最小化**:
- 不修改 `teaching_state.active_training_meta` 字段(保留供 Sprint 23 G-1 业务元数据使用,记录 trigger 信息)
- 不创建独立 `active_training_history` 表(状态变化历史推 S25)
- `steps_json` 一次性序列化,不拆分子表(查询用 JSON_EXTRACT)

---

### 1.2 A-2: 状态机层 — ActiveTrainingService (主进程)

**目标**: 新建 `ActiveTrainingService` (主进程侧状态机),订阅 `training_triggered` 事件,在主进程侧维护 ActiveTrainingSession 状态机。

**DoD**:
1. ✅ `ActiveTrainingService` 类: 封装 `ActiveTrainingStore`,提供状态机方法
2. ✅ 方法集: `start()` / `advanceStep()` / `updateDraft()` / `evaluate()` / `complete()` / `abort()` / `getActive()`
3. ✅ 订阅 `OrchestratorEvent['training_triggered']` 事件 → 调用 `start()` 创建 ActiveTraining
4. ✅ 状态机规则文档: 5 个有效状态 + 5 个转换边界
5. ✅ 单测覆盖: 状态机转换正常路径 + 非法转换拒绝(至少 10 用例)
6. ✅ 集成测试: 真实 ChatOrchestratorService → training_triggered → ActiveTrainingService.start → SQLite 写入

**状态机定义** (5 状态 + 5 转换):
```
[None] --training_triggered+challengeId--> [InProgress]
[InProgress] --advanceStep(stepIndex)--> [InProgress] (currentStepIndex 更新)
[InProgress] --evaluate(submission)--> [InProgress] (submissionResult 更新)
[InProgress] --complete(recordId)--> [Completed] (completed_at 写入)
[InProgress] --abort()--> [Aborted] (status='aborted',清空 userDraft)
[Completed/Aborted] --DELETE 行--> [None] (后续 start 创建新行)
```

**R-010 最小化**:
- 不实现 IPC handler 暴露(A-4 阶段才暴露)
- 不实现草稿自动保存(A-3 阶段)
- 状态机逻辑直接在 service 中,不抽 `state-machine` 子模块

---

### 1.3 A-3: 草稿持久化 — updateDraft 自动保存

**目标**: renderer `updateDraft` 每次调用都推主进程 save,主进程侧 SQLite 持久化 userDraft,刷新页面/异常退出后能恢复。

**DoD**:
1. ✅ 新增 IPC 频道: `activeTraining:updateDraft` (request/response 模式,带 ack)
2. ✅ renderer 端 debounce 500ms(避免每键击一次 IPC)
3. ✅ 主进程侧 `ActiveTrainingService.updateDraft(sessionId, content)`,SQLite UPDATE
4. ✅ 异常隔离: 任何错误仅 console.error,不阻塞 UI
5. ✅ 单测覆盖: debounce 行为 + 持久化正确性(至少 5 用例)
6. ✅ 集成测试: 模拟 renderer 多次 updateDraft → 主进程 SQLite 读取验证

**R-019 硬上限**:
- 草稿长度上限 50,000 字符(SQLite TEXT 类型支持 1GB,实际产品约束)
- 防抖窗口 500ms (R-028 防御性)

---

### 1.4 A-4: 渲染层订阅模式 — renderer store 订阅主进程推送

**目标**: renderer 侧 ActiveTrainingSession 仍存 store,但 store 内容来源改为订阅主进程推送(IPC event),不再直接持有 source-of-truth。

**DoD**:
1. ✅ renderer 侧 store 改造: actions 改调 `getInvoke()(...)`,不再本地持有 transitions 逻辑
2. ✅ 新增 IPC event 频道: `activeTraining:updated` (主进程 → renderer 推送状态变化)
3. ✅ store 在 mount 时主动 fetch 当前 session 状态(从主进程拉取,避免冷启动缺失)
4. ✅ 单测覆盖: store 订阅 + fetch 行为(至少 6 用例)
5. ✅ E2E 测试: 完整 start → 推进 → 草稿 → 评估 → complete 链路
6. ✅ 旧的 `activeTraining: ...` 初始值改 null(主进程推送填充)

**R-010 最小化**:
- 不实现乐观更新(等主进程 ack 后再更新 store)
- 不实现冲突解决(单用户单设备,无冲突场景)

---

## 2. 关键决策

### 2.1 决策 1: 不替换 teaching_state.active_training_meta 字段

**背景**: `active_training_meta` JSON 字段记录"哪个 session 进入了训练态 + 关联症候",是 trigger 元数据。
**决策**: 保留 `active_training_meta` 字段(A-1 不删除),新增独立 `active_training` 表。
**理由**:
- `active_training_meta` 用审计/查询(轻量,业务元数据)
- `active_training` 表用状态机(重量,完整状态)
- 两者职责不同,不应混用
**实施**: 022_teaching_state_active_training.sql 不动,026_active_training.sql 新建

### 2.2 决策 2: 状态机边界 — Complete/Abort 不可恢复

**背景**: 训练完成后,用户可以重新开始新训练,但旧训练记录应保留。
**决策**: Complete/Abort 状态保留行,不删除;新训练开始时若 sessionId 已存在 ActiveTraining,先 abort 旧的。
**理由**:
- 保留完整历史供审计
- 用户主动 abort 时不丢失已写数据
- 新训练覆盖旧训练需明确动作,不静默
**实施**: `start()` 方法检查 sessionId 唯一性,存在则先 abort

### 2.3 决策 3: 草稿保存策略 — 500ms debounce + 字符上限 50K

**背景**: userDraft 是高频更新字段(用户每输入一个字符),直推主进程会刷屏。
**决策**: renderer 端 debounce 500ms,主进程侧无字符上限但记录警告日志(>50K 提示)。
**理由**:
- 防抖 500ms 是业界通用折中(平衡实时性与流量)
- 50K 字符足够 1 万字中文训练草稿
- 异常隔离: 防抖丢失最后 < 500ms 输入可接受(产品决策)
**实施**: renderer 用 lodash.debounce 或自实现 setTimeout,主进程侧 console.warn > 50K

### 2.4 决策 4: 渲染层最终形态 — 订阅模式但保留本地乐观更新

**背景**: A-4 要把 store 改为订阅模式,但完全去除本地状态会导致输入延迟。
**决策**: store 维持本地活跃变量,但每次写操作同时推主进程(主进程为准),主进程 ack 后 store 同步。
**理由**:
- 训练草稿输入需即时响应(不能等 IPC)
- 状态机操作(advanceStep/evaluate/complete)可等 ack
- 简单区分: 本地状态 + 远端权威
**实施**: userDraft 本地 store 直接更新(不等 ack),其他状态操作等 ack 后 store 更新

---

## 3. 门禁

### 3.1 每阶段门禁
- typecheck: 0 errors
- vitest: 当前数 + 该阶段新增 ≥ DoD 数
- lint: 0 errors
- 集成测试: 至少 1 个端到端用例

### 3.2 Sprint 24 全局门禁
- typecheck: 0 errors
- vitest: 当前 881 + Sprint 24 新增 ≥ 35 用例(8+10+5+6+集成 6)
- lint: 0 errors
- E2E: 至少 2 个端到端训练生命周期(start→complete, start→abort)
- 决策日志 D-070 更新

### 3.3 验收清单
- [ ] 026 migration 在 dev 库 + 测试内存 DB 都能应用
- [ ] ActiveTraining 状态机主进程侧独立可测(无需启动 renderer)
- [ ] renderer store 冷启动时从主进程 fetch 状态
- [ ] userDraft 刷新页面后能恢复
- [ ] Complete/Abort 后行保留供审计
- [ ] 4 道门禁全绿
- [ ] 决策日志 D-070 实施结果 + 复盘 + S25 候选

---

## 4. 实施计划

| 阶段 | 任务 | 预计改动 | DoD 单元数 |
|:----:|:-----|:--------|:--------:|
| A-1 | 新建 active_training 表 + ActiveTrainingStore | 4 新文件 + 3 测试修复 | 8 |
| A-2 | ActiveTrainingService 状态机 | 2 新文件 + 1 集成测试 | 10 |
| A-3 | 草稿持久化 IPC + debounce | 2 新文件 + 1 IPC 注册 | 5 |
| A-4 | renderer 订阅模式 + E2E | 3 文件改造 + 1 E2E | 6 + 2 E2E |

---

## 5. 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| 状态机边界遗漏 | 状态机进入非法状态 | A-2 单测覆盖所有 5 转换 + 拒绝非法转换 |
| 草稿 debounce 丢失 | 用户最后输入未保存 | 字符上限 50K 防极端;Product 接受 < 500ms 丢失 |
| 主进程→renderer 推送失败 | renderer store 过期 | store 在 mount 时主动 fetch(冷启动恢复) |
| renderer 旧 store 残留 | 双源真相冲突 | A-4 改造时一次性清除旧 initial value,改 null |
| 训练跨 sessionId 复用 | active_training 唯一约束冲突 | A-2 start() 方法先 abort 旧训练 |

---

## 6. 后续候选(S25+)

- S25 候选: 训练草稿版本历史(每次 step 推进快照)
- S25 候选: 状态机状态变化审计日志
- S25 候选: ActiveTraining 迁移到独立 service (拆出 teaching domain)
- S26+ 候选: 跨设备同步(网络层)
- S26+ 候选: 训练协作(多人共编)
