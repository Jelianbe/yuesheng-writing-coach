# Sprint 33: 用户侧可见缺口修复

> 依据: D-085 真实就绪评估报告
> GStack 阶段: Think → Plan

## 背景

前序 Sprint (31-32) 完成了基础设施层的重构（配置持久化、Chat Android 激活、IPC 层统一）。
本次 Sprint 目标是修复用户在应用使用过程中会直接撞到的 4 个 P1 缺口。

## 任务清单

### C-1: ChatPage 事件响应链路打通

**问题**: ChatPage 接收 orchestrator 事件（`diagnosis_extracted`、`phase_transition`、`training_triggered`）后仅做 `console.log`，没有任何 UI 反馈。

**DoD**:
- [ ] `diagnosis_extracted` 事件 → 更新教学状态机并显示诊断结果面板
- [ ] `phase_transition` 事件 → 自动跳转到对应教学阶段 UI
- [ ] `training_triggered` 事件 → 自动打开 FlowPanel 训练流
- [ ] 事件处理有错误边界（事件缺失/异常不阻塞聊天）

**涉及文件**: `src/renderer/pages/ChatPage.tsx`, `src/renderer/hooks/useOrchestrator.ts`

**预估**: 约 80 行改动

---

### C-2: ProjectSpacePage Mock 数据替换

**问题**: 雷达图使用 `RADAR_VALUES = [4, 3, 5, 2, 4]` 写死数组，统计卡片显示 `—` 占位符，最近记录和章节列表为硬编码常量。卡片数值 `'—'` 占位符——这3个值已标注 D-DEBT-30、D-DEBT-31。

**DoD**:
- [ ] 雷达图接入 `ability.store.fetchProfile()` 真实数据
- [ ] 统计 3 列卡片（练习次数/诊断总数/提升幅度）接入真实计数
- [ ] 最近学习记录接入真实数据（替换 `RECENT_RECORDS` 常量）
- [ ] 章节列表接入真实数据（替换 `CHAPTERS` 常量）
- [ ] 无数据时显示空状态而非横杠

**涉及文件**: `src/renderer/pages/ProjectSpacePage.tsx`, `src/renderer/stores/ability.store.ts`

**预估**: 约 120 行改动

---

### C-3: 4 子页数据通路打通 (D-DEBT-32)

**问题**: ability.store、growth.store、prescription.store、retro.store 接口已定义但数据流未打通，页面显示"数据加载中…"。

**DoD**:
- [ ] `ability.store.fetchProfile()` → 后端 `ability:getProfile` handler → 返回真实数据
- [ ] `growth.store.fetchGlobalTrends()` → 后端 `growth:getGlobalTrends` handler → 返回真实数据
- [ ] `prescription.store.fetchAllStages()` → 依赖 `developmentPathService`（已打通）
- [ ] 各 Store 有时间粒度的 loading/error 状态管理
- [ ] 空数据时显示合理空状态而非永远 loading

**涉及文件**: `src/renderer/stores/ability.store.ts`, `src/renderer/stores/growth.store.ts`, `src/renderer/stores/retro.store.ts`

**预估**: 约 150 行改动

---

### C-4: 硬编码映射表外置化 (R-014 合规)

**问题**: 19 处 Pxxx 映射表、状态映射、维度映射写死在 TypeScript 代码中，违反 R-014 配置外置规范。

**首批目标（5 处关键映射）**:
- [ ] `SYNDROME_TO_TASKS_MAP` → `resources/01-diagnosis/syndromes/` JSON 文件
- [ ] `SYNDROME_NAME_MAP` → `resources/01-diagnosis/syndromes/` JSON 文件
- [ ] `SYNDROME_TO_DIMENSION` → `resources/01-diagnosis/syndromes/` JSON 文件
- [ ] `STATUS_MAP` (ProjectSpacePage) → `resources/config/` JSON 文件
- [ ] `ATTITUDE_OPTIONS` (SettingsPage) → `resources/config/` JSON 文件

**涉及文件**: 多个（见评估报告 §2.1）

**预估**: 约 200 行改动（含 JSON 创建 + 加载器）

---

### C-5: 训练流 UI 入口激活

**问题**: `FlowPanel` 组件完整可用但无 UI 入口，用户无法主动触发训练流程。

**DoD**:
- [ ] 在 ChatPage 底部或侧边栏添加"开始训练"按钮
- [ ] 点击后调用 `activeTrainingService` 创建训练
- [ ] 成功创建后打开 FlowPanel 展示 5 步训练流
- [ ] 训练完成后回到正常聊天状态

**涉及文件**: `src/renderer/pages/ChatPage.tsx`, `src/renderer/components/training/`

**预估**: 约 100 行改动

---

## 优先级排序

```
P0 ─ C-1 (Chat 事件响应) ─ 核心交互断头路
 │
 ├─ C-2 (项目空间 Mock) ─ 用户第一眼印象
 │
 ├─ C-3 (4 子页数据) ─ 次要页面内容
 │
 ├─ C-5 (训练入口) ─ 功能可用性
 │
 └─ C-4 (硬编码外置) ─ 代码质量
```

## 门禁

- typecheck: 0 error
- test: 全绿（新增测试覆盖）
- lint: 0 warning（新增代码必须合规）
