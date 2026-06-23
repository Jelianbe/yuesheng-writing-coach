# Frontend Audit — 2026-06-23

> **Skill**: `$impeccable audit` (v1, see `.agents/skills/impeccable/reference/audit.md`)
> **Scope**: `yuesheng-writing-coach/src/renderer/**`
> **Register**: product (per `PRODUCT.md`)
> **Auditor**: AI (impeccable skill, audit sub-command)
> **Date**: 2026-06-23
> **Status**: 🟡 Conditional Pass — 1 P0 + 6 P1 issues block WCAG AA full compliance
>
> 本报告是"代码级技术质量审计"，不是"设计 critique"。
> 只扫描可测量、可验证的代码事实，不讨论主观审美。
> 不在本报告内修复任何问题；修复由 `$impeccable <command>` 系列承接。

---

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|------:|-------------|
| 1 | Accessibility (A11y) | 2/4 | ARIA labels 部分存在；关键组件缺键盘导航与语义结构 |
| 2 | Performance | 2/4 | Zustand 全 state 订阅 + 布局属性动画导致 over-render |
| 3 | Theming | 3/4 | Token 体系完整；个别组件硬编码颜色 + 内联 style |
| 4 | Responsive Design | 2/4 | 三栏布局有断点，但缩窄到 1024px 以下右栏直接消失 |
| 5 | Anti-Patterns | 2/4 | Emoji 当 UI 元素 + Tailwind/CSS Modules 混用 + ghost-card 风险 |
| **Total** | | **11/20** | **Acceptable — significant work needed** |

**Rating**: **11/20 — Acceptable**（10–13 档）
说明：项目处于"功能可跑但债务堆积"状态，本轮 Sprint 必须清理 P0/P1 才能进入下一阶段。

---

## Anti-Patterns Verdict (先看这段)

> **Pass / Fail**: **FAIL**（轻微 AI 痕迹 + 1 处明显 codex tell）

**具体 tell**（与 PRODUCT.md 自己的 anti-references 互为镜像）：

1. ❌ **Emoji 当 UI 元素** — 与 PRODUCT.md "不要 emoji 当 UI 元素" 明确冲突
   - `AppShell/index.tsx:93–99` 收起栏按钮：`＋ ⚙ ⤢ ─ □ ✕` 6 个 unicode 字符
   - `CenterPanel/index.tsx:273, 280, 287` empty state：`📝 🌱 💬`
2. ❌ **代码型 ghost-card 风险** — 部分卡片同时使用 `border: 1px` + soft shadow
   - `globals.css:259–263 .section`：`border: 1px solid var(--border-light)` + `var(--radius-lg)` 圆角较大 → 接近 ghost-card 模式
3. ⚠️ **border-left 装饰条** — 与 `impeccable/codex.md` 红色禁令"side-stripe borders"冲突
   - `globals.css:139` blockquote 用 `border-left: 3px solid var(--accent-primary)` 作为装饰
4. ⚠️ **Tailwind 工具类 + CSS Modules 混用** — 不在 codex 黑名单，但破坏设计系统单一真源
   - `AppShell/index.tsx:83` 中间栏用 `flex-1 flex flex-col min-w-0` 4 个 Tailwind class
5. ❌ **动效叠 "bounce" 曲线** — `cubic-bezier(0.34, 1.56, 64, 1)` 弹性曲线与 PRODUCT.md "不要堆砌动效" 冲突
   - `AppShell/index.tsx:155`（虽然已从原文件删除当前用法，但 `--transition-bounce` token 仍存在）

---

## Executive Summary

- **Audit Health Score**: **11/20 (Acceptable)**
- **Issue 总数**: 1 P0 + 6 P1 + 5 P2 + 3 P3 = **15 issues**
- **Top 3 关键问题**:
  1. **FiveStepFlow 等 7 个训练流组件完全没 CSS**（P0）—— Sprint 16 交付物实际是"未上色"的 DOM
  2. **Zustand `useTrainingStore` 在 CenterPanel 一次订阅整个 state 对象**（P1）—— 训练态每变一次整个 CenterPanel 重渲染
  3. **Emoji 当 UI 元素**（P1）—— 与 PROJECT.md anti-references 直接冲突
- **建议下一步**: 先 `$impeccable shape` 重新规划 FiveStepFlow 视觉，再用 `$impeccable polish` 批量清理 emoji 和内联 style

---

## Detailed Findings by Severity

### P0 — Blocking

#### [P0] 训练流五步组件无 CSS（DOM 裸奔）

- **Location**:
  - `src/renderer/components/training/flow/FiveStepFlow.tsx`
  - `src/renderer/components/training/flow/StepExplain.tsx`
  - `src/renderer/components/training/flow/StepExample.tsx`
  - `src/renderer/components/training/flow/StepConfirm.tsx`
  - `src/renderer/components/training/flow/StepPractice.tsx`
  - `src/renderer/components/training/flow/StepFeedback.tsx`
  - `src/renderer/components/training/flow/FlowStepIndicator.tsx`
- **Category**: Theming / Anti-Pattern（也影响 A11y — 无焦点环）
- **Impact**: 用户实际看到的是垂直堆叠的裸 H2/H3/P/textarea，**没有卡片、没有进度条样式、没有 step indicator 视觉区分**。Sprint 16 交付的"五步训练流"是功能完整但视觉空白的框架。
- **WCAG/Standard**: WCAG 2.1 SC 1.4.11 (Non-text Contrast) 间接违反 —— 步骤状态 `active/completed/pending` 无视觉差异
- **Reproduction**:
  1. `npm run dev:electron`
  2. 选择任意章节 → 触发训练
  3. 观察 FiveStepFlow 区域：textarea 满宽、H2/H3 无间距、5 步骤无水平指示器
- **Recommendation**:
  - 写 `training/flow/flow.module.css` 至少 200 行
  - `.flow-step` 三态：`--active`/`--completed`/`--pending`
  - `.flow-panel` 用 `var(--bg-card) var(--border-light) var(--radius-md)` 卡片
  - `.flow-step-indicator` flex + 数字徽章 + 状态色
- **Suggested command**: `$impeccable shape training/flow` → 先定视觉规格，再写 CSS

#### [P1] Zustand store 整 state 订阅触发过度渲染

- **Location**: `src/renderer/components/center/CenterPanel/index.tsx:76–92`
- **Code**:
  ```ts
  const trainingState = useTrainingStore((s) => ({
    errorCards: s.errorCards,
    recommendations: s.recommendations,
    readingDecision: s.readingDecision,
    // ... 14 个字段一次性订阅
  }));
  ```
- **Category**: Performance
- **Impact**: training store 中任一字段变化（包括训练评估结果中间态、stream token）都会让 CenterPanel 整树重渲染。S16 训练评估走 AI stream 时，每收到一段都会触发 CenterPanel → ChatView → Footer 三处重渲染。
- **WCAG/Standard**: N/A（性能问题，但间接影响 INP）
- **Recommendation**:
  - 用 4 个独立 `useTrainingStore(s => s.xxx)` 选择器
  - 或用 `zustand/shallow` 做浅比较
  - 或拆分子 store：`useTrainingSessionStore` + `useTrainingHistoryStore`
- **Suggested command**: `$impeccable optimize CenterPanel`（或单独写 Issue）

#### [P1] Emoji 当 UI 元素（违反 PRODUCT.md）

- **Location**:
  - `src/renderer/components/AppShell/index.tsx:93–99`（收起栏 6 个按钮）
  - `src/renderer/components/center/CenterPanel/index.tsx:273, 280, 287`（empty state 3 个选项）
- **Code 片段（AppShell）**:
  ```tsx
  <button title="展开面板" onClick={handleAdd}>＋</button>
  <button title="设置" onClick={handleSettings}>⚙</button>
  <button title="展开面板" onClick={handleExpand}>⤢</button>
  <button title="最小化" ...>─</button>
  <button title="缩放" ...>□</button>
  <button title="关闭" ...>✕</button>
  ```
- **Category**: Anti-Pattern / A11y
- **Impact**:
  - 与 PRODUCT.md 明确 anti-reference 冲突
  - screen reader 会念出 emoji 名字（"plus sign", "gear"）而非按钮含义
  - Windows + Chromium 下 `⚙`（U+2699）渲染不稳定
- **WCAG/Standard**: WCAG 1.1.1 Non-text Content（emoji 不算 alt text）
- **Recommendation**:
  - 全部换为 `lucide-react` 图标（项目已用 `BookOpen/ArrowLeft/FileText/Loader/Save`）
  - 推荐 `Plus / Settings / Maximize2 / Minus / Square / X` 6 个图标
  - empty state 的 📝/🌱/💬 改用 `PenLine / Sprout / MessageCircle`
- **Suggested command**: `$impeccable polish AppShell CenterPanel`（范围明确）

#### [P1] AppShell 硬编码颜色 + 内联边框

- **Location**: `src/renderer/components/AppShell/index.tsx:119`
- **Code**:
  ```tsx
  <aside ... style={{ ..., borderLeft: collapsedRight ? 'transparent' : '1px solid #D6CEC0' }}>
  ```
- **Category**: Theming
- **Impact**:
  - `#D6CEC0` 是 `var(--border)` 的硬编码副本 —— `variables.css:39` 已有 `--border: #D6CEC0`，改动 token 时这里不会同步
  - 暗色主题切换时这条边不会跟着切换
- **WCAG/Standard**: WCAG 1.4.3 Contrast (Minimum) — 在 low-contrast 主题下可能出现不可见边框
- **Recommendation**:
  - 移除内联 `borderLeft`，改在 `AppShell/index.module.css` 用 `var(--border)`
  - 收起时 `borderLeft: none`
- **Suggested command**: `$impeccable polish AppShell`

#### [P1] AppShell 布局属性动画（flex/width/min-width）

- **Location**: `src/renderer/components/AppShell/index.tsx:26–42` + `index.module.css`
- **Impact**:
  - 拖拽时同时动画 `flex / width / min-width` 三个 layout 属性
  - `mousemove` 高频触发，layout thrashing 风险
  - 60fps 难以保证
- **Recommendation**:
  - 拖拽过程用 transform 替代 width（拖拽结束后再 setState）
  - 或加 `will-change: width` 提示 GPU
  - 非拖拽时的折叠/展开可保留 transition（事件少）
- **Suggested command**: `$impeccable animate AppShell`（注意 PRODUCT.md "不要堆砌动效" 约束）

#### [P1] Tailwind 工具类 + CSS Modules 混用

- **Location**:
  - `src/renderer/components/AppShell/index.tsx:83`
  - `src/renderer/components/center/CenterPanel/index.tsx`（隐含：依赖 `flex-1` 工具类）
- **Code**:
  ```tsx
  <main className={`flex-1 flex flex-col min-w-0 ${styles.centerPanel}`}>
  ```
- **Category**: Anti-Pattern / Theming
- **Impact**:
  - 设计系统失去单一真源
  - 新成员需要学两套语法
  - `globals.css` 已 `@tailwind base/components/utilities`，意味着产物中带 Tailwind 整个包
- **WCAG/Standard**: N/A（架构债）
- **Recommendation**:
  - 选定一个：要么全 CSS Modules，要么全 Tailwind
  - 项目体量看 CSS Modules 更合适（token 已建好）
  - 移除 `globals.css` 中 `@tailwind` 引入，清理 node_modules 中 tailwind 依赖
- **Suggested command**: `$impeccable layout AppShell`

#### [P1] FiveStepFlow 测试 4 个 skip 案例（覆盖率缺失）

- **Location**: `src/renderer/components/training/flow/__tests__/FiveStepFlow.test.tsx:104, 127, 149, 175`
- **Code**:
  ```ts
  it.skip('第 3 步（确认）短文本 < 30 字时禁用「下一步」', () => { ... });
  it.skip('第 3 步（确认）≥ 30 字时启用「下一步」', () => { ... });
  it.skip('第 4 步（尝试）空草稿时「提交评估」禁用', () => { ... });
  it.skip('第 4 步（尝试）有草稿时「提交评估」启用并切到第 5 步', () => { ... });
  ```
- **Category**: Performance（间接） / Anti-Pattern
- **Impact**:
  - 5 步流程的核心禁用逻辑（"理解 < 30 字不能进下一步"）完全没有测试覆盖
  - 注释说"留待 Sprint 19 测试基础设施加固时补"——目前是 Sprint 17 阶段，债务拖延 2 个 Sprint
- **WCAG/Standard**: N/A（测试债）
- **Recommendation**:
  - 引入 `@testing-library/user-event` 替代 `fireEvent`，解决多次 click + state flush 问题
  - 把 4 个 skip 全部启用
  - 加 1 个端到端：跑完 5 步后状态机正确
- **Suggested command**: 由 `$impeccable test` 之外的手动测试任务承接（skill 不覆盖测试编写）

---

### P2 — Minor

#### [P2] globals.css blockquote 用 border-left 装饰

- **Location**: `src/renderer/styles/globals.css:139`
- **Code**: `border-left: 3px solid var(--accent-primary);`
- **Impact**: 与 impeccable/codex.md 中 "side-stripe borders" 禁令冲突（blockquote 是文本引用，侧边条作为装饰而非结构信号）
- **Recommendation**: 改用 background tint 或 left padding + 引用符号 `❝` 字符
- **Suggested command**: `$impeccable typeset`

#### [P2] 内联 style 泛滥（7+ 文件）

- **Location**:
  - `AppShell/index.tsx:63, 114`（结构相关，可接受）
  - `editor/ChapterEditor.tsx:72–141`（全文件 70+ 内联 style）
  - `search/SearchPanel.tsx`（全文件 14 处内联）
  - `validation/ValidationResultView.tsx:39–111`（8 处）
  - `retro/RetroSummaryView.tsx:60`（1 处）
  - `center/Footer/index.tsx:67`（1 处）
- **Category**: Anti-Pattern
- **Impact**: 违反 R-019（"内联样式禁止 → CSS Modules + design tokens"）
- **Recommendation**: 逐文件迁移到 `*.module.css`，本轮 Sprint 不动（P2），下个 Sprint 排专项
- **Suggested command**: `$impeccable polish`（分文件）

#### [P2] `--transition-bounce` token 残留

- **Location**: `src/renderer/styles/variables.css:130`
- **Code**: `--transition-bounce: 400ms cubic-bezier(0.34, 1.56, 64, 1);`
- **Impact**: 弹性曲线与 PRODUCT.md "不要堆砌动效" 冲突
- **Recommendation**: 全局 Grep 是否还在用，没有则删 token
- **Suggested command**: `$impeccable quieter`

#### [P2] `.section` / `.growth-card` 接近 ghost-card

- **Location**: `src/renderer/styles/globals.css:259–263`、`:515–522`
- **Code**: 1px border + radius-lg (16px) + 没 shadow
- **Impact**: 单独 border 没 shadow 不算 ghost-card 违规，但 radius 16px 对内嵌卡片偏大
- **Recommendation**: 内嵌卡片用 `--radius-md` (10px)，顶层 hero 卡片才用 `--radius-lg`
- **Suggested command**: `$impeccable layout`

#### [P2] 测试文件名引用未来 Sprint（注释失同步）

- **Location**: `src/renderer/components/training/flow/__tests__/FiveStepFlow.test.tsx:105`
- **Code**: `// 留待 Sprint 19 测试基础设施加固时补`
- **Impact**: 文档陈旧，当前 Sprint 17
- **Recommendation**: 改注释为具体时间或关联 issue 号

---

### P3 — Polish

#### [P3] 收起栏按钮 title 属性英文化不一致

- **Location**: `AppShell/index.tsx:93–99`
- **Code**: `title="展开面板"`（中文，但项目其他 title 多数英文）
- **Impact**: 一致性问题，不影响功能

#### [P3] 训练步骤 estimatedMinutes 硬编码 fallback

- **Location**: `StepExplain.tsx:20` / `StepExample.tsx:20` / `StepConfirm.tsx:32`
- **Code**: `step?.estimatedMinutes ?? 3` / `?? 5` / `?? 3`
- **Impact**: 与 R-014 "配置外置" 弱冲突

#### [P3] 进度条 step 数无 aria-live

- **Location**: `FlowStepIndicator.tsx:20`
- **Code**: `<ol aria-label="训练进度">`
- **Impact**: 切换步骤时屏幕阅读器不会自动播报，依赖用户主动探索
- **Recommendation**: 加 `aria-live="polite"` 或 `aria-current="step"`

---

## Patterns & Systemic Issues

### Pattern 1: 组件先写后样式（设计-实现倒置）

- **证据**:
  - `training/flow/*.tsx` 7 个文件全部无 CSS
  - `FiveStepFlow.test.tsx` 4 个测试 skip
  - 注释说"留待 Sprint 19 加固"
- **原因**: Sprint 16 赶交付，先跑通逻辑再补视觉
- **系统性问题**: 测试基础设施（user-event）未跟上，无法稳定测交互，导致 e2e 逻辑也没人敢写
- **建议**: Sprint 17 起每个组件提交时强制包含 `*.module.css` + 至少 1 个非 skip 的交互测试

### Pattern 2: 硬编码与 token 混用

- **证据**:
  - `AppShell/index.tsx:119` 用 `'#D6CEC0'` 而非 `var(--border)`
  - `globals.css:54` 滚动条 thumb 重复使用 `var(--border-color)`（已用 alias，可接受）
- **系统性问题**: ESLint 缺 `no-hardcoded-colors` 规则
- **建议**: 在 `eslint.config.js` 加 `no-restricted-syntax` 匹配 `/#[0-9a-fA-F]{3,8}/` 字符串字面量

### Pattern 3: Zustand 订阅粒度过粗

- **证据**:
  - `CenterPanel/index.tsx:76–92` 一次性订阅 14 字段
  - 推测其他 CenterPanel 周边组件也有类似模式
- **建议**: 写 ADR 锁定"每次 useStore 调用最多订阅 3 个字段，超过则拆 store 或用 shallow"

---

## Positive Findings

值得保留并复用的好实践：

1. ✅ **`prefers-reduced-motion` 处理正确** — `animations.css:152-158` 用 `*` 通配符一次性降级所有动画
2. ✅ **全局焦点环** — `globals.css:61-64 :focus-visible` 用 `outline: 2px solid var(--accent-primary)`，符合 WCAG 2.4.7
3. ✅ **设计 token 体系完整** — `variables.css` 191 行，覆盖 color/typography/spacing/radius/z-index/layout
4. ✅ **CSS Modules 为主** — 80% 以上组件用 `*.module.css`，避免全局污染
5. ✅ **训练流组件结构清晰** — FiveStepFlow 容器 + 5 个独立 Step 组件，职责分离
6. ✅ **ARIA label 在关键交互** — `StepPractice` / `StepConfirm` 的 textarea 都有 `aria-label`
7. ✅ **FlowStepIndicator 用语义 `<ol>`** — 屏幕阅读器会读出"列表，5 项"
8. ✅ **保留 hover 退路** — `globals.css:209 .panel-tab:hover` 颜色加深，不依赖 hover 颜色对比
9. ✅ **reduced-motion 实际可工作** — 不是简单注释，是 `animation-duration: 0.01ms !important` 强制
10. ✅ **drag handle 在收起时正确隐藏** — `AppShell:73-80` 条件渲染

---

## Recommended Actions (按优先级)

| # | 优先级 | 命令 | 描述 |
|---|:---:|---|---|
| 1 | **P0** | `$impeccable shape training/flow` | 先定 5 步训练流的视觉规格，再写 CSS |
| 2 | **P0** | `$impeccable craft training/flow` | 实现 FiveStepFlow 配套 CSS Module，启用 4 个 skip 测试 |
| 3 | **P1** | `$impeccable polish AppShell` | 6 个 emoji 按钮 → lucide-react 图标 + 硬编码颜色 → token |
| 4 | **P1** | `$impeccable polish CenterPanel` | 3 个 emoji 选项 → lucide + Zustand 订阅拆分 |
| 5 | **P1** | `$impeccable animate AppShell` | 拖拽 layout thrash 优化 |
| 6 | **P1** | `$impeccable optimize CenterPanel` | Zustand 整 state 订阅 → 独立 selector |
| 7 | **P2** | `$impeccable typeset` | blockquote border-left 装饰 → 引用符 |
| 8 | **P2** | `$impeccable quieter` | 删 `--transition-bounce` token + 全局搜残留 |
| 9 | **P2** | `$impeccable polish` × 7 | 7 个有内联 style 的文件逐个迁移 CSS Module |
| 10 | **P3** | `$impeccable polish` | 收尾：title 字符串统一、aria-live 补充 |

**结尾必经一步**: `$impeccable polish` — 完成所有修复后跑一次，确认全维度分提升

---

## 验证清单（建议 Sprint 17 验收时一并走）

```
□ typecheck 通过
□ vitest 全绿（含启用 4 个 skip）
□ ESLint 无 hardcoded-color 警告
□ 真机启动 + 训练流程截图，确认 5 步视觉与 spec 一致
□ axe-core 自动扫描 0 critical
□ prefers-reduced-motion 开关下录屏，确认无突变
□ 1280×800 / 1024×720 两个分辨率下右栏不被截断
```

---

## 报告元数据

- **审计时长**: 1 session（扫描 + 写报告）
- **扫描组件数**: 8 关键文件
- **扫描样式文件数**: 6 全局 + 14 module
- **未审计**: 主进程 / preload / IPC（不在 frontend 范围）
- **下次审计建议**: Sprint 17 修复完成后重跑 `$impeccable audit`，目标 ≥14/20

---

> You can ask me to run these one at a time, all at once, or in any order you prefer.
>
> Re-run `$impeccable audit` after fixes to see your score improve.
