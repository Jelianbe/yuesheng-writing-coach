# T-019: 从零构建引导流程

> **优先级**: P2 | **状态**: draft | **预估**: 3d  
> **依赖**: T-015 | **后续**: 无（核心链终点）

## 目标

新用户首次进入时，检测无历史会话，触发"从零构建"引导流程。引导流程与聊天界面不同，更接近向导/问卷式交互，收集用户的写作背景和需求。完成引导后，用户带着初步的故事框架进入教练对话。

## 设计依据

- **设计文档**: [onboarding-flow-design_V1.0.md](../design/onboarding-flow-design_V1.0.md) — 详细交互设计、数据流、组件接口
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现1 从零构建模式被遗忘
- **来源任务**: T-015（全部核心功能稳定后，做新用户引导）
- **V4.0 开放问题 #6**: 内容路由层设计了 `onboarding` 路由目标，但具体流程未设计，拆出为独立文档

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 检测新用户逻辑（无历史会话） | `src/main/services/session.service.ts` |
| 后端 | 创建初始化引导会话 | `src/main/ipc/chat.handler.ts` |
| 前端 | 新增 OnboardingFlow 引导组件 | `src/renderer/components/onboarding/OnboardingFlow.tsx` |
| 前端 | 在 App.tsx 中检测新用户并展示引导 | `src/renderer/App.tsx` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/renderer/components/onboarding/OnboardingFlow.tsx` | 新增 | 向导式引导组件 |
| 2 | `src/renderer/App.tsx` | 修改 | 检测新用户（无历史会话）时展示引导 |
| 3 | `src/main/services/session.service.ts` | 修改 | 新增 isNewUser() 方法 |
| 4 | `resources/prompts/onboarding-prompt.md` | 新增 | 引导流程用 Prompt |

## DoD（完成标准）

- [ ] S1. 新用户（无历史会话）进入时自动触发引导流程
- [ ] S2. 引导流程以向导/问卷形式交互（非标准聊天界面）
- [ ] S3. 引导完成后用户带着初步框架进入教练对话
- [ ] S4. TypeScript 编译无错误

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. App.tsx 移除新用户检测逻辑
3. OnboardingFlow 组件保留不删除

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|

### 验证结果（实际完成时填写）

- [ ] TypeScript 编译通过（`npm run typecheck`）
- [ ] 测试通过（`npm test`）

### 输出产物（实际完成时填写）


## 下个任务建议

（完成后填写）
