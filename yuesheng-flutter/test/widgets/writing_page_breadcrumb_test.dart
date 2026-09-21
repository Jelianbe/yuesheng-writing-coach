// ─────────────────────────────────────────────────────────────
// writing_page_breadcrumb_test — D1-b / R5 回归钉（2026-09-21）
//
// 缺陷实录（真机像素采样，`.ai/reports/2026-09-21-模拟器暗色全量验收.md §4-R5`）：
// 「未分卷」分支传 `color: null` ⇒ `TextStyle.color` 缺省 ⇒ 文字**继承 AppBar
// 主题前景色**。主题切暗后该默认色 = `AppPalette.dark.textPrimary` = `#E8EAED`，
// 而 AppBar 底色被 `darkUi` 三元锁死为亮色 `AppColors.background` = `#F7F8F6`
// ⇒ **实测对比度 1.13:1**（同栏返回箭头用同一个宿主前景色 = 12.10:1）。
//
// 四条判据（①–③ 正向、④ 负向对照；缺 ④ 则 ③ 无法证明有鉴别力）：
//   ① 亮色主题：未分卷分支文本色 == 宿主 color
//   ② 暗色主题：未分卷分支文本色**仍** == 宿主 color（不回落主题前景色）
//   ③ 该配对（宿主 color × AppBar 实际底色）对比度 ≥ 4.5:1（WCAG AA）
//   ④ 负向对照：暗主题默认前景色对同底色 < 4.5:1 —— 即「回落」这条路本身不达标
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/widgets/writing/view/writing_page_breadcrumb.dart';

/// WCAG 相对亮度（0-1）—— 与 `test/config/app_theme_contrast_test.dart` 同式。
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
  final flattened = fg.a >= 1.0 ? fg : Color.alphaBlend(fg, bg);
  final l1 = _relativeLuminance(flattened);
  final l2 = _relativeLuminance(bg);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  /// 宿主下发的文字色 —— 对齐 `writing_page_scaffold.dart:196`：
  /// 非暗夜编辑器预设（默认纸底）⇒ `fg = AppColors.textPrimary`。
  const hostColor = AppColors.textPrimary;

  /// 写作页 AppBar 的**实际**底色 —— 对齐 `writing_page_app_bar.dart:52-54`
  /// 的 `darkUi ? editorDarkSurface : AppColors.background`；默认纸底 ⇒ 亮色。
  const appBarBg = AppColors.background;

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: AppBar(
              backgroundColor: appBarBg,
              title: const WritingPageBreadcrumb(
                title: '第一章',
                volumeId: null, // ← 未分卷：R5 缺陷分支
                manuscriptId: null,
                color: hostColor,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Color textColor(WidgetTester t) =>
      t.widget<Text>(find.text('第一章')).style!.color!;

  testWidgets('① 亮色：未分卷分支文本色 == 宿主 color', (t) async {
    await pump(t, buildAppTheme());
    expect(textColor(t), hostColor);
  });

  testWidgets('② 暗色：未分卷分支文本色仍 == 宿主 color（不回落主题前景色）', (t) async {
    await pump(t, buildDarkTheme());
    expect(textColor(t), hostColor);
    // 反向锁：防「又变回继承」——继承到的是暗主题前景色
    expect(textColor(t), isNot(AppPalette.dark.textPrimary));
  });

  testWidgets('③ 对比度：宿主 color × AppBar 底色 ≥ 4.5:1', (t) async {
    await pump(t, buildDarkTheme());
    expect(_contrastRatio(textColor(t), appBarBg), greaterThanOrEqualTo(4.5));
  });

  testWidgets('④ 负向对照：暗主题默认前景色 × 同底色 < 4.5:1（证明 ③ 有鉴别力）', (t) async {
    expect(
      _contrastRatio(AppPalette.dark.textPrimary, appBarBg),
      lessThan(4.5),
    );
  });
}
