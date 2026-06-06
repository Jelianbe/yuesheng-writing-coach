# T-010: PromptBuilder 改造

> **优先级**: P1  
> **状态**: ready  
> **预估工时**: 2d  
> **依赖**: T-009（Strategy Service）✅ 已完成  
> **前端组件**: 无（纯后端）

---

## 一、任务目标

改造 `PromptBuilder` 使其接收策略服务层的输出，将教学策略决策（模式、语气、格式、问题优先级）系统性地融入 System Prompt 生成。

---

## 二、变更溯源

### 依据链
- **设计哲学**：`teaching-knowledge-bridge_V1.0.md` §五「PromptBuilder 改造」、§七 Phase D
- **技术规格**：`teaching-knowledge-bridge_V1.0.md` §6.1 数据流、§6.2 文件清单
- **前置任务**：T-009（Strategy Service）— 已产出 TeachingStrategyService 和 ProblemPrioritizer

### 问题陈述
当前 `PromptBuilder.buildSystemPrompt()` 只接收原始教学状态（TeachingState），策略决策逻辑散落在 `chat.handler.ts` 的 `buildStrategyInstruction` 函数中。需要将策略决策正式纳入 PromptBuilder 的职责范围，实现：

1. PromptBuilder 接收 TeachingStrategyDecision 和 PrioritizedProblem[] 作为入参
2. 将策略决策翻译为结构化的 Prompt 指令
3. 保持与现有教学进度注入逻辑的兼容

---

## 三、涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/main/services/prompt-builder.ts` | 修改 | 扩展 buildSystemPrompt 接口，接收策略决策 |
| `src/main/ipc/chat.handler.ts` | 修改 | 简化 buildStrategyInstruction，调用 PromptBuilder 统一构建 |
| `src/main/index.ts` | 修改 | 注入 TeachingStrategyService 和 ProblemPrioritizer 到 PromptBuilder |
| `src/main/services/__tests__/prompt-builder.test.ts` | 新增 | PromptBuilder 单元测试 |

---

## 四、DoD（完成标准）

### 标准 1：PromptBuilder 接口改造
- [ ] `buildSystemPrompt()` 方法接收 `TeachingStrategyDecision` 和 `PrioritizedProblem[]` 作为可选参数
- [ ] 策略决策正确翻译为 Prompt 指令（模式、语气、格式、优先级问题）
- [ ] 原有教学进度注入逻辑保持兼容

### 标准 2：集成验证
- [ ] `chat.handler.ts` 中调用 PromptBuilder 时传入策略决策数据
- [ ] 生成的 System Prompt 包含教学策略指令段落
- [ ] TypeScript 编译无错误（`tsc --noEmit`）

### 标准 3：测试覆盖
- [ ] PromptBuilder 新增至少 5 个单元测试
- [ ] 测试覆盖：无策略决策（降级）、有策略决策、有优先级问题、组合场景
- [ ] 所有测试通过（`npm test`）

---

## 五、实现方案

### 5.1 PromptBuilder 接口变更

```typescript
// 改造后
buildSystemPrompt(
  state: TeachingState,
  getActionName: (id: string) => string,
  getActionGoal: (id: string) => string,
  getSyndromeName: (id: string) => string,
  options?: {
    strategyDecision?: TeachingStrategyDecision;
    prioritizedProblems?: PrioritizedProblem[];
  },
): string
```

### 5.2 PromptBuilder 内部逻辑

```
buildSystemPrompt()
  ├── 1. 基础教学进度（原有逻辑）
  ├── 2. 教学策略指令（新增）
  │     ├── 模式指令（scaffolding/guiding/challenging）
  │     ├── 语气指令（encouraging/direct/logical/resonant）
  │     └── 格式指令（problem→cause→evidence→solution / example→feeling→demonstration）
  └── 3. 优先级问题（新增）
        └── 最高优先级问题标注（tierLabel + action）
```

### 5.3 chat.handler.ts 调用方式

```typescript
// 简化后，策略指令由 PromptBuilder 统一构建
const systemPrompt = promptLoader?.loadSystemPrompt(
  attitude,
  diagnosisAnalysis,
  diagnosisHistory,
  effectiveStudentContext,
  activeSessionId,
  {
    strategyDecision: teachingStrategyService?.decide(strategyInput),
    prioritizedProblems: problemPrioritizer?.prioritize(syndromesForPrioritization),
  },
)
```

---

## 六、回退方案

如果改造过程中发现接口变化影响过大：
1. 保持现有 `buildStrategyInstruction` 函数不变
2. PromptBuilder 新增独立方法 `buildStrategySection()` 返回策略指令段落
3. 在 `chat.handler.ts` 中拼接：`systemPrompt + '\n\n' + strategySection`

---

## 七、变更溯源

### 依据链
- **设计哲学**：`teaching-knowledge-bridge_V1.0.md` §五「PromptBuilder 改造」
- **技术规格**：`teaching-knowledge-bridge_V1.0.md` §6.1 数据流、§6.2 文件清单
- **前置任务**：T-009（Strategy Service）— 已产出 TeachingStrategyService 和 ProblemPrioritizer

### 变更摘要
- **变更类型**：重构 + 新增
- **涉及文件**：`prompt-builder.ts` / `chat.handler.ts` / `index.ts` / `prompt-builder.test.ts`
- **核心变更**：PromptBuilder 接收策略服务输出，统一构建 System Prompt
- **DoD 达成**：待验证

---

## 八、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-05 | 初始任务文档创建 |
