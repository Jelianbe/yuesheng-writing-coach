# FlowPanel — V6.2 五步通用训练流

Sprint 25 BL-01 C-3 迁移自 `src/renderer/components_archived/training/flow/`

## 文件清单

| 文件 | 角色 |
|:-----|:-----|
| `FlowPanel.tsx` | 编排容器（重命名自 `FiveStepFlow.tsx`） |
| `FlowStepIndicator.tsx` | 5 步进度条 |
| `StepExplain.tsx` | 第 1 步：解说技法 |
| `StepExample.tsx` | 第 2 步：例证展示 |
| `StepConfirm.tsx` | 第 3 步：确认理解 |
| `StepPractice.tsx` | 第 4 步：主动尝试 |
| `StepFeedback.tsx` | 第 5 步：修改反馈 |
| `flow.module.css` | 共享 CSS Modules（覆盖全部 7 组件） |
| `__tests__/FlowPanel.test.tsx` | 9 用例单元测试 |

## 与 archived 关系

- archived 文件完整保留（历史快照，不删）
- archived 父组件 `ActiveTrainingView.tsx:26` 改 1 行 import 指向此目录
- V6.2 此目录**不**反向引用 archived（R-020 防止循环依赖）

## 改造点（C-3 vs archived）

1. **重命名**：`FiveStepFlow` → `FlowPanel`（对齐计划 DoD-1）
2. **CSS**：BEM 全局类名 → CSS Modules `styles.xxx` 访问（R-019）
3. **类型 import**：`src/shared/types/types-training.ts`（stale）→ `src/renderer/shared/types-training.ts`（真实）
4. **行为零变更**：9 测试断言原样保留
