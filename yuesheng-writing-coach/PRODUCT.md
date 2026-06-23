# 月笙写作教练 — PRODUCT.md

> 本文件定义产品的战略定位、用户群体、视觉原则和设计边界。
> 由 `$impeccable init` 引导编写，供后续所有 design/code 决策引用。

## Register

**product** — 设计服务于产品功能，不是展示型页面。

## Users

- **长文写作者**：小说作者、剧本写手、深度内容创作者
- **使用模式**：反复开 app，长时间沉浸式写作，非一次性访问
- **核心诉求**：获得即时的写作诊断和训练反馈，不打断创作流

## Purpose

月笙写作教练帮助长文写作者诊断文章问题、提供针对性训练、跟踪成长轨迹。核心价值是"不说空话，只给药方"——诊断精准、训练可执行、进步可感知。

## Brand Personality

**静水深流**：初看低调，相处越久越让人信住。

- 沉稳：不喧哗，不堆砌装饰
- 可信：诊断有依据，反馈有温度
- 渐进：第一次用觉得普通，第十次用离不开

## Anti-references

参考调性（不是抄袭目标，是审美对齐）：

- **Notion**：克制、内容优先、工具感
- **Obsidian**：本地优先、深度、不打扰

不要做：
- 不要 emoji 当 UI 元素
- 不要堆砌动效（bounce / 弹性曲线禁止）
- 不要 side-stripe 边框装饰
- 不要 ghost-card（border + 大 blur shadow 并存）
- 不要 Tailwind 与 CSS Modules 混用（目标：全部统一为 CSS Modules）

## Design Principles

1. **内容优先**：UI 让路给文字，不跟写作内容抢注意力
2. **低噪底色**：暖纸质美学（已定义的金棕体系），不刺眼、不疲劳
3. **渐进披露**：高级功能不堆在首屏，按需展开
4. **克制动效**：transition 只在有意义的方向（状态切换、面板展开），常态下静默

## Accessibility (A11y)

- **WCAG AA 达标**：正文对比度 ≥ 4.5:1，大文本 ≥ 3:1
- **prefers-reduced-motion** 支持：所有动效必须有静默降级
- 关键交互元素必须有 ARIA label 或 visible label
- 不支持纯键盘导航目前没要求，但语义 HTML 是基线

## Visual Identity

- 品牌色体系已在 `src/renderer/styles/variables.css` 定义（金棕暖灰 V2.1）
- 色值对齐 phase-f-shell-v6.2.html 精确值
- 字体：Noto Serif SC（展示）+ system sans-serif（正文）
- 圆角体系：6/10/16/20px 四档
- 阴影：暖调，低 contrast（基于纸质感）
