// ─────────────────────────────────────────────────────────────
// app_theme_contrast_test — 文字令牌对比度护栏（批次99b）
//
// 背景：用户反馈「部分系统字体与背景色差不足、可读性差」。
// 已查证：textTertiary（#858B92）对背景 #F7F8F6 仅 3.23:1，
// caption/microCaption/subCaption 等 11-13px 小号文字不达 WCAG AA
// 正文标准（4.5:1）。批次99b 加深 textSecondary / textTertiary /
// textDeep / primaryDeep。
//
// 本护栏锁定：核心文字令牌在主要背景上全部 ≥4.5:1（AA），
// 且三级文字层级（primary > secondary > tertiary）不塌陷。
// 任何后续调色导致色差回退都会在此红。
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/main.dart' show buildAppTheme, buildDarkTheme;

/// WCAG 相对亮度（0-1）
double _relativeLuminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

/// WCAG 对比度（1-21）
double _contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AppColors 文字令牌对比度（批次99b 护栏）', () {
    // 主要背景：白底 / 页面背景 / 卡片 / 米纸（写作编辑器）
    const backgrounds = [
      Color(0xFFFFFFFF), // surfaceWhite
      Color(0xFFF7F8F6), // background
      Color(0xFFF2F4F2), // surface
      Color(0xFFF5F1E8), // paper
    ];

    // 正文/说明文字必须全场景 ≥4.5:1（WCAG AA 正文标准）
    const bodyTokens = [
      ('textPrimary', AppColors.textPrimary),
      ('textInk', AppColors.textInk),
      ('textBody', AppColors.textBody),
      ('textSecondary', AppColors.textSecondary),
      ('textTertiary', AppColors.textTertiary),
      ('textDeep', AppColors.textDeep),
    ];

    for (final (name, color) in bodyTokens) {
      for (final (i, bg) in backgrounds.indexed) {
        final ratio = _contrastRatio(color, bg);
        test(
          '$name 对背景#${bg.toARGB32().toRadixString(16).substring(2)} ≥4.5:1（实际 ${ratio.toStringAsFixed(2)}:1）',
          () {
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$name 在背景#${bg.toARGB32().toRadixString(16).substring(2)} '
                  '上对比度 ${ratio.toStringAsFixed(2)}:1 < 4.5:1，不达 WCAG AA 正文标准',
            );
          },
        );
      }
    }

    // 三级文字层级：primary > secondary > tertiary（对比度降序，层级不塌陷）
    test('文字层级：textPrimary > textSecondary > textTertiary（白底对比度）', () {
      const white = Color(0xFFFFFFFF);
      final p = _contrastRatio(AppColors.textPrimary, white);
      final s = _contrastRatio(AppColors.textSecondary, white);
      final t = _contrastRatio(AppColors.textTertiary, white);
      expect(
        p,
        greaterThan(s),
        reason:
            'primary(${p.toStringAsFixed(2)}) 应深于 secondary(${s.toStringAsFixed(2)})',
      );
      expect(
        s,
        greaterThan(t),
        reason:
            'secondary(${s.toStringAsFixed(2)}) 应深于 tertiary(${t.toStringAsFixed(2)})',
      );
      // 相邻层级至少拉开 0.5 对比度点，避免同屏糊成一团
      expect(s - t, greaterThan(0.5), reason: 'secondary 与 tertiary 层级差不足');
    });

    // 暗夜编辑色（editorDark* 对 #26282B 基底）保持既有 AA 承诺
    test('暗夜编辑色对 #26282B 基底 ≥4.5:1', () {
      const darkPanel = Color(0xFF26282B);
      final text = _contrastRatio(AppColors.editorDarkText, darkPanel);
      final muted = _contrastRatio(AppColors.editorDarkMuted, darkPanel);
      expect(text, greaterThanOrEqualTo(4.5));
      expect(muted, greaterThanOrEqualTo(4.5));
    });

    // 真机反馈第三批#3（2026-09-11）：书架排序菜单深底深字对比度≈0。
    // 根因：buildDarkTheme 钉了 surface 漏修 M3 PopupMenu 读的 surfaceContainer。
    // 本护栏锁死两主题 popupMenu 必须钉 surfaceWhite 底 + textPrimary 字，防回退。
    group('PopupMenu 浮层钉白底深字（真机三批#3 护栏）', () {
      final themes = [('亮主题', buildAppTheme()), ('暗主题', buildDarkTheme())];

      for (final (name, theme) in themes) {
        test('$name popupMenu 底=surfaceWhite、字=textPrimary', () {
          final pm = theme.popupMenuTheme;
          expect(
            pm.color,
            AppColors.surfaceWhite,
            reason: 'popupMenu 底色必须钉 surfaceWhite，防 M3 surfaceContainer 漂移',
          );
          expect(
            pm.textStyle?.color,
            AppColors.textPrimary,
            reason: 'popupMenu 文字必须钉 textPrimary',
          );
        });

        test('$name popupMenu 底×字对比度 ≥4.5:1', () {
          final bg = theme.popupMenuTheme.color!;
          final fg = theme.popupMenuTheme.textStyle!.color!;
          final ratio = _contrastRatio(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'popupMenu 文字 ${fg.toARGB32().toRadixString(16)} 对底色 '
                '${bg.toARGB32().toRadixString(16)} 仅 ${ratio.toStringAsFixed(2)}:1 < 4.5:1',
          );
        });
      }
    });
  });
}
