# T-005: 长期能力表单与用户能力画像

> 版本：V1.0 | 创建：2026-06-02 | 状态：进行中
> 依据：SPEC_ability-profile_V1.0.md、ability-atlas.json、T-004 诊断持久化
> 回退方案：删除 007 迁移文件，移除 ability-profile.service.ts 和 training-record.service.ts

## 任务描述

将 diagnosis_results 中的原始诊断数据聚合为**用户能力画像**，实现能力评分、弱点标签、训练统计和诊断趋势分析。这是诊断数据从"一次性输出"升级为"持续追踪认知档案"的关键一步。

## 前置依赖

- T-004: 诊断结果持久化（数据基础已就绪）
- ability-atlas.json（能力映射体系已就绪）

## 涉及文件

| 文件路径 | 修改类型 |
|---------|---------|
| `src/main/db/007_user_training.sql` | 新增 |
| `src/main/services/ability-profile.service.ts` | 新增 |
| `src/main/services/training-record.service.ts` | 新增 |
| `src/main/ipc/ability-profile.handler.ts` | 新增 |
| `src/renderer/shared/types.ts` | 修改 |
| `src/preload/index.ts` | 修改 |
| `src/main/index.ts` | 修改 |

## DoD（完成标准）

1. **数据库迁移**：`007_user_training.sql` 成功创建 `user_training_records` 表，字段和索引完整
2. **类型定义完整**：`AbilityProfile`、`AbilityScore`、`WeakPoint`、`TrainingStats`、`DiagnosisTrend` 接口已定义
3. **评分算法正确**：
   - 严重度映射：L1→85, L2→55, L3→20（非线性）
   - 能力评分 = 相关症候非线性分数的平均值
   - 无记录时默认 100 分并标记"数据不足"
4. **弱点标签判定**：≥3次出现 或 (≥2次出现 且 最大严重度 ≥ L2)
5. **趋势判断**：最近5次 vs 之前5次的平均严重度对比
6. **训练记录 CRUD**：`training-record.service.ts` 支持增删改查
7. **IPC 通道**：`ability:getProfile` 通道可正确返回聚合结果
8. **类型检查 + 测试通过**：`npm run typecheck` 和 `npm test` 全部通过

## 变更溯源

### 依据链
- **设计哲学**：design-philosophy_V1.0.md → 第五章「诊断表 + 长期能力表单」
- **技术规格**：SPEC_ability-profile_V1.0.md
- **能力映射**：resources/knowledge-graph/ability-atlas.json

### 关键修正（相对于 SPEC V1.0）
- 数据库迁移编号由 006 改为 007（006 已被聚焦方向占用）
- 能力评分算法：由线性映射 (L1→66.67, L2→33.33, L3→0) 改为非线性映射 (L1→85, L2→55, L3→20)
- 弱点判定条件：由 "≥3 AND ≥2" 改为 "≥3 OR (≥2 AND max ≥ L2)"
