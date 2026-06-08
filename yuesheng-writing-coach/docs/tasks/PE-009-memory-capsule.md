# PE-009: 记忆胶囊机制

> **优先级**: P0 | **状态**: done | **预估**: 0.5d
> **依赖**: 无 | **后续**: F-04 分层反馈策略
> **来源**: docs/research/pro-writing-tools-report_V1.0.md → PE-009（Claude Projects "记忆胶囊机制"）

## 目标

每 3-5 次交互自动生成诊断摘要 + 进度注入上下文，确保 AI 理解完整的教学上下文。替代原有的纯诊断历史格式化逻辑。

## 设计依据

- **PE-009 模式定义**: docs/research/pro-writing-tools-report_V1.0.md → PE-009
  - 核心概念: 将最近诊断摘要 + 教学进度封装为结构化记忆胶囊
  - 标准化格式注入对话上下文
- **现有基础**: chat.handler.ts 中已存在 `formatDiagnosisHistory` 函数（最近 2 条诊断摘要 + 最高严重度症候）
- **相关服务**: DiagnosisService.getRecentBySession()、TeachingState 接口

## 改动方案

### 新增文件

| # | 文件 | 说明 |
|---|------|------|
| 1 | src/main/services/memory-capsule.service.ts | MemoryCapsuleService 类 + CapsuleOptions 接口 + 便捷函数 |

### 修改文件

| # | 文件 | 操作 | 说明 |
|---|------|:----:|------|
| 1 | src/main/ipc/chat.handler.ts | 修改 | 导入 MemoryCapsuleService，替换 formatDiagnosisHistory 实现 |
| 2 | docs/tasks/TASK-CHAIN.md | 修改 | 更新 PE-009 状态 |

### 核心逻辑

```
MemoryCapsuleService.buildCapsule(options):
  1. 最近 recentCount（默认 3）条诊断摘要（日期+症候+严重度）
  2. 当前聚焦：统计所有症候频率，取最高严重度（L2+ 才输出）
  3. 教学进度（可选）：阶段名称 + 步骤 + 进度百分比 + 已完成动作
  4. 教学建议（静态提示）
```

### CapsuleOptions 接口

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|:----:|:------:|------|
| diagnoses | DiagnosisEntry[] | 是 | - | 诊断历史列表 |
| progress | TeachingProgressDisplay | 否 | null | 教学进度显示 |
| title | string | 否 | '教学生态（记忆胶囊）' | 胶囊标题 |
| recentCount | number | 否 | 3 | 最近诊断取多少条 |

## DoD（完成标准）

- [x] D1. MemoryCapsuleService 能正确构建记忆胶囊文本（空诊断、摘要、聚焦、进度）
- [x] D2. chat.handler.ts 集成胶囊服务，最近诊断数从 2 条改为 3 条
- [x] D3. 16 个单元测试覆盖所有功能场景
- [x] D4. tsc 无错误，全量 455 测试全部通过

## 回退方案

1. 回退 chat.handler.ts 到旧版 formatDiagnosisHistory 实现
2. 删除 memory-capsule.service.ts 及测试文件

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| src/main/services/memory-capsule.service.ts | 新建：MemoryCapsuleService + CapsuleOptions + 便捷函数 |
| src/main/services/__tests__/memory-capsule.service.test.ts | 新建：16 个测试覆盖全部场景 |
| src/main/ipc/chat.handler.ts | 导入胶囊服务，替换 formatDiagnosisHistory（2→3 条），移除未使用的 severityToNumber 导入 |
| docs/tasks/TASK-CHAIN.md | 更新 PE-009 状态 |

### 验证结果

- [x] tsc 无错误
- [x] 测试全部通过（39 文件 / 455 tests）
- [x] 16 个胶囊服务测试全部通过
