# Sprint 2 复盘 — 教学链路核心闭环

> 日期：2026-06-21
> 周期：Sprint 2（5 个 Issue）
> 看板：https://github.com/users/Jelianbe/projects/1

---

## 一、概览

### 完成情况

| Issue | 标题 | 类型 | 状态 |
|-------|------|------|:----:|
| #7 | F-01 教学/诊断区视图切换 | 功能 | ✅ |
| #6 | F-02 编辑评估全链路 | 功能 | ✅ |
| #8 | F-03 验证与复盘阶段 | 功能 | ✅ |
| #10 | Q-01 教学链路集成测试 | 质量 | ✅ |
| #9 | Q-02 错误处理与降级 | 质量 | ✅ |

**5/5 完成** — Sprint 目标全部达成。

### 数据

| 指标 | Sprint 1 末 | Sprint 2 末 | 变化 |
|------|:-----------:|:-----------:|:----:|
| 提交数 | — | 5 commits | +5 |
| 文件变更 | — | 47 files | +47 |
| 插入行数 | — | 3,332 | +3,332 |
| 删除行数 | — | 490 | -490 |
| 测试文件 | 12 | 19 | +7 |
| 测试用例 | 201 | 319 | +118 |
| Typecheck | 0 errors | 0 errors | — |
| Lint errors | 0 | 0 | — |
| Lint warnings | ~126 | ~172 | +46（含 Q-01 测试文件 !）断言）

### 架构覆盖

```
五阶段架构完成度：5/5 ✅

01-diagnosis  → ✅ [Sprint 1]
02-prescription → ✅ [Sprint 1]
03-teaching    → ✅ [Sprint 1-2]
   ├── chat/stream-handler   ✅ (Q-02 超时检测)
   ├── state-machine         ✅ (Q-02 验证降级)
   └── prompt                ✅
04-validation  → ✅ [Sprint 2/F-03]
05-retro       → ✅ [Sprint 2/F-03]
```

---

## 二、做得好的

### 1. 五阶段教学链路全线贯通
F-03（Validation + Retro）和 Q-01（集成测试）使 01→05 五阶段架构从"理论设计"变为"运行时验证"。

- ValidationResultView / RetroSummaryView 两个独立 UI 视图
- RetroService + retro IPC handler 完整域服务
- 89 个集成测试覆盖状态机/Prompt/IPC/Store 四层

### 2. 质量基础设施并行建设
Q-01 和 Q-02 在 Sprint 中期并行推进，未阻塞功能开发：

- 4 个集成测试文件（89 用例），类型含 state-machine-flow / prompt-integration / training-handler-flow / store-retro
- 错误码体系（16 个 ErrorCode，6 大分类）
- 流式 60 秒超时自动中断
- Chat store 120 秒超时 + 自动重试

### 3. 保持最小化变更原则
- 没有重构 CenterPanel 以外不相关的组件
- 错误处理只改最小链路（stream/store/view），没有波及全局
- Q-01 中清理了 `constants.js` 编译产物（精准发现 + 删除 3 个文件）

---

## 三、可改进的

### 1. GStack 流程初期切换成本
从 Sprint 1 的"直接 Build"模式切换到 GStack（Think→Plan→Build→Review→Test→Ship→Reflect）时，前两个 Issue（F-01/F-02）的 Review/Test 阶段不够严格。F-03 后改善明显。

**改进**：下个 Sprint 开始，每个 Issue 在 Ship 前必须执行完整门禁（typecheck + test + lint），且 PR 模板中标注 Review 检查项。

### 2. 跨 Issue 依赖管理
F-02 的 CenterPanel 重构在 F-01 基础上增量开发，但 F-01 合并后 F-02 的 typecheck 错误未第一时间发现（F-01 门禁通过时 F-02 分支已有偏移）。

**改进**：当多个 Issue 有文件重叠时，后一个 Issue 的 Plan 阶段应明确标注"基于前一个 Issue 的 XXX 提交"，并在开始前 rebase。

### 3. 测试覆盖仍有缺口
虽然 Q-01 大幅提升，但当前覆盖主要集中在中层（状态机/Prompt/IPC）：

| 层 | 覆盖 | 缺口 |
|:---|:----|:-----|
| 诊断域 (01) | 中 | EditPanel UI 交互未测 |
| 处方域 (02) | 低 | 技法库路由缺少测试 |
| 教学域 (03) | 高 | ✅ Q-01 已覆盖 |
| 验证域 (04) | 低 | 验证逻辑在 UI（ValidationResultView），无独立单元测试 |
| 复盘域 (05) | 中 | RetroService 有测试，但 UI 交互未测 |

---

## 四、技术债务

| 编号 | 描述 | 来源 | 优先级 |
|:----:|------|:----:|:------:|
| TD-01 | 18 个文件超 300 行上限（R-019） | 前 Sprint | P2 |
| TD-02 | ValidationResultView 无独立单元测试 | F-03 | P2 |
| TD-03 | EditPanel UI 交互未覆盖测试 | F-02 | P2 |
| TD-04 | 技法库路由（02-prescription）缺少测试 | Sprint 1 | P2 |
| TD-05 | Lint warnings 172 个（! 断言为主）| 前 Sprint | P3 |

---

## 五、决策日志（D-024）

### D-024: 五阶段架构确认定版
- **类型**: 架构决策
- **决策**: Sprint 2 完成 01-diagnosis → 05-retro 全部五阶段架构贯通，确认该架构为项目正式架构
- **原因**:
  1. 三个 Sprint 的实践证明五阶段架构稳定、可测试、可扩展
  2. 每个阶段都有独立的 domain service + IPC handler + UI 视图
  3. 错误处理（Q-02）为各阶段提供了统一的错误码基座
- **门禁标准**（记录供未来参考）:
  - 五阶段任一阶段的新增功能必须有对应的单元/集成测试
  - 跨阶段流转必须使用 IPC handler，不得直接调用其他阶段的 domain service
  - 错误信息使用 ErrorCode + ERROR_MESSAGES 中文体系

---

## 六、Sprint 3 建议

### 待办候选
1. **渲染链路** — 完成章节列表加载、自动保存、实时渲染
2. **Workspace 视图** — TrainingWorkshop UI 细化、历史回顾
3. **学生模型 Phase 2** — 持久化 + 决策引擎
4. **权限与设置** — API Key 管理、模型选择、系统配置
5. **技术债务清理** — TD-01 ~ TD-05 优先处理 P2

### 推荐的 Issue 顺序
```
渲染链路（核心功能空缺）
  → Workspace 细化（依赖渲染链路完成）
  → 学生模型 Phase 2（可并行）
  → 权限与设置（低优先级，可穿插）
  → 债务清理（每 Sprint 末安排 1 个）
```

---

*复盘人：AI 复盘官*
*2026-06-21*
