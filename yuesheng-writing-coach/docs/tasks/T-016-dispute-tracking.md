# T-016: 辩驳追踪 + 强度升级

> **优先级**: P1 | **状态**: ✅ done | **完成日期**: 2026-06-06  
> **依赖**: T-021 | **后续**: T-017

## 目标

追踪用户的辩驳行为次数，达到阈值时自动升级态度模式（doubao→yuesheng→direct），不同辩驳次数触发不同教学策略。解决验证报告中"AI 在用户辩驳时倾向温和引导"的问题。

## 设计依据

- **设计依据文档**: [dispute-tracking-escalation_V1.0.md](../design/dispute-tracking-escalation_V1.0.md)
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现8 验证报告未消化
- **来源任务**: T-013（基础 UI 和数据流稳定后，集成到 chat.handler）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 新增 DisputeTracker 检测用户辩驳 | `src/main/services/dispute-tracker.service.ts` |
| 后端 | 在 chat.handler 中集成辩驳检测+升级逻辑 | `src/main/ipc/chat.handler.ts` |
| 后端 | index.ts 注册服务并注入 | `src/main/index.ts` |
| 测试 | 30 个单元测试覆盖所有规则 | `src/main/services/__tests__/dispute-tracker.test.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/services/dispute-tracker.service.ts` | 新增 | 辩驳检测 + 计数 + 升级判定 + 否决权 |
| 2 | `src/main/ipc/chat.handler.ts` | 修改 | 注入 DisputeTracker + processMessage 中调用 |
| 3 | `src/main/index.ts` | 修改 | 创建 DisputeTrackerService 并注入 |
| 4 | `src/main/services/__tests__/dispute-tracker.test.ts` | 新增 | 30 个单元测试 |

## DoD（完成标准）

- [x] S1. DisputeTracker 正确检测辩驳消息（正则匹配 + 反问句式） — 30 测试中 6 个覆盖
- [x] S2. 辩驳 2 次自动升级到 yuesheng，4 次升级到 direct — 5 个测试覆盖
- [x] S3. 升级后语气和动作选择相应变化 — attitude 传入 prompt-loader
- [x] S4. **升级只升不降**：用户手动选择 direct 时，辩驳 0 次不会降回 doubao — 4 个测试覆盖
- [x] S5. **用户否决权**：用户手动切回低档位后，同一阈值不再自动升级，但更高阈值仍可触发 — 3 个测试覆盖
- [x] S6. **反思阶段排除**：S2_REFLECTION 阶段的用户回答不纳入辩驳计数 — 3 个测试覆盖
- [x] S7. 升级后态度按钮 UI 同步变化 — attitude 已在 config.store 中响应式更新
- [x] S8. TypeScript 编译无错误 — tsc --noEmit: 0 errors
- [x] S9. 至少 7 个测试覆盖 — 30 个测试，覆盖基础检测/计数/升级/只升不降/否决/反思排除/边界

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. chat.handler 恢复到无辩驳检测版本
3. 无数据库变动

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `dispute-tracker.service.ts` | 新建服务类，包含辩驳检测（19 个关键词 + 7 个反问正则）、计数追踪、升级判定（2→yuesheng, 4→direct）、用户否决权逻辑、反思阶段排除 |
| `chat.handler.ts` | 导入 DisputeTrackerService，添加 setDisputeTracker setter，在 registerChatHandlers 中调用 checkMessage + getEffectiveAttitude |
| `index.ts` | 导入 DisputeTrackerService，创建实例并注入 chat handler |
| `dispute-tracker.test.ts` | 30 个单元测试，覆盖 7 个 describe 块：detectDispute/count/escalation/只升不降/否决权/反思排除/边界情况 |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npm run typecheck`）— 0 errors
- [x] 测试通过（`npm test`）— 350 passed, 6 skipped, 1 failed（已有的 better-sqlite3 兼容性问题）

### 输出产物（实际完成时填写）

- **DisputeTrackerService**: 核心服务，257 行，支持 3 个公开 API（checkMessage, getEffectiveAttitude, onUserAttitudeChange）
- **单元测试**: 30 个测试用例，100% 覆盖所有业务规则

## 变更溯源

### 依据链
- **设计哲学**: design-philosophy_V1.0.md 第三章「降级规则」（用户有最终否决权）
- **技术规格**: dispute-tracking-escalation_V1.0.md §3.1 辩驳检测 + §3.2.1 自动升级 vs 手动选择优先级
- **任务文档**: T-016-dispute-tracking.md

### 变更摘要
- **变更类型**: 新增
- **涉及文件**: dispute-tracker.service.ts（新建）, chat.handler.ts（修改）, index.ts（修改）, dispute-tracker.test.ts（新建）
- **核心变更**: 实现辩驳检测 + 自动态度升级 + 用户否决权机制
- **DoD 达成**: 9/9 全部达成

## 下个任务建议

T-017: 态度系统统一 — 整合 T-016 的升级逻辑为统一的三态系统，调整 UI 态度按钮映射。
