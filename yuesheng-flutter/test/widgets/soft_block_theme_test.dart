// ─────────────────────────────────────────────────────────────
// 亮块族 F2/F3 主题成对断言（P1-2 · 暗色「半边翻」收敛批，2026-09-21）
//
// 覆盖本批四类代表性渲染点（**同一族令牌、四种载体**）：
//   · `PracticeResultIndicator` —— 底 `l1` + 前景 `primary`（顶层函数补 context 的首例）
//   · `AttitudeIndicator`       —— 圆点色来自 `_attitudeMetaFor(palette)`（**顶层 const 色表转 palette 函数**）
//   · `SettingEmptyState`       —— 图标圆底 `primarySoft`（**F2 型**：整块亮底）
//   · `PhaseUpgradeCard`        —— 庆祝圆底 + 徽标底 `primarySoft`（**F3 型**）
//
// 判据形态与轨道 A/B 既有主题测一致：**成对**（亮 = 静态令牌同值 ⇒ 证亮色零变化；
// 暗 = `AppPalette.dark.X` 且 `isNot(亮)` ⇒ 证真翻色）。只测暗色 = 恒置 dark 也能过。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/attitude_indicator.dart';
import 'package:writingcoach/widgets/phase_upgrade_card.dart';
import 'package:writingcoach/widgets/practice_result_indicator.dart';
import 'package:writingcoach/widgets/setting/setting_empty_state.dart';

/// 收集树里所有 `Container` 的 `BoxDecoration.color`（底色取证，不依赖节点顺序）。
Set<Color> _bgs(WidgetTester t) => t
    .widgetList<Container>(find.byType(Container))
    .map((w) => (w.decoration as BoxDecoration?)?.color)
    .whereType<Color>()
    .toSet();

Future<void> _pump(WidgetTester t, ThemeData theme, Widget home) async {
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: home),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  group('① PracticeResultIndicator：底 l1 × 前景 primary 成对', () {
    const hit = '达标！你掌握了这个要点';

    testWidgets('亮色：底 == AppColors.l1 且文字 == AppColors.primary', (t) async {
      await _pump(
        t,
        buildAppTheme(),
        const PracticeResultIndicator(result: TrainingResult.passed),
      );
      expect(_bgs(t), contains(AppColors.l1));
      expect(t.widget<Text>(find.text(hit)).style!.color, AppColors.primary);
    });

    testWidgets('暗色：底 == dark.l1（且 != 亮色）且文字 == dark.primary', (t) async {
      await _pump(
        t,
        buildDarkTheme(),
        const PracticeResultIndicator(result: TrainingResult.passed),
      );
      expect(_bgs(t), contains(AppPalette.dark.l1));
      expect(_bgs(t), isNot(contains(AppColors.l1)));
      expect(
        t.widget<Text>(find.text(hit)).style!.color,
        AppPalette.dark.primary,
      );
    });
  });

  group('② AttitudeIndicator：顶层 const 色表 → _attitudeMetaFor(palette)', () {
    testWidgets('亮色：圆点 == AppColors.l1Text（与迁移前逐字节同值）', (t) async {
      await _pump(
        t,
        buildAppTheme(),
        AttitudeIndicator(
          currentAttitude: AttitudeLevel.doubao,
          onSelect: (_) {},
        ),
      );
      expect(_bgs(t), contains(AppColors.l1Text));
    });

    testWidgets('暗色：圆点 == dark.l1Text 且 != 亮色（色表函数化生效）', (t) async {
      await _pump(
        t,
        buildDarkTheme(),
        AttitudeIndicator(
          currentAttitude: AttitudeLevel.doubao,
          onSelect: (_) {},
        ),
      );
      expect(_bgs(t), contains(AppPalette.dark.l1Text));
      expect(_bgs(t), isNot(contains(AppColors.l1Text)));
    });
  });

  group('③ SettingEmptyState：图标圆底 primarySoft（F2 型）', () {
    Future<void> pump(WidgetTester t, ThemeData theme) => _pump(
      t,
      theme,
      const SettingEmptyState(
        icon: Icons.auto_awesome,
        title: '还没有标签',
        description: '创建第一个标签开始整理',
      ),
    );

    testWidgets('亮色：圆底 == AppColors.primarySoft', (t) async {
      await pump(t, buildAppTheme());
      expect(_bgs(t), contains(AppColors.primarySoft));
    });

    testWidgets('暗色：圆底 == dark.primarySoft 且 != 亮色', (t) async {
      await pump(t, buildDarkTheme());
      expect(_bgs(t), contains(AppPalette.dark.primarySoft));
      expect(_bgs(t), isNot(contains(AppColors.primarySoft)));
    });
  });

  group('④ PhaseUpgradeCard：庆祝底 + 徽标底 primarySoft（F3 型）', () {
    Future<void> pump(WidgetTester t, ThemeData theme) =>
        _pump(t, theme, const PhaseUpgradeCard(from: 'P1', to: 'P2'));

    testWidgets('亮色：底集合含 AppColors.primarySoft', (t) async {
      await pump(t, buildAppTheme());
      expect(_bgs(t), contains(AppColors.primarySoft));
    });

    testWidgets('暗色：底集合含 dark.primarySoft 且不含亮色 primarySoft', (t) async {
      await pump(t, buildDarkTheme());
      expect(_bgs(t), contains(AppPalette.dark.primarySoft));
      expect(_bgs(t), isNot(contains(AppColors.primarySoft)));
    });
  });
}
