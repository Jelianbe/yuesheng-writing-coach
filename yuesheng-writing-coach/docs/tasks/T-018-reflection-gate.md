# T-018: Challenge-Unlock 反思门控

> **优先级**: P1 | **状态**: draft | **预估**: 2d  
> **依赖**: T-017 | **后续**: T-015

## 目标

在"诊断"和"给出建议"之间插入反思关卡。有症候发现时，AI 先输出反思性问题让用户思考，用户回答后再结合回答给出建议。解决"AI 总是诊断即给建议，用户没有反思机会"的问题。

## 设计依据

- **设计依据文档**: [challenge-unlock-reflection_V1.0.md](../design/challenge-unlock-reflection_V1.0.md)
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现9 AI 温和偏差
- **来源任务**: T-017（反思门控复用统一后的态度系统做语气决策）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 新增 ReflectionGateService | `src/main/services/reflection-gate.service.ts` |
| 后端 | 在 chat.handler 中插入反思门控 | `src/main/ipc/chat.handler.ts` |
| 后端 | 扩展教学状态机 S2_REFLECTION 子阶段 | `src/main/services/teaching-state-machine.ts` |
| 前端 | 支持反思消息类型渲染 | `src/renderer/components/chat/ChatMessage.tsx` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/services/reflection-gate.service.ts` | 新增 | 反思触发判定 + 问题 Prompt 生成 |
| 2 | `src/main/ipc/chat.handler.ts` | 修改 | 在诊断和建议之间插入反思门控 |
| 3 | `src/main/services/teaching-state-machine.ts` | 修改 | 扩展 S2_REFLECTION 子阶段 |
| 4 | `src/renderer/components/chat/ChatMessage.tsx` | 修改 | 支持反思消息渲染 |
| 5 | `resources/config/challenge-templates.json` | 使用 | 已有文件，接入反思门控 |

## DoD（完成标准）

- [ ] S1. 症候发现时触发反思门控，输出反思性问题
- [ ] S2. 无症候时不触发，直接给建议
- [ ] S3. 用户回答反思问题后，AI 结合回答给出建议
- [ ] S4. 反思问题根据教学态度调整语气（引导式/挑战式）
- [ ] S5. TypeScript 编译无错误
- [ ] S6. 5 个测试覆盖触发/不触发/不同语气场景

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. chat.handler 恢复为诊断即给建议
3. 状态机删除 S2_REFLECTION 子阶段

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
