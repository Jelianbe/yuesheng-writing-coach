# T-024: 训练效果评分

> **优先级**: P0 | **状态**: done | **预估**: 2d
> **依赖**: T-022（技法库JSON化，评分需要技法库作为参考） | **后续**: T-025（前端证据展示）

## 目标

用户完成训练后获得 AI 评分和反馈，形成「诊断 → 训练 → 评分 → 成长」的完整闭环。当前训练完成后用户看不到自己的改进效果，训练效果评分是验证进步的关键环节。

## 设计依据

- **技术规格**: [training-effectiveness-scoring_V2.0.md](../specs/training-effectiveness-scoring_V2.0.md)
- **关联发现**: system-scan-report_V1.0.md §5.3（训练效果评分未实现）、§10（"执行训练→验证进步"环节为 ⚠️）
- **来源任务**: T-021（训练工坊已提供训练交互，但缺乏评分）
- **已有资源**:
  - `resources/prompts/training-evaluator-prompt-v1.md` — Evaluator Prompt 已存在但未接入
  - `src/main/services/training-record.service.ts` — 训练记录 CRUD，需扩展 score 字段
  - `src/renderer/components/training/TrainingWorkshop.tsx` — 训练工坊主面板

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 接入 training-evaluator-prompt-v1.md：训练提交后调用 LLM 评估 | `src/main/ipc/training.handler.ts` |
| 后端 | 新增 evaluateTraining() IPC 通道，调用 Evaluator Agent | `src/main/services/training-evaluator.service.ts`（新增） |
| 后端 | training_record 表扩展 score 字段 | 新增数据库迁移脚本 + 更新 training-record.service.ts |
| 前端 | TrainingWorkshop 训练完成后展示 EvaluationCard | `src/renderer/components/training/TrainingWorkshop.tsx` |
| 前端 | 评分结果显示：分数 + 文字反馈 + 改进点 + 下一步建议 | 同上 |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/services/training-evaluator.service.ts` | **新增** | 调用 training-evaluator-prompt-v1.md 评估用户改写文本 |
| 2 | `src/main/ipc/training.handler.ts` | 修改 | 新增 evaluateTraining IPC：接收 { trainingId, originalText, rewrittenText }，返回 { score, feedback, improved, nextStep } |
| 3 | `resources/prompts/training-evaluator-prompt-v1.md` | 修改 | 确保输出格式结构化为 JSON（score/feedback/improved/nextStep） |
| 4 | `src/main/services/training-record.service.ts` | 修改 | recordCompletion() 新增 score 字段，扩展 SQLite 表 |
| 5 | `src/main/db/012_add_training_score.sql` | **新增** | 迁移脚本：training_records 表新增 score INTEGER 字段 |
| 6 | `src/renderer/components/training/TrainingWorkshop.tsx` | 修改 | 训练步骤完成后调用 evaluateTraining，展示 EvaluationCard |
| 7 | `src/renderer/stores/training.store.ts` | 修改 | 新增 evaluationResult 状态字段 |

## Evaluator Agent 输入/输出定义

### 输入

```json
{
  "syndromeId": "P003",
  "challenge": "删掉'紧张'这个词，用一个动作展示",
  "originalText": "他很紧张，心里充满了不安",
  "rewrittenText": "他握紧茶杯，指节发白",
  "technique": "行动代替情绪"
}
```

### 输出

```json
{
  "score": 8,
  "feedback": "改写成功。用'握紧茶杯'的具体动作替代了'紧张'的标签，读者能直观感受到情绪。",
  "improved": true,
  "nextStep": "尝试在同一场景中继续用动作展示他的心理活动"
}
```

## 评分对诊断影响

评分 >= 7 的症候应在下次诊断中降低严重度（L3 → L2 或 L2 → L1），在 `teaching-state-machine.ts` 中实现：

```
trainingCompleted(syndromeId, score) →
  if score >= 7:
    lockSyndromes() 中将该症候的 severity 降一级
```

## DoD（完成标准）

- [x] S1. 完成一次训练后能在 TrainingWorkshop 中看到 1-10 分的评分和文字反馈
- [x] S2. 评分结果持久化到 SQLite training_records 表的 score 字段
- [x] S3. 评分 >= 7 的症候在下次诊断中严重度降低一级（验证：训练前 L3 → 训练后显示 L2）

## 回退方案

1. 数据库迁移回退：删除 012_add_training_score.sql
2. Evaluator 接入回退：移除 evaluateTraining IPC 通道
3. 前端 EvaluationCard 使用 feature flag 控制显示

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `resources/prompts/training-evaluator-prompt-v1.md` | 输出格式从 {passed, feedback} 改为 {score, feedback, improved, nextStep} |
| `src/main/services/training-evaluator.service.ts` | 新增 Evaluator Agent 服务，调用 LLM 评估改写稿 |
| `src/main/db/012_add_training_score.sql` | 新增迁移脚本，training_records 表加 score INTEGER 字段 |
| `src/main/services/training-record.service.ts` | TrainingRecord/Row 接口加 score 字段，assign/complete 方法更新 SQL |
| `src/main/ipc/training.handler.ts` | TRAINING_SUBMIT 改用 evaluateTraining 服务，新增 TRAINING_EVALUATE IPC |
| `src/shared/constants.ts` | 新增 TRAINING_EVALUATE 通道常量 |
| `src/renderer/shared/types.ts` | 新增 EvaluationResult 接口，TrainingRecord/ActiveTrainingSession 加 score/syndromeId |
| `src/renderer/stores/training.store.ts` | 新增 evaluationResult 状态、evaluateTraining action、submitStep 处理评分 |
| `src/renderer/components/training/ActiveTrainingView.tsx` | Step 2 展示评分圆环 + 文字反馈 + 下一步建议 |
| `src/renderer/components/training/TrainingWorkshop.tsx` | 传递 evaluationResult prop |
| `src/renderer/App.tsx` | 传递 evaluationResult prop |
| `src/main/services/teaching-state-machine.ts` | 新增 downgradeSyndromeSeverity 函数 |
| `src/main/ipc/teaching-state.handler.ts` | 导出 getTeachingStateStore 供 training handler 使用 |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit` → 0 errors）
- [x] 测试通过（`npx vitest run` → 38 files, 439 tests passed）

## 下个任务建议

T-025（前端证据原文引用展示），评分闭环完成后用户体验的下一个缺口是"看不到诊断依据"。
