# T-020: 状态锁定机制

> **优先级**: P2 | **状态**: completed | **预估**: 1d  
> **依赖**: T-014 | **后续**: T-013

## 目标

补充 P3 阶段缺失（当前直接从 P2 跳到 P4），实现"诊断结果锁定→跨轮次保持→进步后解锁"机制。修复 V1.0 设计的"锁定"语义在代码中完全缺失的问题，确保教学状态单向流转、不可回退。

## 设计依据

- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现2 四层架构坍缩
- **来源任务**: T-014（需 DynamicContextService 稳定后再改状态机）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | teaching-state-machine 补充 P3 阶段定义和流转 | `src/main/services/teaching-state-machine.ts` |
| 后端 | 实现状态锁定语义（锁定→解锁逻辑） | `src/main/services/teaching-state-machine.ts` |
| 数据 | constants.ts 补全 P3 枚举 | `src/shared/constants.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/renderer/shared/types.ts` | 修改 | TeachingState 新增 lockedSyndromes 字段 |
| 2 | `src/main/services/teaching-state.types.ts` | 修改 | TeachingStateRow 新增 locked_syndromes 字段 |
| 3 | `src/main/services/teaching-state.store.ts` | 修改 | 数据库转换逻辑支持 lockedSyndromes 序列化/反序列化 |
| 4 | `src/main/db/011_add_locked_syndromes.sql` | 新增 | 数据库迁移脚本添加 locked_syndromes 列 |
| 5 | `src/main/index.ts` | 修改 | 注册 011 迁移 |
| 6 | `src/main/services/teaching-state-machine.ts` | 修改 | 新增 lockSyndromes/updateSyndromeStatus/unlockResolvedSyndromes/areAllSyndromesResolved 函数 |
| 7 | `src/main/services/diagnosis-merger-utils.ts` | 修改 | 诊断合并时自动锁定新症候 |
| 8 | `src/main/services/__tests__/state-locking.test.ts` | 新增 | 19 个状态锁定单元测试 |
| 9 | `src/main/ipc/__tests__/merge-diagnosis.test.ts` | 修改 | 修复测试缺少 lockedSyndromes 字段 |
| 10 | `src/main/services/__tests__/prompt-builder.test.ts` | 修改 | 修复测试缺少 lockedSyndromes 字段 |

## DoD（完成标准）

- [x] S1. TeachingState 新增 lockedSyndromes 字段，数据库迁移正确执行
- [x] S2. 锁定机制：lockSyndromes 函数实现症候锁定，诊断合并时自动锁定新症候
- [x] S3. 解锁机制：unlockResolvedSyndromes 根据 resolved 状态自动解锁，updateSyndromeStatus 根据严重度变化更新症候状态
- [x] S4. TypeScript 编译无错误
- [x] S5. 19 个测试覆盖锁定/状态更新/解锁/判断全部解决/完整流程

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. 状态机回退到无锁定版本
3. 数据库回退：执行 `ALTER TABLE teaching_state DROP COLUMN locked_syndromes;`（SQLite 3.35.0+ 支持）

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| `src/renderer/shared/types.ts` | TeachingState 接口新增 `lockedSyndromes: string[]` 字段 |
| `src/main/services/teaching-state.types.ts` | TeachingStateRow 新增 `locked_syndromes: string` 字段 |
| `src/main/services/teaching-state.store.ts` | rowToRow/stateToRow 转换逻辑支持 lockedSyndromes JSON 序列化；create 方法初始化空数组；SQL 添加字段 |
| `src/main/db/011_add_locked_syndromes.sql` | 新增迁移：`ALTER TABLE teaching_state ADD COLUMN locked_syndromes TEXT DEFAULT '[]'` |
| `src/main/index.ts` | migrationFiles 数组添加 '011_add_locked_syndromes.sql' |
| `src/main/services/teaching-state-machine.ts` | 新增 4 个函数：lockSyndromes (锁定)、updateSyndromeStatus (严重度比较更新)、unlockResolvedSyndromes (解锁)、areAllSyndromesResolved (判断) |
| `src/main/services/diagnosis-merger-utils.ts` | mergeSyndromesIntoState 返回 lockedSyndromes，自动锁定新发现症候 |
| `src/main/services/__tests__/state-locking.test.ts` | 19 个测试：lockSyndromes(5) + updateSyndromeStatus(5) + unlockResolvedSyndromes(3) + areAllSyndromesResolved(5) + 完整流程(1) |
| `src/main/ipc/__tests__/merge-diagnosis.test.ts` | makeBaseState 添加 lockedSyndromes: [] |
| `src/main/services/__tests__/prompt-builder.test.ts` | makeState 添加 lockedSyndromes: [] |

### 验证结果

- [x] TypeScript 编译通过（`npx tsc --noEmit`）
- [x] 测试通过（`npx vitest run src/main/services/__tests__/state-locking.test.ts` - 19 passed）

### 输出产物

- 状态锁定机制核心函数 4 个（lockSyndromes/updateSyndromeStatus/unlockResolvedSyndromes/areAllSyndromesResolved）
- 数据库迁移脚本 011_add_locked_syndromes.sql
- 单元测试 19 个，覆盖锁定机制所有场景


## 下个任务建议

建议继续执行 T-013（能力成长可视化）或 T-021（诊断→训练闭环），实现 Training Agent 功能。
