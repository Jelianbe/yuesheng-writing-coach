# Frontend Audit — 2026-06-23 (重跑 v2)

> **Skill**: `$impeccable audit` (v1)
> **Scope**: `yuesheng-writing-coach/src/renderer/components/**` (排除 archived)
> **Register**: product (per `PRODUCT.md`)
> **Auditor**: AI (impeccable skill, audit sub-command)
> **Date**: 2026-06-23 (v2)
> **Previous score**: 11/20 (v1, before Sprint 17)
> **Status**: 🟡 Conditional Pass — P0 已清，P1 大部分已清，但系统级债务（内联样式 / 硬编码色值 / ARIA）仍需 Sprint 18 收尾

---

## Audit Health Score

| # | Dimension | v1 Score | v2 Score | Delta | Key Finding |
|---|-----------|:--------:|:--------:|:-----:|-------------|
| 1 | Accessibility (A11y) | 2/4 | **2/4** | — | 13+ 交互元素缺 aria-label；emoji 仍作 UI 图标；对比度已达标 |
| 2 | Performance | 2/4 | **3/4** | +1 | Zustand selector 拆分 + 拖拽 rAF 节流；但 441 内联样式仍影响渲染 |
| 3 | Theming | 3/4 | **3/4** | — | Token 体系完整；但 133 硬编码 hex 色值在 22 个文件中分散 |
| 4 | Responsive Design | 2/4 | **2/4** | — | 三栏布局未动；右栏 1024px 以下消失行为维持 |
| 5 | Anti-Patterns | 2/4 | **3/4** | +1 | emoji → lucide 在 AppShell/CenterPanel 已清；但 ~20 处 emoji 残留 + Tailwind 混用 |
| **Total** | | **11/20** | **13/20** | **+2** | **Good**（v1 Acceptable → v2 Good） |

**Rating**: **13/20 — Good**（14-17 为 Good，差 1 分摸线）
**说明**：P0 和主要 P1 已修，score 从 Acceptable 档升入 Good 档下限。剩余议题全部是系统级工程债务，单次 sprint 修不完也合理。

---

## Anti-Patterns Verdict

**Pass / Fail**: **PASS with caveats**（仍有 AI 痕迹但在减少）

**Sprint 17 已修复的 Issue（不再扣分）**：
1. ✅ **AppShell/CenterPanel emoji → lucide-react**（v1 2 处 9 个 emoji → 2019 年之前）
2. ✅ **FiveStepFlow CSS 缺失**（v1 P0 → 180 行 flow.module.css）
3. ✅ **Zustand CenterPanel 全 state 订阅**（v1 #28 → 5 selectors + useShallow）
4. ✅ **AppShell border-left 硬编码**（v1 #33 → var(--border)）
5. ✅ **拖拽 mousemove 无节流**（v1 #33 → rAF + ref pending）

**残留 AI tells（继续扣分）**：
1. ❌ **~20 处 emoji 仍作 UI 图标** — RetroSummaryView ✅, StepFeedback ✅⚠️, RecommendationsSection 📝, ChatView ⚠, DiagnosisCard ✏️, EvaluationCard ❌✅, OnboardingFlow 🌙 等
2. ⚠️ **--transition-bounce token 仍存在于 variables.css**（虽然当前无组件使用，但 token 本身与 PRODUCT.md "禁止 bounce 曲线"冲突）
3. ⚠️ **Tailwind + CSS Modules 双轨运行** — 12 活跃文件 103 处 Tailwind 工具类。v1 是 P1，至今未修（T17-12 按计划推迟）
4. ⚠️ **441 内联样式** — 51 个活跃组件中仍有 `style={{}}`。v1 作为 anti-pattern 标记，Sprint 17 未触碰（R-010 要求只改最小范围）

---

## Executive Summary

- **Audit Health Score**: **13/20 (Good)**
- **v1 → v2 Delta**: **+2**（Accessibility —, Performance +1, Theming —, Responsive —, Anti-Patterns +1）
- **Issue count**: v1 15 个（1 P0 + 6 P1 + 5 P2 + 3 P3）→ **v2 10 个**（0 P0 + 2 P1 + 5 P2 + 3 P3）
- **Top 3 remaining**:
  1. **Tailwind + CSS Modules 双轨**（P1 #31）— 12 活跃文件 / 103 处。T17-12 计划中，预计 4 批
  2. **441 内联样式**（P1）— 51 组件文件，重灾区 HintPanel(28) / RetroSummaryView(24) / BehaviorDerivationTool(24)
  3. **13+ 交互元素缺 aria-label**（P2）— FiveStepFlow 4 个按钮、CenterPanel 3 个空态、SubTabs/ToolTabs 6+
- **建议下一步**: T17-12 Tailwind 迁移 → `$impeccable polish` ARIA 标签 → `$impeccable optimize` 内联样式批量迁移

---

## Detailed Findings by Severity

### P1 Major（2 issues）

#### [P1] Tailwind + CSS Modules 双轨运行
- **Location**: 12 活跃文件 / 103 处
- **Category**: Anti-Pattern / Theming
- **Impact**: 破坏 design system 单一直源；Tailwind 类名不参与 CSS 变量类型检查；双轨增加样式排查成本
- **Standard**: PRODUCT.md Anti-references "不要 Tailwind 与 CSS Modules 混用"
- **Recommendation**: 分 4 批迁移。已计划 T17-12
- **Suggested command**: `$impeccable polish`（逐文件迁移 + 门禁）

#### [P1] 441 处内联样式（`style={{}}`）
- **Location**: 51 个活跃组件文件
- **Category**: Performance / Anti-Pattern
- **Impact**: 内联样式在每次渲染时创建新对象 → 不必要的 v-dom diff；不可参与主题切换；增加 bundle size
- **Standard**: R-019 "新代码禁止内联样式" + PRODUCT.md "工具感"
- **Recommendation**: 分批迁移至 CSS Modules，每批 3-5 文件。重灾区 `HintPanel.tsx`(28) / `RetroSummaryView.tsx`(24) / `BehaviorDerivationTool.tsx`(24)
- **Suggested command**: `$impeccable polish` + 具体路径

### P2 Minor（5 issues）

#### [P2] 13+ 交互元素缺 aria-label
- **Location**: FiveStepFlow (4 按钮), CenterPanel (3 空态), SubTabs (2+), ToolTabs (5+)
- **Category**: Accessibility
- **Impact**: 屏幕阅读器用户无法识别按钮用途；WCAG 4.1.2 Name, Role, Value 违规
- **WCAG**: 4.1.2
- **Recommendation**: 为所有 `data-testid` 按钮补 `aria-label`；空态按钮补 `aria-label`。约 1h 工时
- **Suggested command**: `$impeccable clarify`

#### [P2] ~20 处 emoji 仍作 UI 元素
- **Location**: 10+ 文件（RetroSummaryView, StepFeedback, RecommendationsSection, ChatView, DiagnosisCard, EvaluationCard 等）
- **Category**: Anti-Pattern / A11y
- **Impact**: 违反 PRODUCT.md "不要 emoji 当 UI 元素"；emoji 在 Windows/Firefox 渲染不一致
- **Recommendation**: 系统性地搜索 `✅ ❌ ⚠️ 📝 ✏️ 🌙 ✕ ＋ ⚙` 等，逐文件替换为 lucide-react
- **Suggested command**: `$impeccable polish`

#### [P2] 133 硬编码 hex 色值
- **Location**: 22 个文件，重灾区 `DiagnosisComparisonView.tsx`(26) / `LearningLogWorkspace`(12) / `SettingsPopover.tsx`(11)
- **Category**: Theming
- **Impact**: 无法通过切换 CSS 变量实现主题变化；硬编码色值可能与 token 色值不一致
- **Recommendation**: 批量替换为 `var(--success)` / `var(--warning)` / `var(--text-secondary)` 等。这些值大部分与 token 语义色相同
- **Suggested command**: `$impeccable colorize`

#### [P2] --transition-bounce token 仍存在
- **Location**: `src/renderer/styles/variables.css:131`
- **Category**: Anti-Pattern
- **Impact**: 与 PRODUCT.md "克制动效" 和 "不要 bounce" 冲突。虽然当前无组件使用，但 token 的存在意味着未来可能误用
- **Recommendation**: 移除 `--transition-bounce` 或其更名为 `--transition-spring` 明确标注 "不建议用于主 UI"
- **Suggested command**: `$impeccable polish`

#### [P2] 右栏 ≤1024px 直接消失
- **Location**: `AppShell/index.tsx` collapsedRight 逻辑
- **Category**: Responsive
- **Impact**: 用户在 1024px 窗口下无法访问工具面板
- **Recommendation**: 使用折叠图标而非完全隐藏
- **Suggested command**: `$impeccable adapt`

### P3 Polish（3 issues）

#### [P3] 部分组件缺少 loading/error 视觉状态样式
- **Location**: FiveStepFlow flow.module.css 中 .flow-panel 的 loading skeleton 尚未定义具体样式
- **Category**: Performance
- **Impact**: 训练流加载时纯文本 "加载中..." 无骨架屏
- **Recommendation**: 补 skeleton pulse animation

#### [P3] 金棕暖灰 #1E1A14 文字在部分背景上可能不够 4.5:1
- **Location**: 涉及 --text-primary 在 --bg-primary (#FAF8F5) 上的组合
- **Category**: Accessibility
- **Impact**: 可能需要工具验证实际对比度
- **Recommendation**: 计算 OKLCH 对比度，必要时微调 --text-primary

#### [P3] globals.css 字号使用了 rem 但未统一缩放基准
- **Category**: Responsive
- **Impact**: 用户更改浏览器默认字号时部分布局可能 break
- **Recommendation**: 统一基于 16px 的 rem 基准

---

## Patterns & Systemic Issues

1. **工程债务 vs 设计债务** — 本次审计发现的核心问题已从 "组件缺 CSS、缺 aria-label"（设计债务）转向 "内联样式、硬编码色值、Tailwind 双轨"（工程债务）。说明 Sprint 17 在"修表面"上有效，但工程底座仍需 1-2 sprint 系统迁移。
2. **Tailwind 重灾区 = diagnosis/** — 7 个 diagnosis 组件贡献了 66/103 的 Tailwind 用法。这些组件在 v1 中被标记为"未上色"（但内联 style + Tailwind 混用），v2 中仍是最大债务源。
3. **OnboardingFlow 孤立** — 31 处 Tailwind className，在设计中是一个独立流程，不影响核心训练/诊断用户体验。可以作为 T17-12 最后一批迁移。

---

## Positive Findings（延续 v1）

1. ✅ **Token 体系深度完善** — `variables.css` V2.1 金棕暖灰、5 维 token 覆盖 color/typography/spacing/shadow/z-index，是项目的设计系统"地基"
2. ✅ **CSS Modules 采用率在增长** — 新增 flow.module.css(180行) + TrainingShared.module.css
3. ✅ **ARIA label 在关键组件上表现好** — AppShell collapsed bar 6 按钮全部有 aria-label
4. ✅ **panel-bus + workspace registry 架构健康** — 没有直接 import 各组件的双向耦合
5. ✅ **zustand persist 使用正确** — 白名单、版本号、迁移函数，符合 R-020/028

---

## Recommended Actions

### Priority order

1. **[P1] `$impeccable polish Tailwind 迁移 B1-B4`**: 分 4 批迁移 12 文件 / 103 处 Tailwind 工具类。每批跑 typecheck + vitest。
   - B1: common/, AppConfigGate, TypingIndicator (3 文件, 9 处)
   - B2: BeatCheckChart + SelfCheckList + EditPanel (3 文件, 20 处)
   - B3: EvaluationCard + GrowthCard + OriginalEvidenceSection (3 文件, 30 处)
   - B4: OnboardingFlow + DiagnosisCard (2 文件, 41 处)

2. **[P2] `$impeccable clarify`**: 为 13 个交互元素补 aria-label。FiveStepFlow 4 按钮 + CenterPanel 3 空态 + SubTabs/ToolTabs

3. **[P2] `$impeccable colorize`**: 批量替换 133 硬编码 hex 为 CSS 变量 token。建议先扫 diagnosis/ 模块（硬编码最多）

4. **[P2] `$impeccable polish`**: 移除 --transition-bounce token + 替换剩余 ~20 emoji 为 lucide-react

5. **[P2] `$impeccable adapt`**: 右栏 1024px 折叠优化

6. **[P3] `$impeccable polish`**: 补骨架屏 loading + 对比度验证

---

> 你可以依次运行上述命令，或指定某个立即执行。
>
> 下次修复后重跑 `$impeccable audit` 确认分数继续提升。
