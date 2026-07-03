# Sprint 21 计划 — A 轨真实化 + E 轨载荷脱敏(Sprint 20 架构落地)

> 创建日期: 2026-07-03
> 锁定原则: A 轨承接(真实 Orchestrator + 事件接状态机) / E 轨安全优先(载荷脱敏) / 最小化债务清理
> 依据: D-059(A-4 mock 桥接待真实化) / D-061(载荷脱敏候选) / D-062(C-1 收尾闭环) / R-029 安全底线

---

## 目标(Sprint Goal)

把 Sprint 20 建立的"事件驱动 + Orchestrator 包装 + 契约层 + 版本过滤"四层架构从"mock 演示态"推进到"生产可用态":用真实 ChatOrchestratorService 替换 mock,让 intent/phase_transition/training_triggered 事件真正联动状态机;同时在主进程侧实现敏感数据载荷脱敏,封堵 R-029 安全底线缺口。

---

## D 轨: A 轨承接 — 真实 Orchestrator + 事件接状态机

### D-1: ChatOrchestratorService → ConversationOrchestrator 适配器

**当前状态**: Sprint 20 A-4 在 `chat-handle-turn.bridge.ts` 中持有 `MockConversationOrchestrator`,事件序列硬编码,无法触发真实业务流。

**改造**: 桥接器内部将 `MockConversationOrchestrator` 替换为 `ChatOrchestratorService` 的适配实现,事件流来自真实 sendMessage 全流程(诊断/教学上下文/流式响应)。

**关键决策**:
- **适配器位置**: `src/main/domains/03-teaching/conversation/real-orchestrator-adapter.ts`(NEW)
- **依赖注入**: `ChatOrchestratorService.onOrchestratorEvent()` 已存在(D-058),适配器订阅其事件 → 转为 `OrchestratorEvent` 联合类型
- **事件对齐**:
  - `streamHandler.handleStream` 产生 token → `OrchestratorEvent.type: 'token'`
  - `diagnosisOrchestrator.analyze` 提取症候 → `OrchestratorEvent.type: 'diagnosis_extracted'`
  - `TeachingStateMachine` 决定训练触发 → `OrchestratorEvent.type: 'training_triggered'`
  - sendMessage 完成 → `OrchestratorEvent.type: 'done'`
  - 失败路径 → `OrchestratorEvent.type: 'error'`
- **mock 退役**: D-1 完成后,`MockConversationOrchestrator` 保留为测试桩(不删除,标 `@legacy`),生产路径不再引用

**DoD**:
- [ ] `real-orchestrator-adapter.ts`(NEW)
- [ ] `chat-handle-turn.bridge.ts` 注入 `RealOrchestratorAdapter`(替 mock)
- [ ] ChatPage 走真实 sendMessage 路径,事件流符合端到端预期
- [ ] 现有 7 个 bridge 单测 + 5 个 subscriber 单测仍全绿
- [ ] 新增至少 5 个适配器单测(订阅路径/事件类型映射/错误转换)
- [ ] FiveStepFlow E2E 全绿(无回归)
- [ ] **契约端到端**:`prompt-contract-integration.test.ts` 跑通 + `validateContract()` 在启动拦截

### D-2: phase_transition/intent/training_triggered 事件接真实状态机

**当前状态**: Sprint 20 A-3 试点仅迁移 1 个分支(`intent:train` → `teachingStateService.getContext()` 纯读验证),其他事件在 ChatPage 仅 console 留痕。

**改造**: 扩大订阅点接入真实状态机:
- `intent:diagnose` → 触发诊断分析流水线(`diagnosisOrchestrator.analyze`)
- `intent:train` → 启动训练(TeachingStateMachine 决策)
- `phase_transition` → 同步本地 phase(Sprint 19 PC 端嫌疑修复的 phaseProgress)
- `diagnosis_extracted` → 症候入库(SyndromeEvidence 持久化)
- `training_triggered` → 训练会话创建(ActiveTrainingSession)

**关键决策**:
- **状态机迁移策略**: 不一次性大改(违反 R-010),按事件类型分批迁移
  - 批次 1(本 Sprint): `intent:diagnose` + `diagnosis_extracted`(诊断链路完整闭环)
  - 批次 2(本 Sprint): `phase_transition` + `intent:train`(phase 流转)
  - 批次 3(推到 S22): `training_triggered` 完整训练流(依赖 D-3 多 streamId)
- **状态机适配**: `TeachingStateMachine` 内部增加 `onOrchestratorEvent()` 入口(模仿 `ChatOrchestratorService` 模式),保留 `stream.parse()` 旧接口(S21 不删,标 `@deprecated`,S22 移除)
- **降级优先**: 状态机方法抛错 → 事件流仍 emit `error` 事件,ChatPage 走降级路径(参考 D-060 typedInvoke 降级模式)

**DoD**:
- [ ] `TeachingStateMachine.onOrchestratorEvent(handler)` 订阅入口
- [ ] 5 个事件类型中的 4 个(`intent:diagnose`/`diagnosis_extracted`/`phase_transition`/`intent:train`)接真实状态机
- [ ] `training_triggered` 推迟 S22(标注 + 决策日志说明)
- [ ] ChatPage 不再有 `console.log` 残留(事件处理全部走 hook)
- [ ] 至少 8 个新增状态机事件单测
- [ ] FiveStepFlow E2E + 4 个新事件路径 E2E 全绿

---

## E 轨: 载荷脱敏字段白名单(主进程侧)

### E-1: 字段白名单机制

**当前状态**: Sprint 20 B-2/B-3 完成 24 处 typedInvoke 降级,但**载荷本身**(用户认知画像、诊断细节、AI 评分)在 IPC 传输中仍是明文,经 Electron ipcRenderer 一路暴露给 renderer 进程。

**背景依据**: D-061 后续已识别 4 个 service 含敏感数据:
- `student-context.service`(认知画像)
- `diagnosis.service`(诊断细节)
- `training.service`(AI 评分/练习内容)
- `teaching-state.service`(教学状态、症候锁定列表)

**改造**: 主进程侧(`src/main/core/payload-sanitizer.service.ts`)实现白名单脱敏:
- **白名单配置**: `resources/config/payload-sanitize-whitelist.json`(R-014 配置外置)
  - 字段级规则:`{ field: 'studentContext.cognitiveProfile', action: 'redact' | 'truncate' | 'hash' }`
  - 默认值:`redact` = 替换为 `'[REDACTED]'`,`truncate` = 截断到 N 字符,`hash` = SHA256
- **执行点**: 所有 IPC handler 在 `event.returnValue` 之前调用 `sanitizePayload(response, contractName)`
- **契约对应**: 每个 API contract 在 `src/shared/api-contracts/*.contract.ts` 标注 `sensitiveFields: string[]`

**关键决策**:
- **白名单 vs 黑名单**: 选白名单(显式安全,默认拒绝所有未声明字段)
- **执行时机**: 序列化前(主进程内,不在 IPC 边界)
- **可观测性**: 脱敏命中计数埋点(`console.debug('[sanitizer] redacted N fields in {contract}')`,生产环境可关)
- **测试覆盖**: 5 种脱敏动作 × 4 个 service = 20 个组合测试

**DoD**:
- [ ] `payload-sanitizer.service.ts`(NEW, ~120 行)
- [ ] `payload-sanitize-whitelist.json`(NEW, R-014 配置外置)
- [ ] 4 个 service 全部接入(`student-context`/`diagnosis`/`training`/`teaching-state`)
- [ ] 4 个 contract 标注 `sensitiveFields`(类型安全)
- [ ] 至少 20 个脱敏单测(动作 × service 矩阵)
- [ ] 降级测试:白名单配置缺失 → 默认 redact 所有非 skill/contract 元数据字段(失败安全)
- [ ] B-2/B-3 降级基线不被破坏(载荷脱敏是新一层,不替代错误降级)

### E-2: 契约标注 + 类型系统加固

**改造**: `src/shared/api-contracts/base.ts` 增加 `sensitiveFields?: ReadonlyArray<string>` 字段,所有含敏感数据的 contract 必须显式声明。

**DoD**:
- [ ] `ApiResponse<T>` 类型扩展 `sensitiveFields`
- [ ] 4 个 contract 标注完成
- [ ] typecheck 强制 sensitiveFields 存在(若 contract 实际含敏感字段但未标,启动拦截)

---

## Sprint 21 DoD (R-004 至少 3 条)

- [ ] **D 轨**: 真实 Orchestrator 适配器 + 4 个事件接状态机
- [ ] **E 轨**: 载荷脱敏白名单 + 4 个 service 接入 + 契约类型加固
- [ ] **门禁(R-027)**: typecheck 0 errors / vitest 全绿(新增 Orchestrator + 状态机 + 脱敏单测 ≥33 个) / lint 0 errors / E2E 全绿(新增事件路径测试 ≥4 个)
- [ ] **变更溯源(R-018)**: D-063 决策记录 + 4 道门禁全过
- [ ] **mock 桥接退役**:`MockConversationOrchestrator` 生产路径零引用(保留为测试桩)

---

## 范围边界 (R-010 最小化)

**不在本 Sprint 范围**:
- 多 streamId 并发管理(D-3) — 推到 S22,单用户场景不阻塞
- typedInvoke v2 强类型 API 客户端(D-DEBT-34) — 推到 S22,价值密度低于真实化
- 旧 IPC 频道完整移除(chat:sendMessage 等) — 推到 S22+ 清理轮
- `training_triggered` 完整训练流接入 — 推到 S22(本 Sprint 仍 console 留痕,标注迁移计划)
- 提示词 v5.0.x 内容迭代(C-3 灰度) — 独立轨道,推到 S22+

**Sprint 22 候选清单**:
- D-3 多 streamId 并发管理
- typedInvoke v2(D-DEBT-34 收尾)
- 旧 IPC 频道清理
- training_triggered 完整接入
- v5.0.x 灰度 + A/B 实验(C-2 + C-3)

---

## 工作量评估

| 轨道 | 预估工时 | 风险 |
|:-----|:---------|:-----|
| D-1 真实 Orchestrator 适配器 | 2 天 | 中(事件类型映射可能遗漏) |
| D-2 4 个事件接状态机 | 2 天 | 中(状态机迁移引入回归) |
| E-1 字段白名单 + 4 service 接入 | 1.5 天 | 中(配置外置 + 类型扩展联动) |
| E-2 契约类型加固 | 0.5 天 | 低 |
| **合计** | **~6 天(2 周)** | |

**Sprint 周期建议**: 2 周(留 4 天 buffer for 状态机迁移回归测试)

---

## 依赖与风险

| 风险 | 概率 | 影响 | 缓解 |
|:-----|:-----|:-----|:-----|
| D-1 真实 Orchestrator 与 mock 行为差异 | 中 | 高 | 保留 mock 作对照测试,真实路径先用旧用户消息验证回归 |
| D-2 状态机迁移触发 FiveStepFlow E2E 大面积红 | 中 | 高 | 分批迁移(诊断 → phase → train),每批跑 E2E 确认无回归 |
| E-1 白名单配置错误导致合法字段被 redact | 低 | 中 | 默认白名单(只列敏感字段),非声明字段不处理(零侵入) |
| E-2 契约类型加固破坏 typecheck | 中 | 中 | 先加 `?:` 可选字段,4 个 contract 标完后改必填,分两阶段 |
| 真实 Orchestrator 暴露性能问题(真实流式 vs 模拟) | 低 | 中 | 复用 D-058 emit 时机策略(sendMessage 末尾),不在流中频繁 emit |

---

## 依据 / 追溯 (R-018)

- **D-052**: Phase B event-bus 候选 → Sprint 20 落地
- **D-053**: Issue 19-3 契约断链教训 → 推动 S20 解耦
- **D-059**: A-4 ChatPage 订阅模式(指明 Sprint 21 真实化路径)
- **D-061**: typedInvoke 收尾(指明载荷脱敏候选)
- **D-062**: v5.0.1 OFFICIAL 收尾(完成 C-1,Sprint 21 进入新轨道)
- **R-010**: 最小化范围,1/5/6 候选推到 S22
- **R-014**: 配置外置(`payload-sanitize-whitelist.json`)
- **R-018**: 变更溯源,本计划是 S21 的设计哲学
- **R-027**: AI 代码质量门禁,所有改动走 4 道门禁
- **R-028**: 防御性编码(脱敏降级、状态机异常隔离)
- **R-029**: 安全与隐私(载荷脱敏是 E 轨核心)

---

## 实施计划

如计划批准,按 GStack 流程推进:

1. **Think**: D-063 决策日志已写(本计划批准后追加)
2. **Plan**: 本文档
3. **Build**: 按 D-1 → E-1 → E-2 → D-2 顺序(真实化 + 安全优先 + 类型加固 + 状态机迁移)
4. **Review**: 每轨道完成后跑 4 道门禁
5. **Test**: E-1 单测 + D-1/D-2 状态机 E2E
6. **Ship**: 8 个 commit(每任务 1 commit + 1 收尾 commit)
7. **Reflect**: D-064~D-067 复盘决策 + 债务台账更新

**实施顺序理由**:D-1 先做(基础架构真实化)→ E-1/E-2 并行(脱敏不依赖 D) → D-2(基于 D-1 真实路径做状态机迁移)
