# 月笙写作教练 v5.0.1(草案) — 契约对齐 + 端到端验证

> **版本**: v5.0.1-draft
> **创建**: 2026-07-03
> **作者**: Sprint 20 C-1 + 增量 3 端到端验证产物
> **状态**: DRAFT(端到端验证版,基于 v5.0.0-draft 修复契约/运行时错配)
> **回退**: `git checkout v5.0.0-draft -- resources/prompts/yuesheng-prompt-v5.0.0-draft.md`(回退到 v5.0.0-draft)
> **依据**: dev-docs/tasks/sprint-20-plan.md §增量 3 / 端到端验证结果

---

## v5.0.0 → v5.0.1 变更日志

| 变更 | 原因 | 验证 |
|------|------|------|
| `required_techniques`: P001-P010 → TQ-001~TQ-010 | v5.0.0-draft 用 P 前缀(症候 ID),但技法库实际是 TQ/TC/TN/TE/AIP 前缀(128 条),P 前缀在 technique-library.json 中**不存在** | 端到端验证暴露: `[techniques] 缺少 10 项: P001, P002, ..., P010` |
| `required_techniques` 追加 TQ-999 | 故意注入不存在的技法 ID,验证契约拦截行为 | 端到端验证预期: `[techniques] 缺少 1 项: TQ-999` |
| `required_tools`: chapter:read/diagnosis:extract/training:start/session:saveMessage → chapter:get/chapter:list/training:recommend/session:list | v5.0.0-draft 用语义名,但契约校验对照 IPC_CHANNELS 值。语义名与 IPC 值不一致,启动会 404 | 端到端验证暴露: `[tools] 缺少 4 项: chapter:read, ...` |

**关键教训**:`required_tools` 应直接对照 `IPC_CHANNELS` 常量值,不要造语义别名。语义层(AI 工具调用名)与 IPC 层(频道名)应统一。

---

## Contract(契约声明 — 启动时硬校验)

> 启动拦截规则:本 prompt 加载时,Orchestrator 会校验以下依赖全部存在,任何缺失立即抛 `PromptContractError` 拒绝启动。

```yaml
contract:
  required_phases: [trust_building, requirement, diagnosis, training, reflection]
  required_skills: [core-identity, scenario-rules, teaching-strategy, validation-rules, feedback-cognition]
  required_techniques: [TQ-001, TQ-002, TQ-003, TQ-004, TQ-005, TQ-006, TQ-007, TQ-008, TQ-009, TQ-010, TQ-999]
  required_tools: [chapter:get, chapter:list, training:recommend, session:list]
  emits_events: [chat:token, chat:intent, chat:phase_transition, chat:done, chat:error, diagnosis:extracted, training:triggered]
```

**TQ-999 说明**:故意注入不存在的技法 ID,用于演示契约拦截行为。生产版本应删除。

**校验位置**: `src/main/domains/03-teaching/conversation/prompt-contract.ts` `validateContract()`
**失败语义**: 抛 `PromptContractError`,列出缺失项,服务拒绝启动
**变更本块时**: 必须同步更新 `mock-orchestrator.ts` 的 `MOCK_CONTRACT` 保持 typecheck 通过

---

## 1. 核心变更概览(继承自 v5.0.0-draft)

### 1.1 v4 → v5 → v5.0.0 → v5.0.1 演进路径

| 版本 | 状态 | 关键变更 |
|------|------|----------|
| v3.9.0 | DEPRECATED | 5 SKILL 拆分(IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO) |
| v5(合并版) | CURRENT | 5 SKILL 合并回单文件,仍按 SKILL 分章节 |
| v5.0.0(草案) | DRAFT | 新增 phase 化会话结构,SKILL 章节保留但 phase 优先 |
| **v5.0.1(本草案)** | **DRAFT** | **契约对齐运行时:techniques 用 TQ 前缀,tools 用 IPC_CHANNELS 值** |

### 1.2 v5.0.1 关键设计

**契约对齐**:V5.0.0-draft 的契约声明与真实运行时数据源不一致(技法库 TQ 前缀,IPC 频道 IPC_CHANNELS 值)。V5.0.1 把契约改成与运行时完全匹配,确保启动校验通过。

---

## 2. Phase 编排(继承自 v5.0.0-draft,见原文件)

> Phase 0-4 设计、五步教学动作、能力边界等核心内容,见 `yuesheng-prompt-v5.0.0-draft.md`。
> V5.0.1 不变更方法论内容,仅修复契约声明的运行时对齐。
