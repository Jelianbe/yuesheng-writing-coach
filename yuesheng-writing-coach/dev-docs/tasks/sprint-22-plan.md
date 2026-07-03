# Sprint 22 计划 — F 轨: 教学链路完整化 (Sprint 21 事件驱动收尾)

> 创建日期: 2026-07-03
> 锁定原则: 完成 Sprint 21 D-2 推迟的 2 个 action + 真实事件源扩展,实现"诊断→训练→评估"事件驱动闭环
> 依据: D-067(S21 E-2 收尾) / Sprint 21 plan "S22 候选" 段 / 教学链路完整性 (R-007 双向绑定)

---

## 目标(Sprint Goal)

把 Sprint 21 D-2 预留的 2 个事件 action(phase_transition/training_triggered)从"config 留痕"推进到"事件源 + 状态机联动"真实工作态,完成教学链路(诊断→训练触发→训练执行→评估)的端到端事件驱动闭环。

---

## F 轨: 教学链路完整化

### F-1: phase_transition 事件接状态机 — 启用 confirmPhase

**当前状态**: Sprint 21 D-2 在 `state-machine-event-mapping.json` 给 phase_transition 留了 `enabled: false` 扩展点,TeachingStateSubscriber.handleConfirmPhase 也有实现,但 ChatOrchestratorService 不在合适时机 emit phase_transition 事件。

**改造**:
1. **事件源**: `ChatOrchestratorService.sendMessage` 在诊断分析完成后,基于 `diagnosisAnalysis.syndromes.length > 0` 判断是否需要推进 phase(从 P2_DIAGNOSIS → P3_TRAINING),emit `phase_transition` 事件(payload: `{ from: 'P2_DIAGNOSIS', to: 'P3_TRAINING', reason: 'symptoms_detected' }`)
2. **config 启用**: `state-machine-event-mapping.json` 改 `enabled: true`
3. **不破坏现有**: 仅在 diagnostic phase 存在时推进,避免误触发其他 phase

**关键决策**:
- **推进条件**: 仅在 P2_DIAGNOSIS 阶段 + syndromes.length > 0 + 旧 phase 与新 phase 不一致时才 emit
- **from/to 字段**: 使用现有 Phase enum 字符串(P0_INIT/P1_WORLD/P2_DIAGNOSIS/P3_TRAINING/P4_REFLECTION)
- **降级**: emit 失败仅 console.warn,不中断 sendMessage
- **不要修改 phase 转换逻辑**: phase 推进仍走 TeachingStateService.confirmPhase(),Subscriber 接到事件后调用该方法

**DoD**:
- [ ] ChatOrchestratorService 在诊断完成后按条件 emit phase_transition
- [ ] state-machine-event-mapping.json 改 phase_transition.enabled = true
- [ ] Subscriber.handleConfirmPhase 验证 currentPhase 推进生效
- [ ] 至少 3 个新增单测(emit 条件分支 + Subscriber dispatch + config 启用)
- [ ] FiveStepFlow E2E 无回归(无新症状时 phase 不推进)

### F-2: training_triggered 事件接状态机 — 启用 setActiveTraining

**当前状态**: Sprint 21 D-2 在 config 留了 `enabled: false` 扩展点,Subscriber.handleSetActiveTraining 当前**错误**实现: 调 markTrainingIntent 而非真正的 setActiveTraining(主进程侧无该方法)。

**改造**:
1. **事件源**: `ChatOrchestratorService.sendMessage` 在诊断完成 + syndromes > 0 + 用户最新消息含训练意图关键词(可选:正则匹配"训练"/"练习"/"试试"),emit `training_triggered` 事件(payload: `{ syndromeId, techniqueId? }`)
2. **config 启用**: `state-machine-event-mapping.json` 改 `enabled: true`
3. **Subscriber 行为**: handleSetActiveTraining 当前调 markTrainingIntent 是 D-2 占位实现,F-2 阶段**保持**该占位(不引入主进程侧 ActiveTraining 状态机,R-010 最小化),但加 console.info 标记"training_triggered received, ActiveTraining 状态由 renderer 维护"
4. **F-3 后续**: 实际 ActiveTrainingSession 创建由 renderer 收到 chat 流后驱动(已有路径)

**关键决策**:
- **训练意图识别**: Sprint 22 阶段用轻量正则匹配(中文关键词"训练"/"练习"/"试试"),不引入 LLM intent 提取(R-010 最小化)
- **不新增 TeachingStateService.setActiveTraining**: 主进程侧 ActiveTraining 状态机推到 Sprint 23+(重量路线,见 Sprint 21 plan 候选)
- **复用 markTrainingIntent**: 写入 lastUserConfirmation,renderer 读 teaching-state IPC 推 ActiveTraining 启动
- **降级**: emit 失败仅 console.warn

**DoD**:
- [ ] ChatOrchestratorService 按条件 emit training_triggered
- [ ] state-machine-event-mapping.json 改 training_triggered.enabled = true
- [ ] Subscriber.handleSetActiveTraining 行为验证(markTrainingIntent 写入 + console.info 留痕)
- [ ] 至少 3 个新增单测(emit 条件 + Subscriber dispatch + 意图识别正则)
- [ ] E2E 验证:用户输入"帮我训练这个"→ 触发 training_triggered → 状态机记录

### F-3: 教学链路 E2E 验证

**当前状态**: Sprint 21 E2E 验证了诊断/教学状态/载荷脱敏,但**教学链路完整事件流**(诊断 → 训练触发 → ActiveTraining 启动)无 E2E 覆盖。

**改造**: 新增 `tests/e2e/flows/teaching-link.spec.ts`,覆盖:
- 用户输入含症候描述 → 诊断分析 → phase_transition 事件 → 状态机 phase 推进
- 用户继续输入"帮我训练" → training_triggered 事件 → 状态机 markTrainingIntent 写入
- 读 teaching-state IPC 验证 lastUserConfirmation 包含 `train:${syndromeId}:${timestamp}` 格式
- ChatPage 走完整事件流(无 console.error 残留)

**DoD**:
- [ ] `tests/e2e/flows/teaching-link.spec.ts`(NEW, ≥4 用例)
- [ ] Playwright 跑通:输入 → 触发 → 验证 lastUserConfirmation
- [ ] FiveStepFlow E2E 无回归
- [ ] 截图证据(诊断页面 phase 推进 + ActiveTraining 启动)

---

## Sprint 22 DoD (R-004 至少 3 条)

- [ ] **F-1**: phase_transition 事件源扩展 + config 启用 + Subscriber dispatch
- [ ] **F-2**: training_triggered 事件源扩展 + 意图识别 + config 启用
- [ ] **F-3**: 教学链路 E2E 覆盖(诊断→训练触发→状态机写入)
- [ ] **门禁(R-027)**: typecheck 0 / vitest 全绿(新增 F-1/F-2 单测 ≥6) / lint 0 / E2E 全绿(新增 ≥4 教学链路用例)
- [ ] **变更溯源(R-018)**: D-068 决策记录 + 4 道门禁全过
- [ ] **事件源单一职责**: ChatOrchestratorService 不持有训练意图识别 LLM 调用(轻量正则,推到 S23+)

---

## 范围边界 (R-010 最小化)

**不在本 Sprint 范围**:
- 主进程侧 ActiveTraining 状态机(新增 TeachingStateService.setActiveTraining) — 推到 Sprint 23 重量路线
- LLM intent 提取(IntentRouter 升级) — 推到 S23+,F-2 用正则占位
- 多 streamId 并发管理(D-3) — 推到 S24
- typedInvoke v2 强类型化(D-DEBT-34 收尾) — 推到 S24
- 旧 IPC 频道清理 — 推到 S24+ 清理轮
- 提示词 v5.0.x 内容迭代 — 独立轨道

**Sprint 23 候选清单**:
- 主进程侧 ActiveTraining 状态机(承接 F-2 重量路线)
- LLM intent 提取(IntentRouter 升级)
- 训练草稿持久化(目前只存 renderer)
- training_triggered 完整流(主进程侧维护 ActiveTrainingSession,与 renderer 同步)

---

## 工作量评估

| 轨道 | 预估工时 | 风险 |
|:-----|:---------|:-----|
| F-1 phase_transition 接状态机 | 1 天 | 中(emit 时机选择可能误触发) |
| F-2 training_triggered 接状态机 | 1 天 | 中(意图识别正则覆盖率) |
| F-3 教学链路 E2E | 1 天 | 低(已有 E2E 基础设施) |
| 决策日志 + 收尾 commit | 0.5 天 | - |
| **合计** | **~3.5 天(1 周)** | |

**Sprint 周期建议**: 1 周(留 3 天 buffer for 回归 + 异常分支)

---

## 依赖与风险

| 风险 | 概率 | 影响 | 缓解 |
|:-----|:-----|:-----|:-----|
| F-1 phase_transition 误触发导致 E2E 红 | 中 | 高 | 仅在 syndromes.length > 0 + 当前 phase 是 P2_DIAGNOSIS 时 emit,其他场景不 emit |
| F-2 训练意图正则误匹配(用户聊"练习"非训练) | 中 | 中 | 正则保守匹配"训练"/"帮我训练"/"我想练",不匹配"练习题"等中性词 |
| Subscriber.handleSetActiveTraining 占位实现被理解为完整实现 | 中 | 中 | console.info 明确标注 "ActiveTraining 状态由 renderer 维护,S23+ 接入主进程" |
| ChatOrchestratorService sendMessage 变长(emit 时机增加) | 低 | 低 | 提取为 emitPhaseTransitionIfNeeded() / emitTrainingTriggeredIfNeeded() 私有方法,主流程不复杂化 |
| E2E 触发链路不稳定(AI 响应时间/症候提取准确率) | 中 | 中 | E2E 用 mock AI 响应或固定输入,避免依赖真实 LLM |

---

## 依据 / 追溯 (R-018)

- **D-067**: Sprint 21 E-2 收尾,ApiResponse.sensitiveFields 落地
- **D-066**: Sprint 21 E-1 载荷脱敏,PayloadSanitizer 落地
- **D-065**: Sprint 21 D-2 事件接状态机,2 个 action 推迟到 S22
- **D-064**: Sprint 21 D-1 真实 Orchestrator 适配器,事件流从 mock 切换到真实
- **Sprint 21 plan §S22 候选**: phase_transition/training_triggered 启用 + 事件源
- **R-007**: 双向绑定(教学状态机 ↔ AI 流),F 轨是完整闭环关键
- **R-010**: 最小化范围,主进程侧 ActiveTraining 状态机推到 S23
- **R-014**: 配置外置(state-machine-event-mapping.json 仅改 enabled 字段)
- **R-027**: AI 代码质量门禁,4 道门禁
- **R-028**: 防御性编码(emit 异常隔离 + 降级原行为)

---

## 实施计划

如计划批准,按 GStack 流程推进:

1. **Think**: D-068 决策日志已写(本计划批准后追加)
2. **Plan**: 本文档
3. **Build**: 按 F-1 → F-2 → F-3 顺序(状态机迁移先做,事件源扩展,最后 E2E)
4. **Review**: 每任务完成后跑 4 道门禁
5. **Test**: F-1/F-2 单测 + F-3 教学链路 E2E
6. **Ship**: 4 个 commit(F-1 + F-2 + F-3 + 收尾)
7. **Reflect**: D-068 复盘 + Sprint 23 候选清单更新

**实施顺序理由**:F-1 先做(事件源相对简单:诊断后按条件 emit phase_transition)→ F-2 复用 F-1 模式(意图识别 + emit training_triggered)→ F-3 端到端验证(必须等 F-1/F-2 完成后才有完整事件流)
