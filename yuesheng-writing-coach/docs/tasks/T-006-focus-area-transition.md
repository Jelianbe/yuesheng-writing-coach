# T-006: 聚焦方向与过渡邀请机制

> 版本：V1.0 | 创建：2026-06-02 | 状态：已完成
> 依据：SPEC_focus-area-transition_V1.0.md

## 任务描述

实现聚焦方向（Focus Area）与过渡邀请机制，允许用户在进入系统时选择"世界观构建"、"角色/OC设计"或"综合提升"方向，并在完成专精领域后收到一次性的过渡邀请反问，优雅引导用户探索相邻创作领域。

## 前置依赖

- T-004: 教学状态机基础实现（已完成）
- T-005: 诊断系统扩展（已完成）
- SPEC_focus-area-transition_V1.0.md（已创建）

## 涉及文件

| 文件路径 | 修改类型 |
|---------|---------|
| `src/renderer/shared/types.ts` | 修改 |
| `src/main/services/teaching-state.types.ts` | 修改 |
| `src/main/services/teaching-state-machine.ts` | 修改 |
| `src/main/services/teaching-state.store.ts` | 修改 |
| `src/main/services/recommendation-engine.ts` | 修改 |
| `src/main/db/006_add_focus_area.sql` | 新增 |
| `src/main/index.ts` | 修改 |
| `src/main/ipc/__tests__/merge-diagnosis.test.ts` | 修改 |

## DoD（完成标准）

1. **类型定义完整**：`TeachingState` 和 `TeachingStateRow` 均包含 `focusArea` 和 `transitionOffered` 字段，类型正确
2. **状态机逻辑正确**：
   - `character` 模式下 WORLD 阶段只走 `WORLD_PROTAGONIST` 子阶段
   - `worldbuilding` 和 `general` 模式保持完整的 5 个子阶段
   - `getNextSubphase` 支持按 `focusArea` 过滤子阶段序列
3. **过渡邀请触发准确**：`shouldOfferTransition` 函数正确判断：仅专精模式、未邀请过、已完成核心教学时返回 true
4. **Prompt 注入有效**：`buildSystemPromptWithState` 根据 `focusArea` 注入对应的诊断优先策略和教学引导策略
5. **推荐排序支持**：`recommendation-engine.ts` 的 `sortByFocusArea` 按聚焦方向优先排序相关症候的训练任务
6. **数据库迁移完整**：`006_add_focus_area.sql` 正确添加字段并创建索引，`index.ts` 中执行该迁移
7. **测试通过**：`npm run typecheck` 和 `npm test` 全部通过

## 变更溯源

### 依据链
- **设计哲学**：design-philosophy_V1.0.md → 用户主权原则、降级规则
- **技术规格**：docs/specs/SPEC_focus-area-transition_V1.0.md
- **用户场景**：专精世界观/OC 的用户需要被邀请进入故事创作，而非强制转换

### 变更摘要
- **变更类型**：新增
- **核心变更**：
  1. 新增 `FocusArea` / `FocusAreaValue` 类型
  2. `TeachingState` / `TeachingStateRow` 增加 `focusArea` + `transitionOffered`
  3. 状态机增加 `FOCUS_AREA_WORLD_SUBPHASES` 映射和 `shouldOfferTransition` 判断
  4. `buildSystemPromptWithState` 增加 `buildFocusAreaPrompt` 注入
  5. `recommendation-engine.ts` 增加 `sortByFocusArea` 函数
  6. 数据库增加 `006_add_focus_area.sql` 迁移
  7. 过渡邀请话术外置到 `resources/config/transition-prompts.json`
  8. 新增 `transition-prompt-loader.ts` 加载器（支持模板变量、多版本轮询）

### 验证
- [x] 变更是否与设计哲学一致
- [x] 变更是否按技术规格执行
- [x] 任务 DoD 是否全部达成
- [x] 类型检查通过（`npm run typecheck`）
- [x] 测试通过（`npm test`，81/81）

## 回退方案

删除 `focusArea` 和 `transitionOffered` 字段，恢复状态机到 T-004 完成状态：
1. 回滚 `src/main/db/006_add_focus_area.sql` 的 ALTER TABLE 操作（SQLite 不支持 ALTER DROP COLUMN，需重建表）
2. 移除所有使用新字段的代码逻辑
3. 恢复 `teaching-state-machine.ts` 到 T-004 版本
