# T-016: 辩驳追踪 + 强度升级

> **优先级**: P1 | **状态**: draft | **预估**: 2d  
> **依赖**: T-021 | **后续**: T-017

## 目标

追踪用户的辩驳行为次数，达到阈值时自动升级态度模式（doubao→yuesheng→sensei），不同辩驳次数触发不同教学策略。解决验证报告中"AI 在用户辩驳时倾向温和引导"的问题。

## 设计依据

- **设计依据文档**: [dispute-tracking-escalation_V1.0.md](../design/dispute-tracking-escalation_V1.0.md)
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现8 验证报告未消化
- **来源任务**: T-013（基础 UI 和数据流稳定后，集成到 chat.handler）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | 新增 DisputeTracker 检测用户辩驳 | `src/main/services/dispute-tracker.service.ts` |
| 后端 | 在 chat.handler 中集成辩驳检测+升级逻辑 | `src/main/ipc/chat.handler.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/main/services/dispute-tracker.service.ts` | 新增 | 辩驳检测 + 计数 + 升级判定 |
| 2 | `src/main/ipc/chat.handler.ts` | 修改 | processMessage 中调用 DisputeTracker |

## DoD（完成标准）

- [ ] S1. DisputeTracker 正确检测辩驳消息（正则匹配 + 反问句式）
- [ ] S2. 辩驳 2 次自动升级到 yuesheng，4 次升级到 sensei
- [ ] S3. 升级后语气和动作选择相应变化
- [ ] S4. **升级只升不降**：用户手动选择 sensei 时，辩驳 0 次不会降回 doubao
- [ ] S5. **用户否决权**：用户手动切回低档位后，同一阈值不再自动升级，但更高阈值仍可触发
- [ ] S6. **反思阶段排除**：S2_REFLECTION 阶段的用户回答不纳入辩驳计数
- [ ] S7. 升级后态度按钮 UI 同步变化
- [ ] S8. TypeScript 编译无错误
- [ ] S9. 至少 7 个测试覆盖：基础升级、只升不降、用户否决、反思排除

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. chat.handler 恢复到无辩驳检测版本
3. 无数据库变动

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
