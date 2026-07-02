# 后端审计报告 — 2026-06-24

> **目的**：对照 diagrams.md 架构图，逐项核查后端实际代码实现，识别阻碍三层架构转型的堵塞项。
> **范围**：仅后端（前端将重做，不在此次审计范围内）。
> **方法**：逐文件阅读 + 编译验证（typecheck） + 测试运行（test/lint）。

---

## 总体评估

**大部分后端功能已实现**且可正常工作。但存在 **5 个 P0 级堵塞项**和 **4 个 P1 级债务项**，需在转型前或转型中解决。

---

## P0 — 阻断转型的堵塞项

### 1. 诊断 Agent Prompt 与代码严重脱节

| 项目 | 状态 |
|:-----|:------|
| `diagnosis-agent-prompt-v1.md` | **V1.2（仅 P001-P006 检测规则）** |
| `DIAGNOSIS-UPGRADE-CHANGELOG.md` | 描述了 v2.0（P001-P012 + 经典原则交叉引用）但**从未被写入** |
| `src/shared/constants.ts` | 定义了 P001-P010 |
| `P011/P012` | 在代码库中**完全不存在** |

**影响**：LLM 无法诊断超出 V1.2 范围的症候。有 P007-P010 的代码路径但 LLM 从未被告知要检测它们。转型后`对话 → AI自动诊断`的基础能力是残缺的。

**位置**：
- `resources/prompts/diagnosis-agent-prompt-v1.md`
- `resources/prompts/DIAGNOSIS-UPGRADE-CHANGELOG.md`

---

### 2. Migration 024/025 未应用

| 项目 | 状态 |
|:-----|:------|
| `024_teaching_decision_log.sql` | 文件存在磁盘但**不在 `migrationFiles` 数组中**，永远不会被应用 |
| `025_evidence_offset.sql` | 同上 |
| `teaching_decision_log` 表 | 生产库**不存在** |
| `evidence.start_offset/end_offset` | 列**不存在** |

**影响**：教学决策日志表缺失，`diagnosis.handler.ts` 中 `processDiagnosisFromAI` 调用 `processAIResponse` 时**没传入 `teachingDecisionService`**（`chat-orchestrator.service.ts` 的正确调用传了 4 个依赖，但 handler 只传了 3 个）。诊断管道中的教学决策无法记录。

**位置**：
- `src/main/db/024_teaching_decision_log.sql`
- `src/main/db/025_evidence_offset.sql`
- `src/main/core/app-initializer.ts`（`migrationFiles` 数组）
- `src/main/ipc/diagnosis.handler.ts:162`（缺失 `teachingDecisionService`）

---

### 3. Retro:save IPC 是桩实现

```typescript
// retro.handler.ts:32-36
RETRO_SAVE: (_event, args) => {
  // 仅返回 {saved: true}，不执行任何持久化
  return { saved: true };
}
```

**影响**：复盘结果无法保存。三层架构中"成长"页需要历史训练数据，桩实现意味着复盘数据的写入通道是坏的。

**位置**：`src/main/ipc/retro.handler.ts:32-36`

---

### 4. 训练流主进程使用硬编码模板

| 问题 | 详情 |
|:-----|:------|
| `CATEGORY_CONFIGS` | `training-flow.service.ts` 中 5 个分类模板全部**硬编码**（L63-109） |
| `training-flow-mapping.json` | 存在且有完整模板，但**主进程生成时不使用它** |
| 模板语法不一致 | JSON 用 `{{double_brace}}`，硬编码用 `{single_brace}` — 两者无法混用 |

**影响**：修改训练流模板需要改代码，违反 R-014 配置外置规范。如果要调整训练流模板以适配三层架构（对话中嵌入训练体验），必须同时改代码和 JSON。

**位置**：
- `src/main/domains/04-validation/training/training-flow.service.ts:63-109`
- `resources/config/training-flow-mapping.json`
- ADR-007 债务记录 `D-DEBT-2026-06-23-28`

---

### 5. 状态机无法自动进入复盘阶段

```typescript
// getNextPhase 中 PRACTICE_LOOP 返回自身
case TeachingPhase.PRACTICE_LOOP:
  return TeachingPhase.PRACTICE_LOOP; // 自循环
```

注释明确写"除非用户主动要求复盘"。没有自动触发 `P4_REVIEW` 的逻辑。

**影响**：三层架构中"成长"页需要复盘数据作为输入。完全依赖用户主动要求复盘意味着大部分用户永远不会看到成长结果。

**位置**：
- `src/main/domains/03-teaching/state/teaching-state-machine.navigation.ts`

---

## P1 — 影响但不阻断

### 6. BehaviorDerivation 零测试 + IPC 格式不匹配

- **零测试覆盖**
- Prompt 路径硬编码，编译后不可靠
- IPC handler 返回裸 `DerivationResult`，但前端 Store 期望 `{ success, data, error }` 结构

**位置**：`src/main/domains/04-validation/training/behavior-derivation.service.ts`

---

### 7. 诊断合约与运行时类型不匹配

`diagnosis.contract.ts` 中的 `SyndromeResult`、`DiagnosisEntry` 字段名与 `types-diagnosis.ts` 的运行时使用版本不同：
- `syndromeId` vs `id`
- `summary` vs 不存在
- `createdAt` vs `timestamp`

**影响**：虽然不是运行时阻塞（IPC 直接传 JSON），但三层架构转型后如果需要重建前端 IPC 层，合约不匹配会引起混乱。

**位置**：
- `src/shared/api-contracts/diagnosis.contract.ts`
- `src/shared/types/types-diagnosis.ts`

---

### 8. 能力画像无独立存储表

`ability:getProfile` 的数据完全在内存中实时聚合（`AbilityProfileService` 聚合 `diagnosis_results` + `user_training_records`）。没有自己的数据库表。

**影响**：三层架构"成长"页需要快速展示能力雷达图，每次实时聚合的性能开销在移动端可能不可接受。

---

### 9. 前端 teaching state store 无 persist

`useTeachingStateStore` 使用 zustand 但不加 `persist` middleware，刷新后丢失。

**影响**：三层架构转型后前端重做时会自然解决，但需要注意在新前端中状态持久化的设计。

---

## 已正常工作（不在图中但实际存在的能力）

| 能力 | 状态 | 备注 |
|:-----|:------|:------|
| LLM 网关（限流/超时/重试/降级/缓存） | ✅ 完整 | Sprint 18 已确认 |
| 5 阶段教学状态机 | ✅ 完整 | 含 GUIDE 子阶段内部状态机 |
| TeachingStateService/Store | ✅ 完整 | 含持久化、IPC、降级推送 |
| TrainingEvaluator（评分+反馈） | ✅ 完整 | 有测试 |
| TrainingRecommendation | ✅ 完整 | 测试充分，含 A3 阅读推荐 |
| B-02 阅读决策（IPC→Router→Store→UI→回环） | ✅ 完整 | 缺 required=true 端到端测试 |
| FiveStepFlow / TrainingFlow 生成 | ✅ 完整 | 含耗时估算 |
| TrainingRecordService CRUD | ✅ 完整 | 含事务处理 |
| RetroSummary 后端 | ✅ 完整 | 除 save 是桩外 |
| AbilityAtlasLoader | ✅ 完整 | 三重 JSON 惰性加载 |
| AbilityProfileService | ✅ 完整 | 实时画像计算 |
| DevelopmentPathService | ✅ 完整 | 含阶段进度 |
| 证据链服务（EvidenceService） | ✅ 完整 | 含 CRUD + 链式查询 |
| 项目空间（projects/manuscripts/chapters） | ✅ 完整 | 含级联删除 |
| 教学笔记服务 | ✅ 完整 | CRUD + 树形结构 |
| 成长趋势（GrowthTrendService） | ✅ 完整 | 含双维度趋势 |

---

## 对三层架构的影响矩阵

| 三层架构组件 | 依赖的后端能力 | 阻塞项 | 无需等待 |
|:-------------|:--------------|:-------|:---------|
| 对话 → 诊断路由 | 诊断引擎 | **#1（Prompt 不完整）** | |
| 对话 → 教学路由 | 教学状态机 | | ✅ 完整 |
| 对话 → 训练路由 | 训练推荐/训练流 | **#4（模板硬编码）** | |
| 成长 → 能力雷达图 | 能力画像 | #8（无独立表，性能） | |
| 成长 → 最近症候 | 诊断历史 | | ✅ 完整 |
| 成长 → 训练记录 | 训练记录 | **#3（save 是桩）** | |
| 成长 → 成长轨迹 | 复盘/历史趋势 | **#5（不自动进入复盘）** | |
| 项目 → 诊断/训练关联 | 诊断/训练记录 | | ✅ 完整 |
| 通用 | DB Schema | **#2（迁移未应用）** | |

---

## 建议处理优先级

```
第一优先级（转型前必须修）：
  #1 诊断 Prompt → 至少补齐到 P001-P010（与代码对齐）
  #2 迁移 024/025 应用 + teachingDecisionService 补传
  #3 Retro:save 桩 → 真实持久化

第二优先级（转型中可并行）：
  #4 训练流模板外置（对齐 JSON 和代码模板）
  #5 自动进入复盘逻辑

第三优先级（转型后可优化）：
  #6 BehaviorDerivation 测试 + IPC 格式修复
  #7 诊断合约与运行时类型对齐
  #8 能力画像缓存/持久化方案
  #9 新前端解决 store 持久化
```

---

*本报告基于 2026-06-24 代码快照，对照 dev-docs/designs/diagrams.md 的系统架构图和数据流图进行逐项核查。*
