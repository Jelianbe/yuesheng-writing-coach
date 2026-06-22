# Sprint 9 — 前端全面审计与修复 (Plan)

> Issue #15 · 分支 `feature/sprint-9-audit-fix` · 设计文档 [sprint-9-frontend-audit-fix-plan.md](./sprint-9-frontend-audit-fix-plan.md)

## 决策总览

| 决策项 | 选择 | 理由 |
|:-------|:-----|:-----|
| 分支策略 | **feature/sprint-9-audit-fix 单分支** | 6 个 Phase 互有依赖，单一 PR review 更高效 |
| 执行顺序 | **B → C → D → E → F → G（顺序执行）** | 先低风险清理建立信心，再做架构变更 |
| ADR 数量 | **2 个**（Phase E + Phase F） | 见下表 |
| 向后兼容 | **不保留**（纯修复 Sprint，遵循 R-019） | 旧 API 同步迁移 |

## ADR 列表

| ADR | Phase | 主题 | 状态 |
|:---:|:------|:-----|:----:|
| **ADR-001** | E | AI 流式输出管道改造 | ⏳ Phase E 启动前撰写 |
| **ADR-002** | F | workspace registry 机制 | ⏳ Phase F 启动前撰写 |

## 执行顺序与门禁

### Phase B：S-01 + H 系列（高价值快赢）

**目标**：消除运行时报错 + 死代码

| 子任务 | 涉及文件 | 验证 |
|:-------|:---------|:-----|
| B-1: 删除 diagnosis.handler.ts 中 `GROWTH_GET_TRENDS` / `GROWTH_GET_GLOBAL_TRENDS` 双重注册 | `src/main/ipc/diagnosis.handler.ts` | typecheck + 启动验证 |
| B-2: 4 个孤立组件处理 | `src/renderer/components/chat/{MessageInput,InputToolbar,AttitudeIndicator,TemplateSelector}.tsx` | grep 引用 + lint |
| B-3: 删除 ChatView 死 CSS | `src/renderer/components/chat/ChatView.module.css` | typecheck + 视觉 |
| B-4: ChatView 死 props 清理 | `src/renderer/components/chat/ChatView.tsx` + `CenterPanel/index.tsx` + `App.tsx` | typecheck + 测试 |
| B-5: Footer 模式覆盖 | `src/renderer/components/center/CenterPanel/index.tsx:334` | 手动 3 模式验证 |

**DoD**：
- [ ] ipc-registry 启动无 "second handler" 报错
- [ ] `git grep` 确认 4 个孤立组件无外部引用
- [ ] ChatView 签名收敛（移除 `onSend`/`onStop`）
- [ ] Footer 仅在 `chat` 模式显示
- [ ] typecheck + test + lint 三门禁全绿

### Phase C：M 系列（基础设施小修）

| 子任务 | 涉及文件 |
|:-------|:---------|
| C-1: `stage` 工具默认显示 | `right-tools.store.ts` |
| C-2: drawer-constants 路径修正 | `right-panel.store.ts` |
| C-3: 双 AppShell 合并 | `components/AppShell.tsx` + `components/layout/AppShell.tsx` |
| C-4: 内联 Tailwind 移出 | `CenterPanel/index.tsx:230` |
| C-5: "回到目录" 功能补全 | `RightPanel/index.tsx:107,117` |
| C-6: clearSubTabs 接入 | `right-tools.store.ts:162` |
| C-7: CatalogWorkspace 关闭 sub-tab | `workspaces/CatalogWorkspace/index.tsx` |
| C-8: `training:catalog` 通道修复 | `constants.ts` + `training.handler.ts` |
| C-9: App.tsx 死状态清理 | `App.tsx:119-120` |

**DoD**：
- [ ] 9 项 M 问题全部修复或明确延期
- [ ] 启动验证无 runtime error
- [ ] typecheck + test + lint 三门禁全绿

### Phase D：L 系列（接口统一）

| 子任务 | 涉及文件 |
|:-------|:---------|
| D-1: 创建 `prescription.contract.ts` | `src/shared/api-contracts/` |
| D-2: 添加 `window:*` 通道常量 | `src/shared/constants.ts` |
| D-3: 添加 `teachingDecision:record` 通道常量 | `src/shared/constants.ts` |
| D-4: ProjectInfo 类型对齐 | `project.store.ts` + `project.contract.ts` |
| D-5: 删除/迁移 `withIdempotency` 死函数 | `renderer/utils/ipc.ts` |

**DoD**：
- [ ] api-contracts 覆盖所有 IPC_CHANNELS
- [ ] typecheck 全绿

### Phase E：AI 渲染（**ADR-001 必需**）

| 子任务 | 涉及文件 |
|:-------|:---------|
| E-1: 撰写 ADR-001 | `dev-docs/designs/adr/001-stream-pipeline.md` |
| E-2: 新建 `streamSanitizer.ts` | `src/renderer/utils/streamSanitizer.ts` |
| E-3: chat.store 接入预处理 | `src/renderer/stores/chat.store.ts` |
| E-4: appendToLastAssistant 改 immutable | `chat.store.ts` |
| E-5: MessageBubble 适配 | `MessageBubble.tsx` |
| E-6: finalContent 对账逻辑 | `App.tsx:82-89` |

**DoD**：
- [ ] AI 输出夹带 JSON 场景无乱码
- [ ] 流式输出无字符丢失
- [ ] 长输出压力测试通过
- [ ] typecheck + test + lint 三门禁全绿

### Phase F：可扩展性架构改造（**ADR-002 必需**）

| 子任务 | 涉及文件 |
|:-------|:---------|
| F-1: 撰写 ADR-002 | `dev-docs/designs/adr/002-workspace-registry.md` |
| F-2: 新建 `right-tools.registry.ts` | `src/renderer/stores/right-tools.registry.ts` |
| F-3: 迁移 7 个 workspace 到 registry | `workspaces/*` |
| F-4: RightPanel 改为 registry 调用 | `RightPanel/index.tsx` |
| F-5: ToolGrid 改造 | `ToolGrid/index.tsx` |
| F-6: 实现 React.lazy + Suspense | `RightPanel/index.tsx` |

**DoD**：
- [ ] 新增工具仅需 `registerWorkspace()` 一次
- [ ] `RightPanel/index.tsx` 不再硬编码 workspace 映射
- [ ] 启动时无 workspace 加载阻塞
- [ ] typecheck + test + lint 三门禁全绿

### Phase G：左侧栏 X-01 + Header 组件化

| 子任务 | 涉及文件 |
|:-------|:---------|
| G-1: right-panel.store 新增 `switchLeftTab` action | `right-panel.store.ts` |
| G-2: LeftPanel 改用统一入口 | `LeftPanel/index.tsx` |
| G-3: 提取 `CenterHeader` 组件 | `center/CenterPanel/CenterHeader.tsx` |
| G-4: projectBtn 接入真实项目 | `CenterHeader.tsx` + `useProjectStore` |

**DoD**：
- [ ] LeftPanel 不再直接调用 `closeTool`/`openTool`
- [ ] CenterHeader 独立可复用
- [ ] typecheck + test + lint 三门禁全绿

## 全局 DoD

- [ ] 所有 32 项问题已解决或明确延期
- [ ] AI 输出 JSON 夹带场景无乱码
- [ ] 流式输出无内容丢失
- [ ] 右侧栏添加新工具仅需注册一次
- [ ] typecheck + test + lint 三门禁全绿
- [ ] 手动验证 3 种 mode（chat/training/editor/retro）
- [ ] PR 描述包含完整的"修复内容"清单
- [ ] CHANGELOG 更新

## 风险与回退

| 风险 | 等级 | 缓解措施 |
|:-----|:-----|:---------|
| R-AI-1: 流式管道改造引入新 bug | 高 | 充分测试长输出 + 多次快速发送 |
| R-REG-1: registry 机制破坏现有依赖 | 中 | 保持 ALL_TOOLS 兼容，渐进迁移 |
| R-LEFT-1: X-01 重写影响训练模式 | 中 | 在 Phase C 之后立即验证一次 |

**回退策略**（R-006）：
- 每 Phase 完成后立即 commit，必要时可单独 revert
- Phase E/F 涉及架构变更，commit 前先运行 typecheck

## 协作节奏

- **每 Phase 开始前**：向用户简报范围
- **每 Phase 完成后**：运行三门禁 + 报告
- **每 2 个 Phase**：checkpoint 总结
- **整体完成时**：Reflect 复盘 + decision-log 更新

## 进度追踪

| Phase | 状态 | commit | 备注 |
|:------|:----:|:-------|:-----|
| B | 🔵 待开始 | - | - |
| C | ⏸ 待 Phase B 完成 | - | - |
| D | ⏸ 待 Phase C 完成 | - | - |
| E | ⏸ 待 Phase D + ADR-001 | - | 需先写 ADR |
| F | ⏸ 待 Phase D + ADR-002 | - | 需先写 ADR |
| G | ⏸ 待 Phase E/F | - | - |
