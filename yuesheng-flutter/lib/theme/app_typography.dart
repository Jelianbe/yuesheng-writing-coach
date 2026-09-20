// ─────────────────────────────────────────────────────────────
// app_typography — 文字档主题扩展（P1 轨道 A · 让文字色随主题翻）
//
// 背景：`AppTextStyles`（config/app_theme.dart）把 `AppColors` 文字色**焊进 static const**
// ⇒ 切暗色时文字不翻（336 处调用点的通病）。本扩展把「尺寸/字重（主题无关）+ 颜色（随主题）」
// 分开：尺寸字重沿用 AppTextStyles 的定义，颜色从 [AppPalette] 取。
//
// 用法：`context.text.body` / `context.text.titleLg` …（替代 `AppTextStyles.body`）。
// 迁移：`AppTextStyles.X` → `context.text.X`（去 const）。AppTextStyles **保留不删**
// （非 UI / 测试仍引用），迁移期两者共存，守卫只统计裸 `AppColors.` 下降。
//
// 注册：buildTheme 的 extensions 里随 AppPalette 一起挂（见 theme/app_theme.dart）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_palette.dart';

/// 文字调色板（9 档，色随主题）。字段与 [AppTextStyles] 的档**一一对应**。
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.titleLg,
    required this.titleMd,
    required this.body,
    required this.microCaption,
    required this.caption,
    required this.noteCaption,
    required this.subCaption,
    required this.subBody,
    required this.formLabel,
  });

  /// 由调色板构建（尺寸/字重固定，色取 palette）。
  factory AppTypography.from(AppPalette p) => AppTypography(
    titleLg: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: p.textPrimary,
    ),
    titleMd: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: p.textInk,
    ),
    body: TextStyle(fontSize: 14, color: p.textSecondary),
    microCaption: TextStyle(fontSize: 11, color: p.textTertiary),
    caption: TextStyle(fontSize: 12, color: p.textTertiary),
    noteCaption: TextStyle(fontSize: 12, color: p.textSecondary),
    subCaption: TextStyle(fontSize: 13, color: p.textTertiary),
    subBody: TextStyle(fontSize: 13, color: p.textSecondary),
    formLabel: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: p.textBody,
    ),
  );

  static final AppTypography light = AppTypography.from(AppPalette.light);
  static final AppTypography dark = AppTypography.from(AppPalette.dark);

  final TextStyle titleLg;
  final TextStyle titleMd;
  final TextStyle body;
  final TextStyle microCaption;
  final TextStyle caption;
  final TextStyle noteCaption;
  final TextStyle subCaption;
  final TextStyle subBody;
  final TextStyle formLabel;

  @override
  AppTypography copyWith({
    TextStyle? titleLg,
    TextStyle? titleMd,
    TextStyle? body,
    TextStyle? microCaption,
    TextStyle? caption,
    TextStyle? noteCaption,
    TextStyle? subCaption,
    TextStyle? subBody,
    TextStyle? formLabel,
  }) {
    return AppTypography(
      titleLg: titleLg ?? this.titleLg,
      titleMd: titleMd ?? this.titleMd,
      body: body ?? this.body,
      microCaption: microCaption ?? this.microCaption,
      caption: caption ?? this.caption,
      noteCaption: noteCaption ?? this.noteCaption,
      subCaption: subCaption ?? this.subCaption,
      subBody: subBody ?? this.subBody,
      formLabel: formLabel ?? this.formLabel,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      titleLg: TextStyle.lerp(titleLg, other.titleLg, t)!,
      titleMd: TextStyle.lerp(titleMd, other.titleMd, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      microCaption: TextStyle.lerp(microCaption, other.microCaption, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      noteCaption: TextStyle.lerp(noteCaption, other.noteCaption, t)!,
      subCaption: TextStyle.lerp(subCaption, other.subCaption, t)!,
      subBody: TextStyle.lerp(subBody, other.subBody, t)!,
      formLabel: TextStyle.lerp(formLabel, other.formLabel, t)!,
    );
  }
}

/// 便捷取用：`context.text.body`。缺扩展时回退 light（与 [AppPalette] 同策略，防裸测试崩）。
extension AppTypographyContext on BuildContext {
  AppTypography get text {
    final t = Theme.of(this).extension<AppTypography>();
    if (t == null) {
      if (kDebugMode) {
        debugPrint('[AppTypography] 当前 Theme 未注册 AppTypography 扩展，已回退 light。');
      }
      return AppTypography.light;
    }
    return t;
  }
}
