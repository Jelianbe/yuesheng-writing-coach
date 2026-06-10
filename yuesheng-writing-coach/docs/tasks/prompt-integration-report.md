# Prompt 工程整合报告

> 基于 D→A→B→E→C 序列的执行结果，2026-06-09

---

## 执行摘要

| 优先级 | 任务 | 状态 | 涉及文件 |
|:------:|:----|:----:|:---------|
| **P0** | D: 诊断 Agent 对齐 V3.7 锁定规则 | ✅ 完成 | diagnosis-agent-prompt-v1.md |
| **P1** | A: L1/L2/L3 四段式结构标注 | ✅ 完成 | yuesheng-prompt-v3.md |
| **P2** | B: 语义化版本 + 文件头 Changelog | ✅ 完成 | yuesheng-prompt-v3.md |
| **P3** | E: Output Contract 审计 | ✅ 无需修改 | — |
| **P4** | C: Skill 触发检查 | ⏸️ 推迟 | 依赖测试基础设施 |

---

## 详细变更

### P0-D: 诊断 Agent 锁定对齐

**文件**：`diagnosis-agent-prompt-v1.md`

| 变更 | 位置 | 说明 |
|:----|:----|:-----|
| 新增输入参数 | §输入 | `lockedSyndromes` 可选参数 |
| 新增锁定过滤步 | §第零步A | 跳过已锁定症候，仅检测新问题 |
| 新增输出字段 | §输出 JSON | `lockedSyndromes` 保留锁定列表 |

**效果**：V3.7 §三.7 的诊断锁定规则现在向下传递到诊断 Agent，不再断裂。

### P1-A: 结构共识标注

**文件**：`yuesheng-prompt-v3.md`

| 层级 | 标注 | 说明 |
|:----|:----|:-----|
| L1 | `[≡ R-026: Role & Capability]` | 身份层 → Role 边界 |
| L2 | `[≡ R-026: Task + Constraints + Strategy]` | 知识层 → 混合 |
| L3 | `[≡ R-026: Extra Layer — 无直接对应]` | 画像层 → 无对应 |

**方法**：选项 A（加标注不改结构），V4 升级时再考虑选项 B（内部分段标注）。

### P2-B: 版本合规

**文件**：`yuesheng-prompt-v3.md`

- 文件头新增 HTML comment 元数据块（Version/Date/Change/Trigger/Rollback）
- 标题 V3.6 → V3.7
- 语义化版本号：`v3.7.0`
- 回退命令：`git checkout prompt/v3.6.0 -- resources/prompts/yuesheng-prompt-v3.md`

### P3-E: Output Contract 审计

| Prompt | JSON | 判定 |
|:-------|:---:|:-----|
| diagnosis-agent-prompt-v1.md | ✅ | 已有 |
| training-evaluator-prompt-v1.md | ✅ | 已有 |
| behavior-derivation-prompt-v1.md | ✅ | 已有 |
| teaching-agent-prompt-v1.md | ❌ | 不需要（输出面向用户）|
| onboarding-analysis-prompt.md | ❌ | 不需要（输出存于 `result.data.summary`）|

### P4-C: Skill 触发

- `prompt-ab-tester`：未使用，依赖测试基础设施
- `yuesheng-dev-practices`：未使用
- → 推迟，等待盲测流程就绪

---

## Prompt 文件版本矩阵

| 文件 | 版本 | 最后修改 |
|:-----|:---:|:---------|
| yuesheng-prompt-v3.md | v3.7.0 | 2026-06-09 |
| diagnosis-agent-prompt-v1.md | V1.3 | 2026-06-09 |
| teaching-agent-prompt-v1.md | V1 | — |
| training-evaluator-prompt-v1.md | V1 | — |
| behavior-derivation-prompt-v1.md | V1 | — |
| onboarding-analysis-prompt.md | V1 | — |

---

## 待办

- [ ] 创建盲测测试集（依赖：反例样本执行完成）
- [ ] 接入 prompt-ab-tester Skill
- [ ] 接入 yuesheng-dev-practices Skill
- [ ] V4 架构升级时考虑 L2 内部分段标注（选项 B）
