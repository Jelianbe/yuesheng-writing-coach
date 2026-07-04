# Sprint 25 计划 — 保守组合：草稿版本历史 + 状态机审计日志

> **核心目标**: 在 Sprint 24 A 轨 ActiveTrainingService 状态机基础上，增加"可回退"和"可审计"两个关键能力。
> **依据**: Issue #41 范围锁定 + Issue #42（C-1）+ Issue #43（C-2）
> **开始日期**: 2026-07-04
> **完成日期**: 待定（预估 ~2 周）
> **R-010**: 每阶段最小化，C-1 / C-2 串行交付（先 C-1 后 C-2）

---

## 0. 范围与边界

### 0.1 目标
让 ActiveTrainingService 同时具备两个新增能力：
- ✅ **可回退**: 用户可回退到任意历史 step 的草稿（C-1）
- ✅ **可审计**: 状态变化全留痕，可查询最近 N 条转换（C-2）

### 0.2 不在范围
- ❌ 草稿 diff 可视化（UI 阶段，S26+）
- ❌ 跨训练回退（同一 active_training 范围内）
- ❌ 协作撤销 / CRDT（S26+ 训练协作）
- ❌ 审计日志导出/报表（UI 阶段，S26+）
- ❌ 审计日志归档/压缩（暂不实现，避免过度设计）
- ❌ 多用户身份追踪（user_id 场景，S26+ 跨设备同步时再实现）

### 0.3 当前现状（Sprint 24 收尾时）
- `active_training` 表已存在（commit 29842df / 026 migration）
- `ActiveTrainingService` 5 状态 + 5 转换（commit 55d4867）
- `userDraft` 字段仅保留"当前最新"（无历史）
- 状态转换无审计日志

---

## 1. 阶段划分

### 1.1 阶段 1：C-1 训练草稿版本历史

#### 1.1.1 C-1.1: 存储层 — `active_training_drafts` 表

**目标**: 新增独立快照表，支持每次 step 推进自动快照。

**DoD**:
1. ✅ `027_active_training_drafts.sql` migration 文件
2. ✅ `ActiveTrainingDraftStore` (主进程侧 SQLite 访问层): create/listByTrainingId/getById
3. ✅ `ActiveTrainingDraftRow` 类型 + 行↔领域对象转换
4. ✅ 单测覆盖: CRUD 正常路径 + 异常隔离（≥ 6 用例）
5. ✅ 集成测试: capability-graph-e2e / student-model-persistence 内存 DB schema 同步添加新表

**字段设计**:
```sql
CREATE TABLE active_training_drafts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  active_training_id INTEGER NOT NULL,
  step_index INTEGER NOT NULL,
  content TEXT NOT NULL,
  trigger TEXT NOT NULL,         -- 'advance' | 'evaluate' | 'complete' | 'abort' | 'restore'
  snapshot_at TEXT NOT NULL,
  restored_from_id INTEGER,      -- 如果是 restore 触发，指向原快照
  FOREIGN KEY (active_training_id) REFERENCES active_training(id) ON DELETE CASCADE
);
CREATE INDEX idx_atd_at_id ON active_training_drafts(active_training_id, step_index);
```

**R-010 最小化**:
- 不实现 diff 算法（只存 content，不存 delta）
- 不实现草稿压缩（存原始内容，简单可靠）
- 字符上限 50K（与 userDraft 一致）

---

#### 1.1.2 C-1.2: 快照触发 — service 内部 hook

**目标**: ActiveTrainingService 每次状态转换时同步写入快照。

**DoD**:
1. ✅ service 内部 hook（在 5 个状态转换方法中调用 `snapshotDraft`）
2. ✅ 事务一致性：状态转换 + 快照写入要么都成功要么都失败
3. ✅ 字符上限保护：>50K 警告日志但不阻塞
4. ✅ 单测覆盖: 5 状态转换各自触发快照（≥ 10 用例）
5. ✅ 集成测试: 真实 start → advance → evaluate → complete 链路验证每步有快照

**关键实现**:
```typescript
class ActiveTrainingService {
  private async snapshotDraft(
    activeTrainingId: number,
    stepIndex: number,
    content: string,
    trigger: 'advance' | 'evaluate' | 'complete' | 'abort' | 'restore',
  ): Promise<void> {
    if (content.length > 50000) {
      console.warn(`[ActiveTrainingService] draft length ${content.length} > 50K`);
    }
    await this.draftStore.create({
      activeTrainingId,
      stepIndex,
      content,
      trigger,
      snapshotAt: new Date().toISOString(),
    });
  }

  async advanceStep(sessionId: string, stepIndex: number) {
    // 1. 状态转换
    const updated = await this.store.updateStep(sessionId, stepIndex);
    // 2. 同步快照（事务一致）
    await this.snapshotDraft(updated.id, stepIndex, updated.userDraft, 'advance');
    return updated;
  }
}
```

**R-028 防御性**:
- 快照写入失败不阻塞状态转换（catch + console.error + 不抛）
- 字符 >50K 警告但不阻塞（产品决策：用户内容优先）

---

#### 1.1.3 C-1.3: 快照查询 + 回退 API

**目标**: 提供 IPC 暴露的快照查询和回退能力。

**DoD**:
1. ✅ `listDrafts(trainingId)` API: 返回某次训练的所有快照（按 step_index ASC）
2. ✅ `restoreDraft(trainingId, draftId)` API: 回退到指定快照
3. ✅ IPC 频道: `activeTraining:listDrafts` + `activeTraining:restoreDraft`
4. ✅ renderer 端 store action 对接（可选，S26+ UI 再做）
5. ✅ 单测覆盖: 正常查询 + 边界（不存在的 trainingId/draftId）+ 回退后审计关联（≥ 8 用例）

**回退语义**:
- restoreDraft 调用 ActiveTrainingService.restore()
- restore 本身也是状态转换（from=InProgress, to=InProgress, trigger=restore）
- restore 触发新的快照（trigger=restore, restoredFromId=原 draftId）

**R-010 最小化**:
- 不实现 snapshot 比对（UI 阶段）
- 不实现批量回退（一次一个）

---

### 1.2 阶段 2：C-2 状态机状态变化审计日志

#### 1.2.1 C-2.1: 存储层 — `active_training_audit_log` 表

**目标**: append-only 审计日志表。

**DoD**:
1. ✅ `028_active_training_audit_log.sql` migration 文件
2. ✅ `ActiveTrainingAuditStore`: create/listByTrainingId/getRecentTransitions
3. ✅ `ActiveTrainingAuditRow` 类型 + 行↔领域对象转换
4. ✅ 单测覆盖: CRUD 正常路径 + append-only 约束（≥ 6 用例）
5. ✅ 集成测试: schema 同步 + append-only 验证

**字段设计**:
```sql
CREATE TABLE active_training_audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  active_training_id INTEGER NOT NULL,
  trigger TEXT NOT NULL,           -- 'start' | 'advance' | 'evaluate' | 'complete' | 'abort' | 'restore'
  from_state TEXT,                 -- 转换前状态
  to_state TEXT NOT NULL,          -- 转换后状态
  actor TEXT NOT NULL DEFAULT 'main',  -- 'main' | 'renderer'
  context_json TEXT,               -- payload 摘要（≤ 2KB）
  occurred_at TEXT NOT NULL,
  FOREIGN KEY (active_training_id) REFERENCES active_training(id) ON DELETE CASCADE
);
CREATE INDEX idx_atal_at_id ON active_training_audit_log(active_training_id, occurred_at);
```

**R-010 最小化**:
- 不创建审计归档表（S26+ 再说）
- 不实现全文检索（按 occurred_at + active_training_id 索引足够）

---

#### 1.2.2 C-2.2: 审计写入 — service 内部 hook（同步）

**目标**: 每次状态转换同步写审计（不允许异步丢日志）。

**DoD**:
1. ✅ service 内部 hook（在 5 个状态转换方法 + restoreDraft 中调用 `recordAudit`）
2. ✅ 同步写入：try/catch 但不静默失败（throw + 业务层决策）
3. ✅ 上下文摘要：context_json 截断至 2KB 字符
4. ✅ 单测覆盖: 5 状态 + restore 各产生 1 条审计（≥ 10 用例）
5. ✅ 集成测试: 真实链路 start→advance→evaluate→complete 验证 4 条审计

**关键实现**:
```typescript
class ActiveTrainingService {
  private async recordAudit(
    activeTrainingId: number,
    trigger: string,
    fromState: string | null,
    toState: string,
    actor: 'main' | 'renderer',
    context: Record<string, unknown>,
  ): Promise<void> {
    const contextJson = JSON.stringify(context).slice(0, 2048);
    await this.auditStore.create({
      activeTrainingId,
      trigger,
      fromState,
      toState,
      actor,
      contextJson,
      occurredAt: new Date().toISOString(),
    });
  }

  async advanceStep(sessionId: string, stepIndex: number) {
    const before = await this.store.getBySession(sessionId);
    const updated = await this.store.updateStep(sessionId, stepIndex);
    // 审计：同步写入
    await this.recordAudit(updated.id, 'advance', before.status, updated.status, 'main', { stepIndex });
    return updated;
  }
}
```

**R-028 防御性**:
- 审计写入失败抛错（业务层决定是否回滚状态转换，初期选择"审计失败让状态转换也失败"）
- 上下文截断 2KB（避免 payload 膨胀）

---

#### 1.2.3 C-2.3: 审计查询 API

**目标**: 提供 IPC 暴露的审计查询能力。

**DoD**:
1. ✅ `listAuditLog(trainingId, limit?)` API
2. ✅ `getRecentTransitions(sessionId, limit?)` API: 按 session 维度查最近转换
3. ✅ IPC 频道: `activeTraining:listAuditLog` + `activeTraining:getRecentTransitions`
4. ✅ 单测覆盖: 正常查询 + limit 参数 + 不存在场景（≥ 8 用例）

**R-010 最小化**:
- 不实现全文搜索
- 不实现时间范围查询（先按 limit 倒序）

---

## 2. 关键决策

### 2.1 决策 1: 快照 + 审计触发机制 — service 内部 hook（ADR-007）

**背景**: 两种方案：
- 方案 A: service 内部 hook（状态转换方法中直接调用 snapshotDraft + recordAudit）
- 方案 B: event-bus 订阅（service 发出状态转换事件，外部订阅者处理）

**决策**: 方案 A（service 内部 hook）。

**理由**:
- 事务一致性：A 让状态转换 + 快照/审计写入要么都成功要么都失败
- 简化依赖：B 需要 event-bus 模块 + 订阅注册 + 重试机制
- 性能：A 同步写入开销可接受（草稿 + 审计各 1 条 SQL）

**实施**: 在 ActiveTrainingService 的 5 个状态转换方法（start/advanceStep/evaluate/complete/abort）+ restoreDraft 中直接调用。

**R-010 最小化**:
- 不实现异步快照（同步 + 事务一致优先）
- 不实现批量快照（一次一个）

---

### 2.2 决策 2: 审计写入失败处理 — 抛出错误

**背景**: 审计日志是关键证据，丢失影响合规性。

**决策**: 审计写入失败抛错，业务层决定是否回滚状态转换。初期选择"审计失败让状态转换也失败"。

**理由**:
- 审计是合规需求，丢失不可接受
- 同步写入失败概率极低（SQLite 单机本地）
- 如果审计失败率高，说明系统有问题，应该响铃报警

**实施**: `recordAudit` 不 try/catch，错误自然抛出。

**R-010 最小化**:
- 不实现审计重试队列（S26+ 再说）
- 不实现降级到本地文件（避免复杂度）

---

### 2.3 决策 3: 字符上限策略 — 警告不阻塞

**背景**: userDraft 是用户输入，可能超出 50K（产品约束）。

**决策**:
- 草稿快照: 字符 >50K 警告日志但**不阻塞**（用户内容优先）
- 审计 context_json: 强制截断至 2KB（避免 payload 膨胀）

**理由**:
- 草稿是用户创作内容，不应因为超限丢失
- 审计上下文是辅助信息，截断可接受

**实施**:
- `snapshotDraft` 中检查长度，>50K console.warn
- `recordAudit` 中 `.slice(0, 2048)` 强制截断

---

### 2.4 决策 4: C-1 + C-2 串行交付

**背景**: 两个任务都涉及 service 内部 hook 改造，叠加开发风险大。

**决策**: 先 C-1 后 C-2 串行交付。

**理由**:
- C-1 完成后，service 已具备 hook 能力
- C-2 在 C-1 基础上加一层审计 hook，复用 hook 位置
- 串行可降低 merge 冲突概率

**实施**: 阶段 1（C-1）→ 阶段 2（C-2），每阶段独立 PR。

---

## 3. 门禁

### 3.1 每阶段门禁
- typecheck: 0 errors
- vitest: 当前数 + 该阶段新增 ≥ DoD 数
- lint: 0 errors
- 集成测试: 至少 1 个端到端用例

### 3.2 Sprint 25 全局门禁
- typecheck: 0 errors
- vitest: 当前 881 + Sprint 25 新增 ≥ 60 用例（C-1: 6+10+8=24, C-2: 6+10+8=24, 集成 12）
- lint: 0 errors
- E2E: 至少 2 个端到端用例（C-1 完整链路 + C-2 完整链路）
- 决策日志 D-074（D-073 之后）更新

### 3.3 验收清单
- [ ] 027 / 028 migration 在 dev 库 + 测试内存 DB 都能应用
- [ ] C-1: start → 推进 3 步 → 回退 → 验证草稿内容一致
- [ ] C-2: start → advance → evaluate → complete 产生 4 条审计
- [ ] service 内部 hook 在所有状态转换方法生效
- [ ] 字符上限保护（>50K 警告 + >2KB 截断）
- [ ] 4 道门禁全绿
- [ ] 决策日志 D-074 实施结果 + 复盘 + S26 候选

---

## 4. 实施计划

| 阶段 | 任务 | 预计改动 | DoD 单元数 |
|:----:|:-----|:--------|:--------:|
| 1.1.1 | C-1 存储层 active_training_drafts | 2 新文件 + 3 测试修复 | 6 |
| 1.1.2 | C-1 快照触发 service hook | 1 文件改造 + 1 集成测试 | 10 |
| 1.1.3 | C-1 查询 + 回退 API | 2 新文件 + 1 IPC 注册 | 8 |
| 2.2.1 | C-2 存储层 audit_log | 2 新文件 + 3 测试修复 | 6 |
| 2.2.2 | C-2 审计写入 service hook | 1 文件改造 + 1 集成测试 | 10 |
| 2.2.3 | C-2 审计查询 API | 1 新文件 + 1 IPC 注册 | 8 |

预估 commits: 6~8 个

---

## 5. 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| 快照写入阻塞状态转换 | 用户感知延迟 | 草稿快照 try/catch 失败不阻塞；审计失败抛错（罕见） |
| 审计表膨胀 | 磁盘占用 | 不在 Sprint 25 处理（S26+ 归档/压缩） |
| 回退导致状态混乱 | 用户期望不符 | restore 本身是状态转换（from=InProgress, to=InProgress, trigger=restore），留痕 |
| 内存 DB schema 漂移 | 测试 fail | 集成测试 fixture 同步添加新表 |
| 字符超限攻击 | 存储膨胀 | 草稿警告 + 审计强制截断（双层防御） |

---

## 6. 后续候选（S26+）

### S26 候选
1. C-3 refactor: ActiveTraining 迁移到独立 service
2. C-4 D-073: 治理 264 warnings（D-DEBT-34）
3. 草稿 diff 可视化（UI 阶段）
4. 审计日志导出/报表（UI 阶段）

### S26+ 候选
1. C-5 跨设备同步（云端 + 冲突合并）
2. C-6 训练协作（CRDT / OT）
3. 审计日志归档/压缩
4. 多用户身份追踪（user_id 维度）

---

## 7. 关联

- Issue #41（Sprint 25 范围锁定）
- Issue #42（Sprint 25 C-1 训练草稿版本历史）
- Issue #43（Sprint 25 C-2 状态机审计日志）
- Sprint 24 plan: dev-docs/tasks/sprint-24-plan.md
- D-070 Sprint 24 Reflect
- D-073 推 S26 治理（264 warnings，独立任务）
- ADR-008（已写）: service 内部 hook 决策 → dev-docs/designs/adr/008-active-training-internal-hook.md
