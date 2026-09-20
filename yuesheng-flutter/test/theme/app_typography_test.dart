// ─────────────────────────────────────────────────────────────
// app_typography_test — 文字主题扩展（P1 轨道 A 地基）
//
// 锁死（防「两套文字真源漂移」+ 证暗色真翻）：
//   ① light 档色 == AppColors 同名（与 AppPalette 漂移护栏同纪律）
//   ② dark 档色 == AppPalette.dark 同名（暗色真翻，非焊死亮色）
//   ③ 尺寸/字重 == AppTextStyles 对应档（迁移前后观感一致，只换色不换排）
//   ④ context.text 经 buildTheme 解析到对应主题实例
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/theme/app_theme.dart' show buildTheme;
import 'package:writingcoach/theme/app_typography.dart';

void main() {
  group('light 档色 == AppColors（防漂移）', () {
    final t = AppTypography.light;
    test('文字族色对齐 AppColors', () {
      expect(t.titleLg.color, AppColors.textPrimary);
      expect(t.titleMd.color, AppColors.textInk);
      expect(t.body.color, AppColors.textSecondary);
      expect(t.caption.color, AppColors.textTertiary);
      expect(t.microCaption.color, AppColors.textTertiary);
      expect(t.noteCaption.color, AppColors.textSecondary);
      expect(t.subCaption.color, AppColors.textTertiary);
      expect(t.subBody.color, AppColors.textSecondary);
      expect(t.formLabel.color, AppColors.textBody);
    });
  });

  group('dark 档色 == AppPalette.dark（暗色真翻）', () {
    final t = AppTypography.dark;
    final d = AppPalette.dark;
    test('文字族色对齐暗色调色板（非亮色焊死）', () {
      expect(t.titleLg.color, d.textPrimary);
      expect(t.body.color, d.textSecondary);
      expect(t.caption.color, d.textTertiary);
      expect(t.formLabel.color, d.textBody);
      // 关键：暗色 textPrimary 必须 != 亮色 textPrimary（否则暗色没翻）
      expect(t.titleLg.color, isNot(AppColors.textPrimary));
    });
  });

  group('尺寸/字重 == AppTextStyles（只换色不换排）', () {
    test('各档 fontSize/fontWeight 与 AppTextStyles 一致', () {
      final pairs = <(TextStyle, TextStyle)>[
        (AppTypography.light.titleLg, AppTextStyles.titleLg),
        (AppTypography.light.titleMd, AppTextStyles.titleMd),
        (AppTypography.light.body, AppTextStyles.body),
        (AppTypography.light.microCaption, AppTextStyles.microCaption),
        (AppTypography.light.caption, AppTextStyles.caption),
        (AppTypography.light.noteCaption, AppTextStyles.noteCaption),
        (AppTypography.light.subCaption, AppTextStyles.subCaption),
        (AppTypography.light.subBody, AppTextStyles.subBody),
        (AppTypography.light.formLabel, AppTextStyles.formLabel),
      ];
      for (final (a, b) in pairs) {
        expect(a.fontSize, b.fontSize);
        expect(a.fontWeight, b.fontWeight);
      }
    });
  });

  testWidgets('context.text 经 buildTheme 解析到对应主题', (tester) async {
    late AppTypography captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppPalette.dark, Brightness.dark),
        home: Builder(
          builder: (context) {
            captured = context.text;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured.body.color, AppPalette.dark.textSecondary);
  });
}
