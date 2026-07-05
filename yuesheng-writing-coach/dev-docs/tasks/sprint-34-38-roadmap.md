# Sprint 34-38: 后续任务序列

> 依据: Sprint 33 完工复盘 + 活跃债务表 (D-DEBT-30~37) + 用户方向选择
> GStack 阶段: Think → Plan

## 序列总览

| Sprint | 主题 | 类型 | 依赖 | 预估 |
|:------:|------|:----:|:----:|:----:|
| **34** | 基础设施债务清理 | 债务 | 无 | ~200 行 |
| **35** | 训练流端到端完善 | 功能 | Sprint 34 | ~150 行 |
| **36** | 硬编码映射表第二波（主进程） | 重构 | 无 | ~180 行 |
| **37** | 测试覆盖率加厚 | 质量 | 无 | ~300 行 |
| **38+** | 新功能/待定 | 功能 | 以上全部 | 待定 |

---

## Sprint 34: 基础设施债务清理

**目标**: 清理 C-2/C-3 暴露的基础设施缺口，消除空状态占位符。

### 活跃债务状态（确认）

| 债务 | 描述 | 优先级 | Sprint 33 后状态 |
|:----:|------|:------:|:----------------:|
| D-DEBT-30 | ChatPage 历史消息分页 | P2 | 未动 |
| D-DEBT-31 | ProjectSpacePage 雷达图数据源 | P2 | C-2 部分缓解（ability.store 接入），仍缺 stats IPC |
| D-DEBT-32 | 4 子页 Store 实装 | **P1** | **C-3 已完成 ✅** |
| D-DEBT-33 | ProjectSpacePage 维度数据整合 | P2 | 未动 |
| D-DEBT-34 | typedInvoke 降级 | 已完成 | **D-060/D-061 已收尾 ✅** |
| D-DEBT-35 | a11y moderate/minor | P3 | 未动 |
| D-DEBT-36 | 视觉基线重建流程 | P3 | 未动 |
| D-DEBT-37 | Electron 端到端烟测 | P2 | 未动 |

### 实施项

1. **stats/activity IPC 端点** — 新增主进程 handler 聚合练习次数/诊断总数/提升幅度
2. **雷达图数据源** — 建立 capability 聚合查询，替换 `SYNDROME_KEYWORD_MAP` 关键词匹配
3. **消息分页** — ChatPage 历史消息加载上限处理（当前无上限加载）

**涉及文件**: `src/main/domains/` (新 IPC handler), `src/renderer/pages/ProjectSpacePage.tsx`, `src/renderer/pages/ChatPage.tsx`

---

## Sprint 35: 训练流端到端完善

**目标**: C-5 已打通 UI 入口，但训练流端到端链路需要对齐 orchestrator 侧事件生产和主进程评估推送。

### 实施项

1. **training_triggered 事件生产验证** — 确保 orchestrator 在诊断后正确触发训练事件
2. **评估结果推送链路** — 主进程 evaluate → renderer store 同步 → FlowPanel 展示
3. **训练完成通知优化** — 完成消息展示评估摘要（得分/反馈）

**涉及文件**: `src/main/domains/03-teaching/chat/`, `src/renderer/pages/ChatPage.tsx`

---

## Sprint 36: 硬编码映射表第二波（主进程）

**目标**: 将 `src/main/domains/` 下的硬编码映射表外置为 JSON 配置（R-014 合规延续）。

### 已知位置

| 位置 | 映射表 | 行号 |
|:-----|:-------|:----:|
| `student-model-service.ts` | `styleMap`/`maturityMap`/`proficiencyMap` | L407-417 |
| `student-model-analyzer.ts` | `styleMap`/`maturityMap`/`proficiencyMap` | L319-329 |
| `router.layer2.ts` | `styleMap` 反向查找 | L96-98 |

**涉及文件**: `src/main/domains/02-prescription/student/` (3 个文件)

---

## Sprint 37: 测试覆盖率加厚

**目标**: 提升测试覆盖率，对齐 R-013 规范要求。

### 实施项

1. ChatPage 新增集成测试（训练入口交互）
2. FlowPanel 训练完成回调测试
3. ProjectSpacePage 能力数据集成测试
4. 边界情况测试（空数据、加载失败、训练创建失败）

**涉及文件**: 各 `__tests__/` 目录

---

## Sprint 38+: 新功能 / 待定

待以上债务清理和测试夯实后，进入新功能开发阶段。候选方向：
- 用户自定义训练计划
- 多作品管理
- 写作进度追踪
- 社交/分享功能

---

## 门禁

每个 Sprint 完工必须通过：
- typecheck: 0 error
- test: 全绿
- lint: 0 error
- decision-log.md 追加对应条目
