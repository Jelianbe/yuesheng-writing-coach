# Sprint 33 C-5: 训练流 UI 入口激活

> 依据: D-085 真实就绪评估报告, GitHub Issue #53
> GStack 阶段: Plan → Build

## 背景

ChatPage 已通过 C-1 实现了 orchestrator `training_triggered` 事件响应链路（系统消息 + "开始训练"按钮 → `activeTrainingService.create()` → FlowPanel 覆盖层），但存在 4 个关键缺口：

1. **`evaluation={null}` 硬编码** — FlowPanel 的 `evaluation` prop 永远为 null，第 5 步反馈无法显示真实评估
2. **未挂载 `mountActiveTraining`** — 训练状态变更推送未订阅，评估结果无法同步到本地 store
3. **训练完成后无重置** — `onExit` 仅 `setShowTraining(false)`，`activeSession`/`trainingFlow` 残留，无完成消息
4. **无主动入口** — 用户只能等 AI 触发 `training_triggered` 才能开始训练，无法自主发起

## DoD

- [ ] 从 `useTrainingStore` 获取 `evaluationResult` 传给 FlowPanel
- [ ] 挂载 `trainingStore.mountActiveTraining()` 订阅评估结果推送
- [ ] 训练完成后：注入完成系统消息 + 重置 `activeSession`/`trainingFlow`/`showTraining`
- [ ] 底栏添加"开始训练"按钮（主动入口）
- [ ] 门禁: typecheck 0 error + test 全绿 + lint 0 error

## 涉及文件

- `src/renderer/pages/ChatPage.tsx` — 主要修改
- `docs/decision-log.md` — 追加 D-090

## 改动概要

| # | 改动 | 文件 | 说明 |
|---|------|------|------|
| 1 | 从 `useTrainingStore` 取 `evaluationResult` 替代 `null` | ChatPage.tsx | `evaluation` prop 从 store 获取 |
| 2 | `useEffect` 挂载 `mountActiveTraining` | ChatPage.tsx | 进入训练时订阅主进程推送 |
| 3 | `onExit` 增加状态重置 + 完成消息注入 | ChatPage.tsx | 清理 `activeSession`/`trainingFlow` + 注入系统消息 |
| 4 | 输入栏旁加"训练"按钮 | ChatPage.tsx | 调用 `activeTrainingService.create()` 同款逻辑 |
| 5 | 门禁 + 决策日志 | — | typecheck / test / lint / decision-log.md |

## 门禁

- typecheck: 0 error
- test: 全绿（FlowPanel 9 个测试, ChatPage 若有测试也通过）
- lint: 0 error
