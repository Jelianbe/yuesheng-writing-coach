// ─────────────────────────────────────────────────────────────
// editor_background_presets — 编辑器背景预设真源
//
// 批次 X-037-P0-1 UI 审查 H3：将 EditorBackgroundPreset 从弹层文件
// editor_settings_sheet.dart 迁移到 config 包，让写作页/稿件详情页/预览页
// 等组件可直接引用工具函数而不需 import 弹层（消除跨职责耦合）。
// 预设色 100% 引用 AppColors 令牌，硬编码清零。
//
// 预设列表：米纸 / 护眼 / 暗夜（H1：原「暖白」因 ΔE 与米纸仅 3.8，属伪选项移除）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Editor 背景预设 key（WritingState.editorBackground 存储值）
const String editorBgPaper = 'paper';
const String editorBgGreen = 'green';
const String editorBgDark = 'dark';

/// 编辑器背景预设
class EditorBackgroundPreset {
  final String key;
  final String label;
  final Color color;

  /// 正文/标题的输入文字色
  final Color textColor;

  /// 输入框占位提示（hint）色 —— 批次 V-3（P0-5）新增。
  ///
  /// 动因：此前两处 `hintStyle` **硬编码** `AppColors.textTertiary`、**不随预设联动**
  /// ⇒ 切到「暗夜」预设时空输入框的提示（「未命名章节」/「请输入正文内容」）
  /// 对 `editorDarkPanel` 仅 **2.79:1** —— 连非文字的 3:1（WCAG 1.4.11）都不到，
  /// 用户几乎看不见。同缺陷类此前已复发一次（书架排序菜单「深底深字」）。
  ///
  /// 契约（由护栏强制）：`hintColor` 对**本预设的 `color`** 必须 ≥4.5:1。
  final Color hintColor;

  const EditorBackgroundPreset({
    required this.key,
    required this.label,
    required this.color,
    required this.textColor,
    required this.hintColor,
  });
}

/// 编辑器背景预设列表（X-037 H1：原 4 预设精简为 3，暖白伪选项移除）
const List<EditorBackgroundPreset> editorBackgroundPresets = [
  EditorBackgroundPreset(
    key: editorBgPaper,
    label: '米纸',
    color: AppColors.paper,
    textColor: AppColors.textInk,
    // 4.70:1（薄但达标 —— 与正文 15.44 保持明显弱化层级）
    hintColor: AppColors.textTertiary,
  ),
  EditorBackgroundPreset(
    key: editorBgGreen,
    label: '护眼',
    color: AppColors.successBg,
    textColor: AppColors.textInk,
    // 4.55:1（全系统最薄余量之一，已由护栏锁死）
    hintColor: AppColors.textTertiary,
  ),
  EditorBackgroundPreset(
    key: editorBgDark,
    label: '暗夜',
    color: AppColors.editorDarkPanel,
    textColor: AppColors.editorDarkText,
    // 7.48:1 —— 取 editorDarkMuted（次级文字）而非 editorDarkText（12.26）：
    // 提示是**弱化**层级，须明显弱于正文，同时远高于 AA 线。
    hintColor: AppColors.editorDarkMuted,
  ),
];

/// key → 预设（未命中回退米纸）
EditorBackgroundPreset editorBackgroundPresetOf(String key) {
  for (final preset in editorBackgroundPresets) {
    if (preset.key == key) return preset;
  }
  return editorBackgroundPresets.first;
}

/// 编辑器背景色（供写作页正文底）
Color editorBackgroundColorFor(String key) =>
    editorBackgroundPresetOf(key).color;

/// 编辑器文字色（暗夜用浅色，其余墨色）
Color editorTextColorFor(String key) => editorBackgroundPresetOf(key).textColor;

/// 编辑器占位提示色（随预设联动，批次 V-3 P0-5）
Color editorHintColorFor(String key) => editorBackgroundPresetOf(key).hintColor;

/// 是否为暗夜背景预设（写作页周边 UI 取反联动判断，批次 94-4）
bool isDarkEditorPreset(String key) => key == editorBgDark;
