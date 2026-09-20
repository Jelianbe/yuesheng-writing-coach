// ─────────────────────────────────────────────────────────────
// theme_registry — 主题注册表：ThemeId → (AppPalette, ThemeData)
//
// 加一套新主题 = ① 在 AppPalette 里定义该调色板 ② ThemeId 加一个枚举值
//   ③ 下面两张表各加一行。**widget 与组件主题零改动**（都经 Theme.of(context)）。
//   这是「可复用、为更多主题做准备」的落点。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import 'app_theme.dart';

/// 主题标识。`wireName` 是落 app_state 的稳定字符串（不随枚举顺序变）。
/// `brightness` 决定 Material 组件的明暗基调（状态栏/滚动条等）。
enum ThemeId {
  light('light', Brightness.light),
  dark('dark', Brightness.dark);

  const ThemeId(this.wireName, this.brightness);

  final String wireName;
  final Brightness brightness;

  /// 由存储字符串解析；未知 / 空返回 null（调用方回落默认）。
  static ThemeId? fromWire(String? w) {
    if (w == null) return null;
    for (final id in values) {
      if (id.wireName == w) return id;
    }
    return null;
  }
}

/// 主题 id → 调色板（语义色 token）。
final Map<ThemeId, AppPalette> paletteRegistry = <ThemeId, AppPalette>{
  ThemeId.light: AppPalette.light,
  ThemeId.dark: AppPalette.dark,
};

/// 主题 id → ThemeData（由调色板经参数化 buildTheme 构建）。
final Map<ThemeId, ThemeData> themeRegistry = <ThemeId, ThemeData>{
  ThemeId.light: buildTheme(AppPalette.light, Brightness.light),
  ThemeId.dark: buildTheme(AppPalette.dark, Brightness.dark),
};
