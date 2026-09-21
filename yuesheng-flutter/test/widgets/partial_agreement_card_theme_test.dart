// P1 轨道B 成对断言（P1-3 代表）：PartialAgreementCard 迁移色随主题翻。
// 说明文案用 context.palette.textTertiary（裸色迁移点）→ buildAppTheme==AppColors /
// buildDarkTheme==AppPalette.dark（含 != 亮色反向锁，防「永远亮/不翻」退化）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/widgets/partial_agreement_card.dart';

void main() {
  const hint = '告诉我哪些描述不准确，我会调整诊断结果。';

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: PartialAgreementCard(
            syndromeId: 's1',
            syndromeName: '叙事含糊',
            severity: 'L2',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Color _hintColor(WidgetTester t) =>
      t.widget<Text>(find.text(hint)).style!.color!;

  testWidgets('亮色：说明文案 == AppColors.textTertiary', (t) async {
    await pump(t, buildAppTheme());
    expect(_hintColor(t), AppColors.textTertiary);
  });

  testWidgets('暗色：说明文案 == AppPalette.dark.textTertiary（且 != 亮色）', (t) async {
    await pump(t, buildDarkTheme());
    expect(_hintColor(t), AppPalette.dark.textTertiary);
    expect(_hintColor(t), isNot(AppColors.textTertiary));
  });
}
