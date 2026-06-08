# T-023: AI 回复长度与焦点控制

> **优先级**: P0 | **状态**: done | **预估**: 1d
> **依赖**: — | **后续**: —（与其他任务无硬依赖）

## 目标

解决 AI 回复偏长、一次输出太多信息、诊断即给建议的问题。通过 Prompt 约束 + 上下文注入策略优化 + 反思门控生效化，让每次 AI 回复聚焦 1-2 个核心问题，长度控制在可消化范围。

## 设计依据

- **设计依据文档**: [design-philosophy_V1.0.md](../design/design-philosophy_V1.0.md) §第五章「教学诊断体系」
- **关联发现**: system-scan-report_V1.0.md §7.1（AI 回复偏长、缺乏"只说一个问题"的约束）
- **已有基础**: T-018 反思门控已接入（reflection-gate.service.ts），但 `isReflectionGate` 尚未在教学状态机中实际使用

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| Prompt | System Prompt 增加长度约束和焦点约束 | `resources/prompts/yuesheng-prompt-v3.md` |
| 后端 | 诊断历史注入策略优化（从最近 5 次 → 最近 2 次 + 最严重 1 个未解决症候） | `src/main/services/prompt-builder.ts` |
| 后端 | 反思门控生效化：L2+ 症候时先触发反思再给建议 | `src/main/services/teaching-state-machine.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `resources/prompts/yuesheng-prompt-v3.md` | 修改 | 加入 "一次只聚焦一个问题"、"回复不超过 4 段"、"先诊断→给原因→给练习" 的结构要求 |
| 2 | `src/main/services/prompt-builder.ts` | 修改 | buildTeachingContext() 中修改诊断历史注入策略：MAX_DIAGNOSIS_HISTORY=5 → 最近 2 次 + 当前最严重的 1 个未解决症候 |
| 3 | `src/main/services/teaching-state-machine.ts` | 修改 | 在 S2_REFLECTION 子阶段中检查是否存在 L2+ 症候，有则门控生效 |

## Prompt 修改要点

### yuesheng-prompt-v3.md 新增约束

```
## 回复原则

1. 一次只聚焦一个问题：每次回复只针对当前最严重的 1-2 个症候，不超范围展开
2. 回复结构：先说诊断发现（1 段）→ 给一个具体原因（1 段）→ 给一个可执行的练习（1-2 段）
3. 长度限制：每次回复不超过 4 段
4. 如果存在 L2+ 症候，先问一个反思问题（"你有没有想过..."），等用户回答后再给建议
```

### prompt-builder.ts 注入策略变更

```
[现有] injectDiagnosisHistory(diagnosisResults[-5:]) → 注入最近 5 次
[改为] 
  1. 筛选出当前未解决的症候（severity ≥ L2）
  2. 按严重度排序，取最严重的 1 个
  3. 补充最近 2 次诊断的摘要
  4. 注入："当前最严重问题: {syndromeName}（{severity}）\n 最近诊断: {last2 summaries}"
```

## DoD（完成标准）

- [x] S1. AI 单次回复中症候建议数量不超过 2 个（Prompt §二「回复控制」约束）
- [x] S2. AI 回复不超过 4 段（Prompt §二.2.0.3 长度限制）
- [x] S3. `isReflectionGate` 在 teaching-state-machine.ts 中被正确触发：存在 L2+ 症候时进入反思流程，否则跳过

## 回退方案

1. Prompt 修改回退：恢复 yuesheng-prompt-v3.md 的旧版本
2. 注入策略回退：恢复 MAX_DIAGNOSIS_HISTORY=5
3. 反思门控：关闭 isReflectionGate 标记

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `resources/prompts/yuesheng-prompt-v3.md` | 新增§二「回复控制」（焦点约束+长度限制+反思优先+禁止堆叠），章节重编号 V3.3→V3.4 |
| `src/main/ipc/chat.handler.ts` | `formatDiagnosisHistory` 重写：最近2次摘要+最严重1个未解决症候；`getRecentBySession` 限制改为2 |
| `src/main/services/teaching-state-machine.ts` | 新增 `shouldEnterReflection()` + `enterReflectionIfTriggered()` |
| `src/main/services/diagnosis-merger.ts` | `merge()` 中合并后调用 `enterReflectionIfTriggered`，L2+症候时自动进入 S2_REFLECTION |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit`）
- [x] 测试通过（439 passed, 38 files）

## 下个任务建议

T-022（技法库JSON化）或 T-025（前端证据展示），T-023 无硬依赖可并行推进。
