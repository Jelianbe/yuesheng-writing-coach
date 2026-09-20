// ─────────────────────────────────────────────────────────────
// theme/app_theme — 主题构建（token-first · 参数化 · 可复用）
//
// 核心设计（2026-09-20 主题架构重构，取代旧 main.dart 里写死 light/dark 两分支）：
//   buildTheme(palette) —— **一套构建逻辑，喂不同 AppPalette 出不同主题**。
//   加第三套配色 = 写一个 AppPalette + 注册表加一行，**这里与所有 widget 都不动**。
//   这就是舰长要的「模块化、可复用、为更多主题做准备」。
//
// componentThemes(palette) —— 把按钮 / 卡片 / 弹窗 / 底部面板 / 输入框 / chip / tab /
//   snackbar / appbar / 底部导航 全套 Material 组件默认色**集中**从 palette 派生。
//   这一层是「换主题不用逐处改 widget」的关键杠杆：凡走 Material 主题机制的组件自动翻色。
//   （自定义 widget 仍直读 AppColors 的部分，由 P1 迁移 + 裸色守卫逐批收敛，见
//    reports/2026-09-20-主题配色架构设计提案.md）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../config/app_motion.dart';
import '../config/app_palette.dart';
import '../config/app_theme.dart';
import 'app_typography.dart';

/// 页面转场（各主题共用）。
const PageTransitionsTheme _kPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: YueFadeSlidePageTransitionsBuilder(),
    TargetPlatform.fuchsia: YueFadeSlidePageTransitionsBuilder(),
    TargetPlatform.linux: YueFadeSlidePageTransitionsBuilder(),
    TargetPlatform.windows: YueFadeSlidePageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  },
);

/// 构建一份 ThemeData（亮 / 暗 / 未来任意主题都走这里）。
///
/// 组件级默认色（popupMenu / appBar / card / dialog / bottomSheet / navigationBar /
/// 输入框 / 文字）全部从 [p] 派生 —— 这是「换主题不逐处改 widget」的杠杆层。
/// 自定义 widget 直读 AppColors 的部分不在此列（P1 迁移 + 裸色守卫收敛）。
ThemeData buildTheme(AppPalette p, Brightness brightness) {
  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      surface: p.surfaceWhite,
      onSurface: p.textPrimary,
      error: p.danger,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: p.background,
    // ── 组件主题：全部从 palette 派生 ──
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceWhite,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: p.textPrimary, fontSize: 14),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: p.surfaceWhite,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceWhite,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surfaceWhite,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.background,
      indicatorColor: p.primarySoft,
    ),
    inputDecorationTheme: _inputTheme(p),
    textTheme: _textTheme(p),
    pageTransitionsTheme: _kPageTransitions,
    extensions: [p, AppTypography.from(p)],
  );
}

/// 输入框主题（R-019：从 buildTheme 提取）。
InputDecorationTheme _inputTheme(AppPalette p) => InputDecorationTheme(
  filled: true,
  fillColor: p.background,
  hintStyle: TextStyle(color: p.textTertiary),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: BorderSide(color: p.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: BorderSide(color: p.primary),
  ),
);

/// 文字主题（R-019：从 buildTheme 提取）。
TextTheme _textTheme(AppPalette p) => TextTheme(
  titleMedium: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: p.textPrimary,
  ),
  bodyMedium: TextStyle(fontSize: 15, color: p.textPrimary),
  bodySmall: TextStyle(fontSize: 13, color: p.textSecondary),
);

/// 亮色主题（等价旧 buildAppTheme，但改走参数化构建）。
ThemeData buildAppTheme() => buildTheme(AppPalette.light, Brightness.light);

/// 暗色主题（真暗色，非旧「假暗色」）。
ThemeData buildDarkTheme() => buildTheme(AppPalette.dark, Brightness.dark);
