# Changelog

> 月笙写作教练变更日志。版本号遵循语义化版本（semver）。

## [1.5.0] - 2026-06-25

### 移动端 V1 — 前端重构

#### Added
- **PageStackRouter**: 轻量页面栈路由（Context + Zustand），支持 push/pop/navigateToTab，子页面隐藏 TabBar
- **TabBar 3 tab**: 书架 | 对话 | 应用（Lucide 图标 + 激活指示器）
- **BookshelfPage**: 书卡列表（渐变色封面 46×60px + 书名 + 元数据 + 成长指示点）+ 虚线新建按钮
- **ProjectSpacePage**: 项目空间（诊断/训练/学习天数统计 + SVG 雷达图五维能力 + CTA + 最近记录 + 章节列表）
- **ChatPage**: 教学对话（欢迎引导区含月头像 + 用户/诊断/思考中三种气泡 + 诊断分析标签 + 工具条输入栏）
- **ConversationsPage**: 对话列表（标题/摘要/时间/作品关联 + 空状态引导）
- **AppsPage**: 应用中心（4×4 图标网格 + 工具列表）
- **page-stack.store**: Zustand store 管理页面栈状态，RootTab 类型约束

#### Changed
- **variables.css V3.0**: 金棕暖灰 → 暖紫柔棕体系（主色 `#8A7A9E`，功能色教学 `#7A93AC`/练习 `#B8956E`/成长 `#7BA089`）
- **App.tsx**: 替换 AppShell 为 PageStackRouter，保留全部 IPC 订阅
- 圆角体系对齐设计稿（sm: 8px / md: 12px / lg: 16px / xl: 20px）
- 阴影色相从暖棕 → 暖紫调

#### Architecture
- 375px 移动端优先容器（maxWidth: 430, margin: 0 auto, 100dvh）
- 现有桌面端三栏布局（AppShell/CenterPanel/RightPanel）保留未改动
- 后端 IPC 订阅、Store、Service 层零改动

## [1.4.0] - 2026-06-23

### Sprint 17 三期 — Catalog 修复 + ToolGrid 重构 + 硬编码清理 + 审计 14/20

#### Fixed
- **Catalog IPC 包裹层**: `createHandler` 把 handler 返回值包装为 `{ success: true, data: ... }`，CatalogWorkspace 和 useStartTraining 直读 `res.groups` 导致始终为空（回归自 S16）
- **Catalog CSS 类名失配**: 组件用 14 个 CSS 类名在 css 文件中不存在（`wrapper`/`catalogGrid`/`coreGroupCard`/`techCard` 等），核心组网格和技法卡片全部裸奔
- **ToolGrid 图标**: 文本字符 `✤ ◐ ✎ ☰ ⚙ ◈` → lucide-react（BookOpen/BarChart3/FileText 等）
- **~80 硬编码 hex → CSS design tokens**: 18 个文件，核心组网格/技法卡片/进度面板 统一 token 化
- **SubTabs/ToolTabs emoji → lucide + aria-label**: 剩余 emoji 清理
- **--transition-bounce 移除**: 全局移除不合理的 bounce 动效
- **RightPanel header onWheel**: passive listener preventDefault 警告修复（改用 addEventListener + passive: false）

#### Changed
- **ToolGrid**: 重做为方格标签布局（圆形 icon 容器 + 描述文案 + hover 上浮）
- **Catalog 技法卡片**: 左侧 3px accent 边框卡片 + hover 左移
- **Catalog 核心组网格**: 2 列居中卡片 + hover 上浮
- **WelcomeCard / ChatView / Recommendations emoji → lucide**: 剩余批次清理

#### Chore
- **README**: 全面重写（项目概览 / 架构图 / 路线图 / 已知债务）
- **PRODUCT.md**: 产品战略定义（register / user / purpose / anti-references / design principles）
- **二次审计 v3**: 14.5/20 Good（目标 ≥14/20 达成），v1→v3 +3.5

## [1.3.0] - 2026-06-23

### Sprint 17 — Tailwind 迁移 + 二次审计 (2026-06-23)

#### Added
- **T17-13 二次审计** `dev-docs/audits/2026-06-23-frontend-audit-v2.md`：13/20 (Good)，+2 分
- **PRODUCT.md**：完整产品战略定义（register / user / purpose / anti-references / design principles）

#### Changed
- **T17-12 Tailwind → CSS Modules (4 批, 12 文件, ~103 处)**：
  - **B1**：Card / EmptyState / TypingIndicator / AppConfigGate（4 文件 12 处）
  - **B2**：BeatCheckChart / SelfCheckList / GrowthCard（3 文件 20 处）
  - **B3**：EvaluationCard / EditPanel / OriginalEvidenceSection（3 文件 29 处）
  - **B4**：OnboardingFlow / DiagnosisCard（2 文件 41 处）
  - 全量使用 design tokens（`var(--bg-*)` / `var(--text-*)` / `var(--space-*)`）

#### Chore
- **packages**：Tailwind 配置保留 1 sprint 观察期，包暂未移除

## [1.2.0] - 2026-06-23

### Sprint 17 — 前端审计整改 + Sprint 16 验收闭环 (2026-06-23)

#### Added
- **训练流 CSS Module** `src/renderer/components/training/flow/flow.module.css`（180 行）：覆盖 FiveStepFlow + FlowStepIndicator + 5 步面板样式，design tokens + 金棕暖灰 + WCAG AA + reduced-motion
- **CenterPanel selectors** `selectors.ts`：5 个独立 selector 替代全 store 订阅，useShallow 保证聚合字段引用稳定性
- **selector 单元测试** `__tests__/selectors.test.ts`：11 个用例覆盖引用稳定性
- **FiveStepFlow 启用 4 个 skip 测试**：引入 @testing-library/user-event v14.6.1，覆盖核心禁用逻辑

#### Changed
- **CenterPanel** 改用新 selectors：actions 走 getState()，高频/低频字段解耦
- **AppShell 收起栏** 6 个 emoji 按钮 → lucide-react 图标（Plus / Settings / Maximize2 / Minus / Square / X）
- **CenterPanel empty state** 3 个 emoji → lucide-react 图标（PenLine / Sprout / MessageCircle）
- **AppShell 拖拽**：mousemove 改用 requestAnimationFrame 节流，避免布局抖动
- **AppShell borderLeft**：硬编码 #D6CEC0 → var(--border) token

#### Performance
- **CenterPanel 训练流 stream**：ChatView / RetroSummaryView 不再因 CenterPanel 重渲染被波及
- **AppShell 拖拽节流**：每帧只 commit 一次到 React state

## [1.1.0] - 2026-06-23

### Sprint 16 — 五步通用训练流贯通 (2026-06-22)

#### Added
- **训练流映射配置** `resources/config/training-flow-mapping.json`：6 类挑战 → 5 步流程模板
- **训练流加载器** `src/renderer/flow/training.flow.ts`：根据 challengeId 查 mapping，返回 5 步内容
- **五步训练流 UI**：
  - `FiveStepFlow` 主容器 + 进度条 + 导航
  - 5 个步骤面板：`StepExplain` / `StepExample` / `StepConfirm` / `StepTry` / `StepFeedback`
  - 步进指示器 `FlowStepIndicator`
- **填模板工具** `fillTechniqueTemplate()`：从 `technique-library.json` 动态取数据替换占位符
- **复制 resources 脚本** `scripts/copy-resources.cjs`：解决 tsc 后 dist/resources/ 缺失
- **22 个单元测试**（loader 13 + UI 3 + orchestrator 3 + 其他 3）

#### Changed
- **技法消费层过滤**：diagnosis-orchestrator 现在按 `activeSyndromeIds` 过滤技法池（BL-02）
- **训练流类型扩展** `types-training.ts`：新增 `flowType: 'flow5' | 'legacy'`
- **ActiveTrainingView** 支持 `flowType` 分支：5 步流 vs 旧 3 步流并存
- **workspaces-index.ts** 修正 import 路径：原本错误的 `./registry/...` → 正确的 `../components/right/workspaces/...`
- **RightPanel** 加 mount-once useEffect：补齐 `defaultOpen` 同步

#### Fixed
- **preload 白名单缺失** `src/preload/index.ts`：补回 4 个频道（`prescription:getAllStages` / `prescription:getStageProgress` / `prescription:getStageById` / `training:generateFlow`），原"Disallowed IPC channel" 错误
- **goNext 闭包陷阱**：`useState` 函数式 set 修复
- **业务字段名错**：`trainingFlow.content` → `trainingFlow.instruction`
- **setUserDraft 命名错**：`setUserDraft` → `updateDraft`
- **评估/submit UI 阻塞**：用 `queueMicrotask` 包裹不阻塞切换

#### Tech Debt (Sprint 17+ 候选)
- **BL-22: better-sqlite3 双版本** — npm rebuild 单一目标，dev/electron 二选一，配置缺失
- **BL-23: preload 共享白名单** — 硬编码与 `shared/constants.ts` 同步靠人
- **BL-19: 7 个 stub workspace 待实组件化**（Sprint 18 排期）

#### 门禁
- typecheck: 0 errors
- test: 42 files, 629 passed (4 skipped, Sprint 19 补)
- lint: 0 errors, 253 warnings (pre-existing)
