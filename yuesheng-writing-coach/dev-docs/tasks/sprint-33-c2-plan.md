# Sprint 33 C-2: ProjectSpacePage Mock 数据替换

> 依据: sprint-33-user-gaps-plan.md
> GStack: Plan → Build

## 现状分析

ProjectSpacePage 当前有 5 处 mock/占位数据：

| 位置 | 问题 | 标注 | 替换可行性 |
|------|------|------|-----------|
| `RADAR_VALUES = [4,3,5,2,4]` | 硬编码数组 | D-DEBT-30 | 需 sessionId → `ability.store.fetchProfile()` |
| 统计卡片 `value: '—'` | 横杠占位 | D-DEBT-30 | 需 session 聚合数据，前置依赖 |
| `RECENT_RECORDS` 常量 | 硬编码 3 条假数据 | D-DEBT-31 | 无 activity/history IPC 端点 |
| `CHAPTERS` 常量 | 硬编码 3 条假数据 | D-DEBT-30 | project→manuscript DB 映射未持久化 |
| `STATUS_MAP` 常量 | 状态颜色映射 | — | C-4 处理，本次暂不动 |

## 基础设施限制

- **session.store 无 projectId 字段**: 无法通过 projectId 查询关联 session
- **project→manuscript 映射**: 仅存在于 renderer 内存态，未持久化到 DB
- **无 stats/activity IPC**: 无聚合统计或最近活动的后端端点

## 实施策略

采用"能接则接，不能则空"原则：

1. **雷达图**: 接受 `params.sessionId`，如果有则用 `ability.store.fetchProfile()` 获取真实评分；否则渲染空雷达图
2. **统计卡片**: 将 `'—'` 替换为 `0` + 添加 TODO 注释
3. **最近记录**: 替换为 `[]` + 渲染"暂无学习记录"空状态
4. **作品章节**: 保留空数组 + 渲染"暂无章节"空状态
5. **空状态统一**: 所有空数据区域显示友好提示而非横杠

## 改动清单

**文件**: `src/renderer/pages/ProjectSpacePage.tsx`

- [ ] 导入 `useAbilityStore`
- [ ] 从 `abilityStore.fetchProfile(sessionId)` 加载能力画像
- [ ] RadarChart 改为响应式：接受外部 `values` prop 替代全局常量
- [ ] 统计卡片: `'—'` → `0`
- [ ] 最近记录: mock 常量 → `[]` → 空状态 UI
- [ ] 章节列表: mock 常量 → `[]` → 空状态 UI
- [ ] 添加 loading/error 状态处理

## 门禁

- typecheck: 0 error
- test: 全绿（14 个现有测试需适配 mock 替换）
- lint: 0 warning

## 预估

约 120 行改动
