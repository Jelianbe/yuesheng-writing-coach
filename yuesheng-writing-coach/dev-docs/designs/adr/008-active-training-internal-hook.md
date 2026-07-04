# ADR-008: ActiveTrainingService 内部 hook 决策（vs event-bus 订阅）

> **状态**: Accepted
> **日期**: 2026-07-04
> **关联**: Sprint 25 Issue #42 / #43 / dev-docs/tasks/sprint-25-plan.md
> **决策者**: AI 架构师（用户确认）

## 背景

Sprint 25 需要在 ActiveTrainingService 状态机基础上增加两个能力：
- **C-1**: 训练草稿版本历史（每次 step 推进快照）
- **C-2**: 状态机状态变化审计日志

两种实现方案：
- **方案 A**: service 内部 hook（在状态转换方法中直接调用 snapshotDraft + recordAudit）
- **方案 B**: event-bus 订阅（service 发出状态转换事件，外部订阅者处理）

## 评估

### 方案 A：service 内部 hook

**优点**:
- 事务一致性：状态转换 + 快照/审计写入要么都成功要么都失败
- 简单：无需新模块，依赖少
- 同步写入：失败立即可见，便于调试
- 性能可控：单次状态转换 2 次 SQL 写入（草稿 + 审计）

**缺点**:
- service 类膨胀（5 个状态转换方法都要加 hook）
- 违反"单一职责"原则（service 同时管状态机 + 快照 + 审计）

### 方案 B：event-bus 订阅

**优点**:
- 职责分离：service 只管状态机，快照/审计由独立订阅者处理
- 可扩展：未来加新订阅者（统计/通知/分析）无需改 service

**缺点**:
- 事务一致性难保证：event-bus 异步，状态转换成功 + 订阅失败 → 数据不一致
- 复杂度高：需要 event-bus 模块 + 订阅注册 + 重试机制
- 调试困难：异步事件链路长，丢消息难追查
- 性能开销：序列化 + 队列 + 反序列化

## 决策

**采用方案 A**（service 内部 hook）。

**理由**:
1. 事务一致性优先：草稿快照是用户内容丢失不可接受，审计日志是关键证据
2. 复杂度优先：Sprint 25 范围 2 周，event-bus 改造至少 +1 周
3. 性能可接受：同步 2 次 SQL 写入（草稿 + 审计），在 SQLite 本地 < 5ms
4. 调试友好：同步链路易追踪

## 实施

在 ActiveTrainingService 的 6 个方法中加 hook：
1. `start()` → recordAudit('start', null, 'InProgress', 'main', {challengeId})
2. `advanceStep(sessionId, stepIndex)` → snapshotDraft(...) + recordAudit('advance', ...)
3. `evaluate(sessionId, submission)` → snapshotDraft(...) + recordAudit('evaluate', ...)
4. `complete(sessionId, recordId)` → snapshotDraft(...) + recordAudit('complete', ...)
5. `abort(sessionId)` → recordAudit('abort', 'InProgress', 'Aborted', 'main', {})
6. `restoreDraft(trainingId, draftId)` → snapshotDraft(..., trigger='restore', restoredFromId) + recordAudit('restore', ...)

## 风险与对策

| 风险 | 对策 |
|:-----|:-----|
| service 类膨胀（5 状态转换方法都要改） | 抽象 `private withHook()` 高阶函数包裹状态转换 |
| 同步写入性能问题 | 监控 P99 延迟，超过 50ms 考虑异步化 |
| 审计/快照失败影响状态转换 | 草稿快照 try/catch 失败不阻塞；审计失败抛错让业务层决策 |

## 备选方案

如果未来需要解耦，可考虑：
- 方案 C: 状态转换完成后发出 domain event（同步事件总线，非异步队列）
- 方案 D: 数据库 trigger（SQLite trigger 监听 active_training 表）

## 关联

- Sprint 25 plan: dev-docs/tasks/sprint-25-plan.md
- Issue #42 C-1 训练草稿版本历史
- Issue #43 C-2 状态机审计日志
- Sprint 24 A 轨 ActiveTrainingService（commit 55d4867）
