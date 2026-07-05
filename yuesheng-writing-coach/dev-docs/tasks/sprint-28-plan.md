# Sprint 28 — `no-non-null-assertion` 生产代码专项治理

> **范围**: 清理生产代码中 ~68 个 `no-non-null-assertion` warning，附带清理剩余 45 个其他 warning
> **依据**: Sprint 27 清洗结果 — 253 → 113 warnings（R-019 代码规范标准）
> **前置**: Sprint 27 lint 专项（测试/工具文件 disable 完成，基线 300 安全）
> **更新**: 2026-07-04

---

## 0. 目标与边界

### 0.1 目标

- 生产代码中 `@typescript-eslint/no-non-null-assertion` warning **减少 ≥ 80%**（~68 → ≤ 14）
- 附带清理剩余 test 文件的同类 warning（~37 个）
- 残余 `no-console` / `consistent-type-imports` / `no-unused-vars` 一并处理
- 保持 `--max-warnings 300` 不变，预期最终降至 **≤ 30 warnings**

### 0.2 不在范围

- ❌ 业务逻辑重构（R-010 最小化不顺手）
- ❌ 新功能添加
- ❌ 测试覆盖率提升（R-013 是独立工作流）
- ❌ Capacitor Android 端端到端验证（D-076 已记，推 S27+）

---

## 1. 现状快照

### 1.1 门禁状态

| 门禁 | Sprint 27 结果 |
|:-----|:--------------:|
| Typecheck | 0 error ✅ |
| Tests | 1007 passed ✅ |
| Lint | 113 warnings（基线 300）✅ |

### 1.2 113 个剩余 warning 分类

#### A. 生产代码 `no-non-null-assertion`（68 个，17 个文件）— 核心目标

| 文件 | 数量 | 风险等级 |
|:-----|:----:|:--------:|
| `src/shared/storage/adapters/memory.adapter.ts` | 10 | 中 |
| `src/main/domains/02-prescription/ability-atlas/ability-atlas.loader.ts` | 18 | 高（核心模块） |
| `src/main/domains/01-diagnosis/distillation/distillation.loader.ts` | 12 | 高（诊断核心） |
| `src/main/domains/02-prescription/development-path/development-path.service.ts` | 7 | 中 |
| `src/shared/storage/adapters/capacitor-sqlite.adapter.ts` | 6 | 中 |
| `src/main/ipc/chat.handler.ts` | 3 | 低（薄 wrapper） |
| `src/main/domains/03-teaching/chat/chat-orchestrator.service.ts` | 2 | 高（教学核心） |
| `src/main/domains/01-diagnosis/evidence/evidence-grouping.ts` | 1 | 低 |
| `src/main/domains/02-prescription/technique-pool.service.ts` | 1 | 低 |
| `src/main/domains/03-teaching/conversation/real-orchestrator-adapter.ts` | 1 | 低 |
| `src/main/domains/03-teaching/prompt/memory-capsule.service.ts` | 1 | 中 |
| `src/main/domains/03-teaching/prompt/skill-dispatcher.ts` | 1 | 中 |
| `src/main/domains/03-teaching/state/teaching-state-machine.locking.ts` | 1 | 低 |
| `src/main/domains/04-validation/training/flow-mapping.loader.ts` | 1 | 低 |
| `src/main/shared/llm/middleware/retry.ts` | 1 | 低 |
| `src/renderer/services/diagnosis.service.ts` | 1 | 中 |
| `src/shared/services/session.service.ts` | 1 | 低 |

#### B. 测试文件 `no-non-null-assertion`（37 个，3 个文件）— 附带清理

| 文件 | 数量 |
|:-----|:----:|
| `src/main/domains/01-diagnosis/evidence/evidence.service.test.ts` | 17 |
| `src/main/domains/02-prescription/ability-atlas/__tests__/ability-atlas.loader.test.ts` | 11 |
| `src/main/domains/02-prescription/development-path/__tests__/development-path.service.test.ts` | 9 |

#### C. 其他（8 个）

| 类别 | 文件 | 数量 |
|:-----|:-----|:----:|
| `no-console` | `src/main/core/app-initializer.ts` | 3 |
| `no-non-null-assertion` | `src/test/reporter.ts` | 1 |
| `consistent-type-imports` | `src/main/core/ipc-registry.ts` | 1 |
| `consistent-type-imports` | `src/main/domains/01-diagnosis/orchestrator/__tests__/diagnosis-orchestrator-s16-filter.test.ts` | 1 |
| `no-unused-vars` | `src/shared/storage/adapters/capacitor-sqlite.adapter.ts`（`_rollbackErr`） | 1 |

---

## 2. 修复策略

每个 `!` 断言代表一个"开发者确认非空"的假设。正确的修复方式是**用类型安全的等价写法替换**，而不是简单删除 `!`。

### 2.1 通用修复模式

| 模式 | 原始代码 | 修复后 |
|:-----|:---------|:-------|
| Map.get 后断言 | `map.get(key)!` | `const v = map.get(key); if (!v) throw ...` |
| 数组索引 | `arr[i]!` | `const v = arr[i]; if (!v) ...` 或 `arr[i] as T` 加注释 |
| 可选链后断言 | `obj.foo!.bar` | `if (!obj.foo) return; obj.foo.bar` |
| 类型守卫缺失 | `x as Type` | 加 type guard 函数 |
| 初始化后非空 | `this.prop!` | 用 `!:` 声明（延迟初始化声明） |

### 2.2 三档处理策略

| 档位 | 适用 | 方法 | 预期覆盖 |
|:-----|:-----|:-----|:--------:|
| **S 档（Safe）** | 上下文简单，`!` 可安全替换为类型守卫 | 直接改写 | ~30 个 |
| **M 档（Medium）** | 需要理解上下文逻辑 | 逐行审查 + 改写 | ~25 个 |
| **R 档（Risk）** | 核心模块/逻辑复杂，改错风险高 | 保留 `!`，加 `eslint-disable-next-line` + 理由注释 | ~13 个 |

### 2.3 文件分档

| 文件 | S 档 | M 档 | R 档 |
|:-----|:----:|:----:|:----:|
| `memory.adapter.ts`（10） | 8 | 2 | 0 |
| `ability-atlas.loader.ts`（18） | 8 | 8 | 2 |
| `distillation.loader.ts`（12） | 6 | 4 | 2 |
| `development-path.service.ts`（7） | 4 | 2 | 1 |
| `capacitor-sqlite.adapter.ts`（6） | 4 | 2 | 0 |
| `chat.handler.ts`（3） | 2 | 1 | 0 |
| `chat-orchestrator.service.ts`（2） | 0 | 1 | 1 |
| 其余 10 个文件（每文件 1 个） | 10 | 0 | 0 |

### 2.4 附带清理

| 类别 | 处理方式 |
|:-----|:---------|
| 3 个测试文件（37 个） | 加文件级 `/* eslint-disable @typescript-eslint/no-non-null-assertion */` |
| `app-initializer.ts` 3 个 no-console | 改为 `console.warn`（同 Sprint 27 做法） |
| `ipc-registry.ts` 1 个 `import()` | 拆为顶层 `import type` |
| `diagnosis-orchestrator-s16-filter.test.ts` | 拆为顶层 `import type` |
| `reporter.ts` 1 个 no-non-null-assertion | 加行级 disable |
| `_rollbackErr` unused-vars | 确认 eslint 配置是否应匹配 catch 参数，如不匹配改为 `/* eslint-disable-line */` |

---

## 3. 阶段拆解

### 阶段 1: 低风险文件 + 附带清理（0.5 天） ✅ 完成

**文件**:
- `technique-pool.service.ts` / `evidence-grouping.ts` / `real-orchestrator-adapter.ts` / `memory-capsule.service.ts` / `skill-dispatcher.ts` / `teaching-state-machine.locking.ts` / `flow-mapping.loader.ts` / `retry.ts` / `diagnosis.service.ts` / `session.service.ts`
- 3 个测试文件加 disable
- `app-initializer.ts` no-console → warn
- `ipc-registry.ts` / `diagnosis-orchestrator-s16-filter.test.ts` import 修复
- `reporter.ts` 行级 disable
- `_rollbackErr` 处理

**DoD**:
- 10 个简单文件 + 3 个测试文件 + 4 个其他 → warning -15
- typecheck 0 error
- test 全部通过

### 阶段 2: 中等风险文件（1 天） ✅ 完成

**文件**:
- `memory.adapter.ts`（10 个）— 纯数据访问层，上下文简单
- `capacitor-sqlite.adapter.ts`（6 个）— 存储层，有 async 边界
- `development-path.service.ts`（7 个）— 业务逻辑已知
- `chat.handler.ts`（3 个）— 薄 wrapper

**DoD**:
- 4 个文件 ~26 个 warning 清理
- S 档全部改写，M 档逐行审查
- 每个 `!` 替换后验证 typecheck + 测试
- typecheck 0 error, test 全部通过

### 阶段 3: 高风险核心模块（1 天） ✅ 完成

**文件**:
- `ability-atlas.loader.ts`（18 个）— 核心载荷模块
- `distillation.loader.ts`（12 个）— 诊断蒸馏核心
- `chat-orchestrator.service.ts`（2 个）— 教学编排

**DoD**:
- R 档加 `eslint-disable-next-line` + 理由注释
- S/M 档改写
- typecheck 0 error, test 全部通过
- 手工 smoke 核心链路（诊断 → 教学 → 训练）

### 阶段 4: 收尾门禁（0.25 天） ✅ 完成

- 运行完整门禁：`npm run typecheck && npm run test && npm run lint`
- 预期 lint ≤ 30 warnings
- 写入决策日志 D-078

---

## 4. 总 DoD

1. ✅ 生产代码 17 个文件的 `!` 断言逐行审查/改写
2. ✅ 3 个测试文件加 disable 或改写
3. ✅ `app-initializer.ts` / `ipc-registry.ts` 等附带清理
4. ✅ typecheck 0 error
5. ✅ 测试 1007 passed
6. ✅ lint 0 warning（基线 300）
7. ✅ 决策日志 D-079 写入 Sprint 28 完工

---

## 5. 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| `!` 删除后运行时 NPE | 崩溃 | 替换为抛出语义化错误或安全 fallback |
| 核心模块改错导致回归 | 诊断/教学链断裂 | 阶段 3 R 档保留 `!` + disable 注释 |
| 改写后测试覆盖率不足 | 未覆盖的新路径 NPE | 为 `!` 替换路径补充单测 |
| 逐行审查遗漏 | 部分 warning 残留 | 最终 lint 扫描验证，残留项记录债务 |

---

## 6. 时间盒

| 子阶段 | 工时 | 累计 |
|:-------|:----:|:----:|
| 阶段 1: 低风险 + 附带 | 0.5 天 | 0.5 |
| 阶段 2: 中等风险 | 1 天 | 1.5 |
| 阶段 3: 高风险核心 | 1 天 | 2.5 |
| 阶段 4: 收尾门禁 | 0.25 天 | 2.75 |
| **总计** | **2.75 工作日** | |

---

## 7. 决策点

| # | 决策 | 推荐 | 说明 |
|:--|:-----|:----:|:-----|
| D1 | R 档保留 `!` 的模式是否接受 | ✅ 接受 | 加 `eslint-disable-next-line` + 理由注释，不删除安全断言 |
| D2 | 阶段 3 核心模块是否需手工 smoke | ✅ 需要 | 修改后运行一次诊断 → 教学 → 训练全链路 |
| D3 | 残余 warning 处理 | ⏸ 推 S29+ | 预期最终 ≤ 30，可接受，S29 再清零 |
