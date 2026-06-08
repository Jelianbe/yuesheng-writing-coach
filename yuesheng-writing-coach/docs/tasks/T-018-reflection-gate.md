# T-018: Challenge-Unlock 反思门控

> **优先级**: P1 | **状态**: completed | **预估**: 2d  
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
| 常量 | TeachingSubphase 新增 PRACTICE_REFLECTION | `src/shared/constants.ts` |
| 前端 | 反思问题通过 AI 流式输出自然显示（无需特殊 UI） | — |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/services/reflection-gate.service.ts` | 新增 | 反思触发判定 + 问题 Prompt 生成 |
| 2 | `src/main/ipc/chat.handler.ts` | 修改 | 在诊断和建议之间插入反思门控 |
| 3 | `src/main/services/teaching-state-machine.ts` | 修改 | 扩展 S2_REFLECTION 子阶段 |
| 4 | `src/shared/constants.ts` | 修改 | 新增 PRACTICE_REFLECTION 子阶段常量 |
| 5 | `src/shared/mappings.ts` | 修改 | SUBPHASE_TO_ACTIONS 新增 S2_REFLECTION 映射 |
| 6 | `src/main/services/__tests__/reflection-gate.test.ts` | 新增 | 11 个测试覆盖触发/不触发/不同语气场景 |
| 7 | `src/main/services/__tests__/teaching-state-machine.test.ts` | 修改 | 更新进度计算测试（0.25→0.2） |

## DoD（完成标准）

- [x] S1. 症候发现时触发反思门控，输出反思性问题
- [x] S2. 无症候时不触发，直接给建议
- [x] S3. 用户回答反思问题后，AI 结合回答给出建议（通过 Prompt 注入实现）
- [x] S4. 反思问题根据教学态度调整语气（引导式/挑战式）
- [x] S5. TypeScript 编译无错误
- [x] S6. 11 个测试覆盖触发/不触发/不同语气场景

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. chat.handler 恢复为诊断即给建议
3. 状态机删除 S2_REFLECTION 子阶段

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `src/main/services/reflection-gate.service.ts` | **新建**：ReflectionGateService，包含 shouldTriggerReflection()、adjustReflectionTone()、buildReflectionPrompt() |
| `src/main/ipc/chat.handler.ts` | 导入 ReflectionGateService，新增 setReflectionGate()，prepareTeachingContext 返回 isReflectionGate 标记，辩驳检测使用 isReflectionGate 排除反思阶段消息 |
| `src/main/services/teaching-state-machine.ts` | SUBPHASE_NAMES 新增 S2_REFLECTION='反思引导'，PHASE_SUBPHASES PRACTICE_LOOP 新增 PRACTICE_REFLECTION |
| `src/shared/constants.ts` | TeachingSubphase 新增 PRACTICE_REFLECTION: 'S2_REFLECTION' |
| `src/shared/mappings.ts` | SUBPHASE_TO_ACTIONS 新增 S2_REFLECTION: [] |
| `src/main/services/__tests__/reflection-gate.test.ts` | **新建**：11 个测试覆盖 null/空/仅L1/L2/L3/混合/语气调整/Prompt构建 |
| `src/main/services/__tests__/teaching-state-machine.test.ts` | 更新进度测试 0.25→0.2（PRACTICE_LOOP 从 4→5 个子阶段） |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit` 0 errors）
- [x] 测试通过（32/33 test files passed，361/367 tests passed，6 skipped 为 pre-existing better-sqlite3 兼容性问题）

### 输出产物（实际完成时填写）

- ReflectionGateService 服务类，支持 8 个症候的反思问题模板
- S2_REFLECTION 子阶段已加入教学状态机流转序列
- 反思阶段辩驳排除逻辑已集成到 chat.handler 中（T-016 交互）


## 下个任务建议

T-015: 翻译层（诊断展示使用 T-018 后的数据流）
