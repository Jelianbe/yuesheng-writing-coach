# T-013: 能力成长可视化

> **优先级**: P1 | **状态**: completed | **预估**: 2d  
> **依赖**: T-012 ✅ | **后续**: T-021

## 目标

在右侧栏展示跨对话的症候严重度趋势，让用户看到自身进步（同一症候从 L3→L2→L1 或消失）。不依赖训练评分，而是基于每次对话的诊断数据进行自然语言描述。

## 设计依据

- **设计依据文档**: [training-effectiveness-scoring_V2.0.md](../specs/training-effectiveness-scoring_V2.0.md) §二 症候严重度趋势
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现5 评分幽灵（明确不做评分，只做趋势）
- **来源任务**: T-012（右侧栏数据同步已就绪）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 新增 GrowthTrendService，计算跨对话症候趋势 | `src/main/services/growth-trend.service.ts` |
| 后端 | 在 diagnosis.handler 中注入成长趋势数据 | `src/main/ipc/diagnosis.handler.ts` |
| 前端 | 右侧栏能力成长部分对接 API 数据 | `src/renderer/App.tsx` |
| 数据 | V2.0 评分规范文档 | `docs/specs/training-effectiveness-scoring_V2.0.md` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/services/growth-trend.service.ts` | 新增 | 聚合诊断数据计算症候趋势，映射为四种状态 |
| 2 | `src/main/services/__tests__/growth-trend.test.ts` | 新增 | 9 个单元测试覆盖趋势计算逻辑 |
| 3 | `src/shared/constants.ts` | 修改 | 添加 GROWTH_GET_TRENDS IPC 通道 |
| 4 | `src/main/ipc/diagnosis.handler.ts` | 修改 | 注册 GrowthTrendService 和 GROWTH_GET_TRENDS 处理器 |
| 5 | `src/main/index.ts` | 修改 | 创建并注册 GrowthTrendService |
| 6 | `src/preload/index.ts` | 修改 | 允许 growth:getTrends 通道 |
| 7 | `src/renderer/App.tsx` | 修改 | buildGrowthItems 改用 GrowthTrend 数据，新增 fetchGrowthTrends |

## DoD（完成标准）

- [x] S1. GrowthTrendService 能正确计算同一症候跨对话严重度趋势
- [x] S2. 右侧栏展示"已掌握/进步中/稳定/需关注"四种状态，不展示数字评分
- [x] S3. IPC 通道传输成长摘要数据
- [x] S4. **术语一致性**：趋势展示使用的症候名称通过 SYNDROME_NAMES 映射，与翻译层共享同一映射源
- [x] S5. TypeScript 编译无错误
- [x] S6. 9 个单元测试覆盖趋势计算逻辑

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. IPC 通道不回退，前端状态缺失时显示空状态
3. 配置文件无变化

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| `src/main/services/growth-trend.service.ts` | 新增 GrowthTrendService，依赖 StudentModelService 获取症候画像，计算趋势并映射为 mastered/improving/stable/needsAttention 四种状态 |
| `src/main/services/__tests__/growth-trend.test.ts` | 9 个测试：空数据/稳定/进步/需关注/worsening/自定义名称映射/多症候混合场景 |
| `src/shared/constants.ts` | 添加 `GROWTH_GET_TRENDS: 'growth:getTrends'` |
| `src/main/ipc/diagnosis.handler.ts` | 导入 GrowthTrendService/SYNDROME_NAMES，添加 setGrowthTrendService 注册函数，添加 GROWTH_GET_TRENDS IPC 处理器 |
| `src/main/index.ts` | 导入 GrowthTrendService/setGrowthTrendService，创建实例并注册 |
| `src/preload/index.ts` | 允许 `growth:getTrends` 通道 |
| `src/renderer/App.tsx` | buildGrowthItems 改用 GrowthTrend 数组，新增 growthTrends 状态和 fetchGrowthTrends 方法，在流结束/切换会话时获取趋势数据 |

### 验证结果

- [x] TypeScript 编译通过（`npx tsc --noEmit`）
- [x] 测试通过（`npx vitest run src/main/services/__tests__/growth-trend.test.ts` - 9 passed）
- [x] 全量测试 294 passed / 6 skipped / 1 failed (better-sqlite3 环境问题)

### 输出产物

- GrowthTrendService 服务（状态映射：mastered/improving/stable/needsAttention）
- 单元测试 9 个
- IPC 通道 growth:getTrends
- 右侧栏能力成长部分对接真实诊断趋势数据


## 下个任务建议

建议继续执行 T-021（诊断→训练闭环），实现 Training Agent 功能，完成"诊断→训练→验证"的完整教学链路。
