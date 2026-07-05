# Sprint 23 计划 — G 轨: 教学链路重量化 (Sprint 22 占位承接)

> 创建日期: 2026-07-03
> 锁定原则: 承接 Sprint 22 F-2 主动债 + LLM intent 升级,补完教学链路核心完整性 (R-007 双向绑定)
> 依据: D-068(S22 收尾 + Sprint 23 候选清单) / user_profile "核心教学链路优先" / 调研发现(IntentRouter 已有 LLM 兜底 / ActiveTrainingSession 仅 renderer 侧)

---

## 目标(Sprint Goal)

把 Sprint 22 F-2 的 `console.info` 占位标注收敛为**真实业务方法**(`setActiveTraining`),并把训练意图识别从"70% 覆盖率正则"升级为"IntentRouter 100% LLM 兜底"。核心教学链路(诊断 → 训练触发 → ActiveTraining 标记)在主进程侧完成关键节点的状态写入。

---

## G 轨: 教学链路重量化

### 关键发现(影响范围)

调研发现两个关键事实,影响 G 轨范围决策:

1. **IntentRouter 已支持 LLM 兜底**(`src/main/domains/03-teaching/chat/intent-router.ts`):
   - 已有 keyword 关键词规则(`train` 类: `['练习', '写一个', '试试', '练练', '来练', '我想练', '训练']`)
   - 已有 LLM 分类系统提示词(Few-shot 10 个示例,token 消耗 ~50)
   - 已有 5 秒超时 + 低置信度降级
   - 结论: G-2 实际工作量 = **把 F-2 正则委托给 IntentRouter**,不需要重新设计

2. **ActiveTrainingSession 仅在 renderer 侧**(27 个文件引用):
   - `src/renderer/shared/types-training.ts` 定义 ActiveTrainingSession 类型
   - `src/renderer/stores/training.store.ts` 实现 zustand 状态机
   - 主进程侧**完全无** ActiveTraining 状态表 / 类型 / service
   - 结论: G-1 完整迁移是 S24+ 重量路线,Sprint 23 走**路径 C**(占位改进)

---

### G-1: setActiveTraining 替换 markTrainingIntent 占位

**当前状态**: Sprint 22 F-2 `Subscriber.handleSetActiveTraining` 调 `markTrainingIntent` + `console.info('ActiveTraining 状态由 renderer 维护,S23+ 接入主进程')`。`markTrainingIntent` 实际是 D-2 时代为 intent:train 写的"通用训练意图标记"方法,与 ActiveTraining 语义不匹配。

**改造**:
1. **新增 `TeachingStateService.setActiveTraining(sessionId, syndromeId, techniqueId?)`**:
   - 业务语义: 标记 session 进入 ActiveTraining 状态,写入 `activeTrainingMeta` 字段(JSON 字符串)
   - 异常隔离: 任何错误仅 warn,不抛出
   - 数据格式: `{ syndromeId, techniqueId?, triggeredAt: ISO timestamp, source: 'training_triggered' }`
2. **TeachingStateStore 新增字段**:
   - `teaching_state` 表新增 `active_training_meta` 列(TEXT, 缺省 NULL)
   - 加 SQLite migration 文件(021_teaching_state_active_training.sql)
   - `TeachingState` 类型扩展 `activeTrainingMeta?: ActiveTrainingMeta | null`
3. **Subscriber.handleSetActiveTraining 改造**:
   - 移除 `console.info` 占位标注
   - 调 `setActiveTraining` 替代 `markTrainingIntent`
4. **同步更新集成测试**: `teaching-link-integration.test.ts` 验证 `activeTrainingMeta` 字段写入

**关键决策**:
- **路径 C(占位改进)而非完整迁移**: R-010 最小化 + 完整迁移是 S24 重量路线(需新增表/类型/store/IPC 同步)。Sprint 23 只做"业务命名 + 主动债收敛"
- **不加独立 active_training 表**: 用 `teaching_state.active_training_meta` JSON 字段,避免破坏单表模式(R-014 配置外置精神)
- **Renderer 状态机保持不变**: Sprint 23 不动 `training.store.ts`,只增加主进程侧业务元数据
- **markTrainingIntent 保留**: 它是 `intent:train` 事件的通用方法,语义不同于 setActiveTraining,不应删除

**DoD**:
- [ ] `TeachingStateService.setActiveTraining()` 方法(异常隔离)
- [ ] `TeachingStateStore` 支持 `active_training_meta` 字段读写
- [ ] `TeachingState` 类型扩展 `activeTrainingMeta`
- [ ] SQLite migration 文件(021_teaching_state_active_training.sql)
- [ ] `Subscriber.handleSetActiveTraining` 改调 setActiveTraining,移除 console.info
- [ ] 至少 3 个新增单测(setActiveTraining 写入/异常隔离/无 session 时降级)
- [ ] 集成测试 `teaching-link-integration.test.ts` 更新:验证 `activeTrainingMeta` 字段
- [ ] typecheck 0 / vitest 全绿 / lint 0

### G-2: IntentRouter 替换 TRAINING_INTENT_PATTERN 正则

**当前状态**: Sprint 22 F-2 `emitTrainingTriggeredIfNeeded` 用 `TRAINING_INTENT_PATTERN` 正则匹配训练意图。覆盖 70% 场景,但:
- 不匹配"我想练环境描写"(只匹配"练一下"/"练一练"/"试试练"等显式训练)
- 不支持上下文场景(用户可能描述完问题后说"帮帮我",正则不能识别训练意图)

**改造**:
1. **ChatOrchestratorService DI 注入 IntentRouter**:
   - `ChatOrchestratorDeps` 新增 `intentRouter?: IntentRouter` 字段
   - 工厂/DI 容器装配时注入
2. **emitTrainingTriggeredIfNeeded 改造**:
   - 优先 IntentRouter: `await intentRouter.route(userMessage, sessionId)`,仅当 `result.intent === 'train'` 时 emit
   - IntentRouter 不可用时降级到正则(向后兼容 + 防御)
   - 5 秒 LLM 超时 + 不阻塞主流程(IntentRouter 内部已有超时)
3. **TRAINING_INTENT_PATTERN 处理**:
   - 保留正则作为"快速路径"(IntentRouter keyword 阶段已覆盖)
   - 或: 完全删除正则,IntentRouter.keyword 阶段更快更准
4. **handleTurn 入参兼容**:
   - Sprint 22 F-2 的 `emitTrainingTriggeredIfNeeded(sessionId, message, analysis)` 签名不变

**关键决策**:
- **IntentRouter 不可用 → 降级正则**: R-028 防御性编码,IntentRouter 注入失败或抛错时仍能跑
- **不强制替换正则**: Sprint 23 阶段保留正则作为 fallback,后续 S24 可根据数据决定是否完全删除
- **DI 注入容错**: ChatOrchestratorDeps 新增字段为 optional,旧测试代码不破坏

**DoD**:
- [ ] `ChatOrchestratorDeps.intentRouter?` 字段(可选注入)
- [ ] `emitTrainingTriggeredIfNeeded` 改用 IntentRouter.route
- [ ] IntentRouter 不可用/抛错 → 降级到 TRAINING_INTENT_PATTERN
- [ ] 至少 4 个新增单测(IntentRouter 触发/正则 fallback/IntentRouter 抛错降级/无意图不触发)
- [ ] 集成测试 `teaching-link-integration.test.ts` 验证 IntentRouter 路径
- [ ] typecheck 0 / vitest 全绿 / lint 0

---

## Sprint 23 DoD (R-004 至少 3 条)

- [ ] **G-1**: setActiveTraining 替换 markTrainingIntent 占位 + migration + 主动债收敛
- [ ] **G-2**: IntentRouter 替换正则 + DI 注入 + 降级路径
- [ ] **门禁(R-027)**: typecheck 0 / vitest 全绿(新增 ≥7 单测) / lint 0 / 集成测试覆盖 G-1/G-2
- [ ] **变更溯源(R-018)**: D-069 决策记录 + 4 道门禁全过

---

## 范围边界 (R-010 最小化)

**不在本 Sprint 范围**:
- 完整 ActiveTrainingSession 状态机迁移(renderer → 主进程) — 推到 S24 重量路线
- ActiveTrainingSession 类型在主进程侧定义 — S24
- 新增独立 active_training 表 — S24(本次用 teaching_state.active_training_meta JSON 字段)
- LLM intent 提取的 token 成本优化 — S24
- IntentRouter 升级为多意图联合提取 — S24

**Sprint 24 候选清单**:
- 完整 ActiveTrainingSession 状态机迁移(renderer → 主进程)
- 新增独立 active_training 表(替代 teaching_state JSON 字段)
- IntentRouter 多意图联合提取
- ActiveTraining IPC 双向同步
- 多 streamId 并发管理(D-3)
- typedInvoke v2 强类型化(D-DEBT-34 收尾)

---

## 工作量评估

| 轨道 | 预估工时 | 风险 |
|:-----|:---------|:-----|
| G-1 setActiveTraining + migration | 1.5 天 | 中(SQLite migration 需谨慎) |
| G-2 IntentRouter 替换正则 | 1 天 | 低(IntentRouter 已有,主要是 DI 接入) |
| 决策日志 + 收尾 commit | 0.5 天 | - |
| **合计** | **~3 天(1 周)** | |

**Sprint 周期建议**: 1 周(留 2 天 buffer for 回归 + DI 注入改造)

---

## 依赖与风险

| 风险 | 概率 | 影响 | 缓解 |
|:-----|:-----|:-----|:-----|
| SQLite migration 失败导致旧数据丢失 | 低 | 高 | 用 `ALTER TABLE ... ADD COLUMN`(SQLite 安全),不破坏现有行 |
| IntentRouter LLM 调用阻塞 sendMessage | 中 | 中 | IntentRouter 内部已有 5 秒超时,失败降级到正则 |
| ChatOrchestratorDeps 新增字段破坏旧测试 | 中 | 中 | 字段标 optional,旧测试不传也不崩 |
| `markTrainingIntent` 误删影响其他路径 | 中 | 高 | 保留 markTrainingIntent(它服务于 intent:train,语义不同) |
| IntentRouter 注入后依赖图变复杂 | 中 | 中 | 不在 Sprint 23 引入完整 DI 重构,只做最小注入 |

---

## 依据 / 追溯 (R-018)

- **D-068**: Sprint 22 收尾,F-2 console.info 占位标注 "S23+ 接入主进程"
- **D-068 实施结果**: F-2 决策日志明确"console.info 显式标注占位实现,S23 接入主进程"
- **调研发现**: IntentRouter 已有 LLM 兜底,ActiveTrainingSession 仅 renderer 侧(27 文件)
- **R-007**: 双向绑定(教学状态机 ↔ AI 流),G 轨是完整闭环关键
- **R-010**: 最小化范围,完整状态机迁移推到 S24
- **R-014**: 配置外置(SQLite migration 谨慎,JSON 字段保持单表模式)
- **R-027**: AI 代码质量门禁,4 道门禁
- **R-028**: 防御性编码(IntentRouter 注入容错 + 降级)
- **R-029**: 安全与隐私(SQLite migration 加 transaction)
- **user_profile**: "所有模块必须直接贡献核心教学链路" + "G 轨是承接 F-2 主动债"

---

## 实施计划

如计划批准,按 GStack 流程推进:

1. **Think**: 本文档 + D-069 决策日志
2. **Plan**: 本文档
3. **Build**: 按 G-1 → G-2 顺序(主动债优先 → 升级增量)
4. **Review**: 每任务完成后跑 4 道门禁
5. **Test**: G-1/G-2 单测 + 集成测试更新
6. **Ship**: 3 个 commit(G-1 / G-2 / 收尾)
7. **Reflect**: D-069 复盘 + Sprint 24 候选清单更新

**实施顺序理由**:
- G-1 先做(主动债收敛,console.info 移除是关键)
- G-2 后做(依赖 G-1 验证主进程状态机完整,确保 IntentRouter 接入的 sendMessage 流程不破坏既有功能)
