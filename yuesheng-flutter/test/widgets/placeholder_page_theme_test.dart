// ─────────────────────────────────────────────────────────────
// placeholder_page 主题成对断言（P1 轨道 A · 子批 1-B 代表性）
// 证迁移点 subtitle(context.text.body → textSecondary) 端到端随主题翻色：
//   buildAppTheme() == AppColors.textSecondary · buildDarkTheme() == AppPalette.dark.textSecondary（且 != 亮色）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/widgets/placeholder_page.dart';

void main() {
  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const PlaceholderPage(title: '成长曲线', subtitle: '待后续阶段实现'),
      ),
    );
    await t.pumpAndSettle();
  }

  Color _sub(WidgetTester t) =>
      t.widget<Text>(find.text('待后续阶段实现')).style!.color!;

  testWidgets('亮色：subtitle(body) == AppColors.textSecondary', (t) async {
    await pump(t, buildAppTheme());
    expect(_sub(t), AppColors.textSecondary);
  });

  testWidgets('暗色：subtitle(body) == AppPalette.dark.textSecondary（且 != 亮色）', (
    t,
  ) async {
    await pump(t, buildDarkTheme());
    expect(_sub(t), AppPalette.dark.textSecondary);
    expect(_sub(t), isNot(AppColors.textSecondary));
  });
}
