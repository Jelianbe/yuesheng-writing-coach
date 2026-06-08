# T-019: 从零构建引导流程

> **优先级**: P2 | **状态**: completed | **预估**: 3d  
> **依赖**: T-015 | **后续**: 无（核心链终点）

## 目标

新用户首次进入时，检测无历史会话，触发"从零构建"引导流程。引导流程与聊天界面不同，更接近向导/问卷式交互，收集用户的写作背景和需求。完成引导后，用户带着初步的故事框架进入教练对话。

## 设计依据

- **设计文档**: [onboarding-flow-design_V1.0.md](../design/onboarding-flow-design_V1.0.md) — 详细交互设计、数据流、组件接口
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现1 从零构建模式被遗忘
- **来源任务**: T-015（全部核心功能稳定后，做新用户引导）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 类型 | 新增 OnboardingBaseline 接口 | `src/renderer/shared/types.ts` |
| 后端 | 引导分析 IPC handler | `src/main/ipc/chat.handler.ts` |
| 前端 | 新增 OnboardingFlow 引导组件 | `src/renderer/components/onboarding/OnboardingFlow.tsx` |
| 前端 | 在 App.tsx 中检测新用户并展示引导 | `src/renderer/App.tsx` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/renderer/shared/types.ts` | 修改 | 新增 OnboardingBaseline 接口 |
| 2 | `src/renderer/components/onboarding/OnboardingFlow.tsx` | 新增 | 3步向导式引导组件（认识→基线→推荐） |
| 3 | `src/renderer/App.tsx` | 修改 | 新增新用户检测 + 引导展示逻辑 |
| 4 | `src/main/ipc/chat.handler.ts` | 修改 | 新增 onboarding:analyze IPC handler |

## DoD（完成标准）

- [x] S1. 新用户（无历史会话）进入时自动触发引导流程
- [x] S2. 引导流程以向导/问卷形式交互（非标准聊天界面）
- [x] S3. 引导完成后用户带着初步框架进入教练对话
- [x] S4. TypeScript 编译无错误

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. App.tsx 移除新用户检测逻辑
3. OnboardingFlow 组件保留不删除

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `src/renderer/shared/types.ts` | 新增 OnboardingBaseline 接口（writingType, sampleText, analysisSummary, improvementGoal, capturedAt） |
| `src/renderer/components/onboarding/OnboardingFlow.tsx` | **新建**：3步引导组件，Step1=写作类型选择，Step2=发送文字/AI分析，Step3=改进目标选择+推荐卡片 |
| `src/renderer/App.tsx` | 新增 isNewUser 检测（sessions.length===0）、showOnboarding 状态、引导完成/跳过回调、引导页面渲染 |
| `src/main/ipc/chat.handler.ts` | 新增 onboarding:analyze IPC handler（MVP轻量级分析回复） |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit` 0 errors）
- [x] 测试通过（34/34 test files passed，375/375 tests passed）

### 输出产物（实际完成时填写）

- OnboardingFlow 3步引导组件，符合设计文档的交互流程
- App.tsx 中无历史会话时自动展示引导
- onboarding:analyze IPC handler 提供轻量级分析回复


## 下个任务建议

无后续任务（核心链路终点）。可考虑 T-020 之后的优化任务或新需求。
