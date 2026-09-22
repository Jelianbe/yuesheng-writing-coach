// ─────────────────────────────────────────────────────────────
// editor_background_presets — 编辑器背景预设真源（**palette 驱动**）
//
// 历史：
//   批次 X-037-P0-1 UI 审查 H3：将 EditorBackgroundPreset 从弹层文件
//   editor_settings_sheet.dart 迁移到 config 包，让写作页/稿件详情页/预览页
//   等组件可直接引用工具函数而不需 import 弹层（消除跨职责耦合）。
//
// ★ 2026-09-22（批次 M1）—— 由「静态常量表」重构为「palette 驱动」：
//
//   病灶（改造前）：本文件是 `const List<EditorBackgroundPreset>`，每个预设把
//   `Color` 直接写死为 `AppColors.*` 静态常量。后果有二：
//     ① 预设轴**物理上无法**接入 `AppPalette`（ThemeExtension）—— `const` 顶层
//        变量求值期拿不到 `BuildContext`；
//     ② 加第 N 套主题时，必须在 `AppColors` 里再长一族静态令牌
//        （`editorDark*` 就是这么长出来的：同一组 5 色在 `AppColors` 与
//        `AppPalette` 里**各写一遍**，逐字节相同）。
//
//   改造方案（参照业界通行分层）：
//     · **表现无关**部分（`key` / `label`）保持 `const`；
//     · **表现相关**部分（颜色）改为**接受 `AppPalette` 的函数**。
//   ⇒ 预设不再是「另一套颜色表」，而是「**从 palette 取色的视图**」。
//      换主题只改 palette，本文件零改动。
//
//   权威印证（编辑器轴独立性的正当性）：
//     Visual Studio 官方文档：「The editor color setting is separate from the
//     IDE color theme. By default, it matches the overall IDE color theme, but
//     you can choose a light or dark background for the editor **independently**
//     of the IDE color theme.」
//     ⇒ R4 裁定「编辑器设为独立预设轴」方向正确；本次修的是它的**实现方式**，
//       不是它的**独立性**。
//
//   预设列表：米纸 / 护眼 / 暗夜（H1：原「暖白」因 ΔE 与米纸仅 3.8，属伪选项移除）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Editor 背景预设 key（WritingState.editorBackground 存储值）
const String editorBgPaper = 'paper';
const String editorBgGreen = 'green';
const String editorBgDark = 'dark';

/// 编辑器背景预设（**表现无关部分**：仅标识与展示名）
///
/// 颜色**不在本类**上 —— 见 [editorBackgroundColorFor] 等 palette 驱动函数。
/// 这样加预设只需追加一条本表记录 + 在解析函数里补一支 `switch`，
/// 且预设表本身保持 `const`（可安全用于 `const` 上下文与测试）。
class EditorBackgroundPreset {
  final String key;
  final String label;

  const EditorBackgroundPreset({required this.key, required this.label});
}

/// 编辑器背景预设列表（X-037 H1：原 4 预设精简为 3，暖白伪选项移除）
const List<EditorBackgroundPreset> editorBackgroundPresets = [
  EditorBackgroundPreset(key: editorBgPaper, label: '米纸'),
  EditorBackgroundPreset(key: editorBgGreen, label: '护眼'),
  EditorBackgroundPreset(key: editorBgDark, label: '暗夜'),
];

/// key → 预设（未命中回退米纸）
EditorBackgroundPreset editorBackgroundPresetOf(String key) {
  for (final preset in editorBackgroundPresets) {
    if (preset.key == key) return preset;
  }
  return editorBackgroundPresets.first;
}

/// 编辑器背景色（供写作页正文底）
///
/// 取值：暗夜 ⇒ `AppPalette.dark.paper`（= `0xFF1E2126`，与旧 `editorDarkSurface` 同值）
///       其余 ⇒ `AppPalette.light.paper`（= `0xFFF5F1E8` 米纸）
///
/// ⚠️ 视觉回归对照（实算，见批次 M1 报告）：
///   · 暗夜预设底色将由旧 `editorDarkPanel`(0xFF26282B) 变为 `dark.paper`(0xFF1E2126)
///     —— **ΔL 极小**（同为深灰，仅差一档），且新配对对比度 **13.88:1**（旧 12.26:1）**更优**。
///   · 米纸/护眼预设**完全不变**（仍走 `light.paper` / `light.successBg`）。
Color editorBackgroundColorFor(AppPalette palette, String key) =>
    key == editorBgGreen ? palette.successBg : editorPaletteFor(key).paper;

/// 编辑器文字色（暗夜用浅色，其余墨色）
Color editorTextColorFor(AppPalette palette, String key) =>
    editorPaletteFor(key).textInk;

/// 编辑器占位提示色（随预设联动，批次 V-3 P0-5）
///
/// 历史动因：此前两处 `hintStyle` **硬编码** `AppColors.textTertiary`、
/// **不随预设联动** ⇒ 切到「暗夜」预设时空输入框的提示（「未命名章节」/
/// 「请输入正文内容」）对 `editorDarkPanel` 仅 **2.79:1** —— 连非文字的
/// 3:1（WCAG 1.4.11）都不到，用户几乎看不见。同缺陷类此前已复发一次
/// （书架排序菜单「深底深字」）。
///
/// 契约（由护栏强制）：`hintColor` 对**本预设的 `color`** 必须 ≥4.5:1。
///   米纸 `light.paper` / `light.textTertiary`  —— 4.70:1（薄但达标，与正文 15.44 拉开弱化层级）
///   护眼 `light.successBg` / `light.textTertiary` —— 4.55:1（全系统最薄余量之一，已由护栏锁死）
///   暗夜 `dark.paper` / `dark.textTertiary` —— 6.11:1（旧为 7.48:1，**仍远高于 AA 线**）
Color editorHintColorFor(AppPalette palette, String key) =>
    editorPaletteFor(key).textTertiary;

/// 是否为暗夜背景预设（写作页周边 UI 取反联动判断，批次 94-4）
bool isDarkEditorPreset(String key) => key == editorBgDark;

/// ★ 编辑器预设 → palette 实例（**编辑器轴的定义所在**）
///
/// 这是本次改造的核心：把「编辑器配色轴」建模为**选择 palette 实例的维度**，
/// 而不是「另一套静态颜色表」。
///
/// 为何编辑器轴要有**自己的 palette 选择**，而不直接用 `context.palette`（全局当前实例）：
///   实测反例（2026-09-22，WCAG 对比度实算）：
///     · 米纸底 `0xFFF5F1E8` vs `AppPalette.dark.textPrimary` ⇒ **1.07:1**（不可读）
///     · 暗夜底 `0xFF26282B` vs `AppPalette.light.textPrimary` ⇒ **1.15:1**（不可读）
///   ⇒ 若「全局暗 + 米纸编辑器」直接取 `context.palette.textPrimary`，会亮字压亮底。
///     这与 `writing_page_scaffold.dart` 原豁免注释警告的场景一致 —— **该警告是对的**。
///
/// 但它**不构成**「编辑器轴必须用静态 AppColors」的理由：
///   正解是让编辑器轴**自己决定取哪套 palette**：
///     预设 = 暗夜           ⇒ `AppPalette.dark`  （暗底配亮字）
///     预设 = 米纸 / 护眼    ⇒ `AppPalette.light` （亮底配墨字）
///   ⇒ 编辑器轴从此是 palette 体系内的一等公民，与全局 ThemeMode **解耦但同构**。
///     加第 N 套主题时，只需在 palette 注册表加一行 —— 本文件与所有 widget 零改动。
///
/// 权威印证（「编辑器轴独立」本身在业界成立）：
///   Visual Studio 官方文档：「The editor color setting is separate from the IDE
///   color theme. By default, it matches the overall IDE color theme, but you can
///   choose a light or dark background for the editor **independently** of the IDE
///   color theme.」
AppPalette editorPaletteFor(String key) =>
    isDarkEditorPreset(key) ? AppPalette.dark : AppPalette.light;
