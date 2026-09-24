// ─────────────────────────────────────────────────────────────
// bookshelf_empty_state 主题成对断言（P1 轨道 A · 样板）
//
// 证「文字随主题翻」端到端接进真实 widget（令牌层映射已由 test/theme/
// app_typography_test 穷尽锁死；此处补 widget 渲染层的成对断言）：
//   · buildAppTheme() 下 → 迁移点色 == AppColors.x（亮色）
//   · buildDarkTheme()  下 → 迁移点色 == AppPalette.dark.x（暗色真翻，且 != 亮色）
// 一对多错即退化（要么没翻/要么永远暗）。样板文件：证明「脚本替换→去 const→
// context.text→pump 两主题→断言」全链在真实 widget 上跑通。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/features/bookshelf/bookshelf_empty_state.dart';

Color _colorOf(WidgetTester t, String text) =>
    t.widget<Text>(find.text(text)).style!.color!;

void main() {
  Future<void> pumpWith(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: BookshelfEmptyState(onCreate: () {})),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('书架空状态：迁移点随主题翻色', () {
    testWidgets('亮色：titleLg/body == AppColors', (tester) async {
      await pumpWith(tester, buildAppTheme());
      // titleLg → textPrimary
      expect(_colorOf(tester, '还没有作品'), AppColors.textPrimary);
      // body → textSecondary
      expect(_colorOf(tester, '点击「新建」创建你的第一部作品'), AppColors.textSecondary);
    });

    testWidgets('暗色：titleLg/body == AppPalette.dark（非亮色焊死）', (tester) async {
      await pumpWith(tester, buildDarkTheme());
      expect(_colorOf(tester, '还没有作品'), AppPalette.dark.textPrimary);
      expect(
        _colorOf(tester, '点击「新建」创建你的第一部作品'),
        AppPalette.dark.textSecondary,
      );
      // 关键反向断言：暗色下必须 != 亮色值（否则等于没翻）
      expect(_colorOf(tester, '还没有作品'), isNot(AppColors.textPrimary));
    });
  });
}
