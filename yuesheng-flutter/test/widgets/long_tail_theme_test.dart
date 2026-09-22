// ─────────────────────────────────────────────────────────────
// P1-5 长尾批 主题成对断言 + R4 源码钉（2026-09-21）
//
// 三件事，各自钉住本批的一种**新机制**（不是重复既有渲染色断言）：
//   ① `AbilityProgressChart` 的 `_CurvePainter` —— paint 拿不到 BuildContext，
//      正解是**构造注入**；断言**读注入字段**（skill 要求的形态），不只测渲染色。
//   ② `PunctuationBar` —— 私有方法补 `BuildContext` 形参后，图标色随主题翻。
//   ③ ★ **R4 源码钉**：写作页 AppBar 前景**刻意**保留静态 `AppColors.*`（编辑器不随全局翻暗）。
//      配对守卫本体在 `.ai/`（不进公仓、CI 看不见）⇒ 本条是这条不变式在**门禁可见面**里
//      唯一的机器执行点，防下一批的机械迁移脚本把它「顺手」翻回去。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/services/growth_service.dart' show AbilityScore;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/types/display_types.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/ability_progress_chart.dart';
import 'package:writingcoach/widgets/punctuation_bar.dart';

/// 只剥 `//` 行注释（本钉够用；源码对账不涉字符串内的 `//`）。
String _stripLineComments(String s) => s
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

/// 按 runtimeType 字符串取私有 painter（私有类型在测试里不可引用）。
dynamic _painterOf(WidgetTester t) {
  final cps = t.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(AbilityProgressChart),
      matching: find.byType(CustomPaint),
    ),
  );
  return cps
      .map((c) => c.painter)
      .firstWhere(
        (p) => p != null && p.runtimeType.toString() == '_CurvePainter',
      );
}

List<EvaluationData> _twoPointHistory() => [
  EvaluationData(
    round: 1,
    trend: EvaluationTrend.stable,
    trainingCount: 0,
    passRate: 0.5,
    summaryText: 's1',
    syndromeDetails: const [],
    abilityScores: const [
      AbilityScore(
        dimension: '情节构建',
        score: 60,
        trend: Trend.stable,
        description: 'd',
      ),
    ],
    generatedAt: 1000,
  ),
  EvaluationData(
    round: 2,
    trend: EvaluationTrend.improving,
    trainingCount: 2,
    passRate: 0.8,
    summaryText: 's2',
    syndromeDetails: const [],
    abilityScores: const [
      AbilityScore(
        dimension: '情节构建',
        score: 75,
        trend: Trend.improving,
        description: 'd',
      ),
    ],
    generatedAt: 2000,
  ),
];

void main() {
  group('① _CurvePainter 网格色由 build 注入（painter 不直读令牌）', () {
    Future<void> pump(WidgetTester t, ThemeData theme) async {
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: AbilityProgressChart(history: _twoPointHistory()),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('亮色：注入的 gridColor == AppColors.borderSoft', (t) async {
      await pump(t, buildAppTheme());
      expect(
        _painterOf(t).gridColor,
        AppColors.borderSoft,
        reason: '亮色下必须与静态令牌同值 ⇒ 证亮色零变化',
      );
    });

    testWidgets('暗色：注入的 gridColor == dark.borderSoft 且 != 亮色', (t) async {
      await pump(t, buildDarkTheme());
      expect(_painterOf(t).gridColor, AppPalette.dark.borderSoft);
      expect(_painterOf(t).gridColor, isNot(AppColors.borderSoft));
    });
  });

  group('② PunctuationBar 常驻操作项图标色成对（补 BuildContext 形参）', () {
    Future<void> pump(WidgetTester t, ThemeData theme) async {
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 900,
                child: PunctuationBar(
                  onTap: (_) {},
                  onUndo: () {},
                  onRedo: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    Color _undoIcon(WidgetTester t) =>
        t.widget<Icon>(find.byIcon(Icons.undo).first).color!;

    testWidgets('亮色：撤销图标 == AppColors.textTertiary', (t) async {
      await pump(t, buildAppTheme());
      expect(_undoIcon(t), AppColors.textTertiary);
    });

    testWidgets('暗色：撤销图标 == dark.textTertiary 且 != 亮色', (t) async {
      await pump(t, buildDarkTheme());
      expect(_undoIcon(t), AppPalette.dark.textTertiary);
      expect(_undoIcon(t), isNot(AppColors.textTertiary));
    });
  });

  group('③ ★ R4 源码钉：写作页 AppBar 前景刻意不随全局主题翻', () {
    const src = 'lib/widgets/writing/view/writing_page_scaffold.dart';

    test('文件在（防路径漂移导致断言静默空跑）', () {
      expect(File(src).existsSync(), isTrue, reason: '路径漂移 ⇒ 本钉失效，先修路径');
    });

    test('_buildAppBar 内仍取静态 AppColors，且带 R4 注因', () {
      final body = File(src).readAsStringSync().replaceAll('\r\n', '\n');
      final i = body.indexOf('PreferredSizeWidget _buildAppBar');
      expect(i, greaterThan(0), reason: '函数改名/删除 ⇒ 本钉须同步，不得静默通过');
      final fn = body.substring(i, body.indexOf('\n  }', i) + 4);
      // ★ 判据只取**代码**：注释里会解释「为什么不能用 context.palette」，
      //   拿原文做反向断言会被自家注释误伤（本钉初版正是这么假失败的）。
      final code = _stripLineComments(fn);

      expect(
        code,
        contains('AppColors.textPrimary'),
        reason: 'R4：编辑器保持米纸底 ⇒ 前景必须留在静态令牌上（全局暗时亮字压亮底）',
      );
      expect(code, contains('AppColors.editorDarkText'));
      expect(fn, contains('R4'), reason: '注因必须在场，否则下批无从判断这是刻意而非漏迁');
      // ★ 反向钉：该函数**代码**内不得出现运行期前景取色（机械脚本顺手迁回这里 = 红）
      expect(
        code.contains('context.palette.textPrimary') ||
            code.contains('context.palette.textSecondary'),
        isFalse,
        reason: '该处一旦吃 context.palette，「全局暗 + 米纸编辑器」下即不可读',
      );
    });
  });
}
