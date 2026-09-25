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
    const src = 'lib/features/writing/writing_page_scaffold.dart';

    test('文件在（防路径漂移导致断言静默空跑）', () {
      expect(File(src).existsSync(), isTrue, reason: '路径漂移 ⇒ 本钉失效，先修路径');
    });

    test('_buildAppBar 内**不**按全局主题取色，且带 R4 注因', () {
      final body = File(src).readAsStringSync().replaceAll('\r\n', '\n');
      final i = body.indexOf('PreferredSizeWidget _buildAppBar');
      expect(i, greaterThan(0), reason: '函数改名/删除 ⇒ 本钉须同步，不得静默通过');
      final fn = body.substring(i, body.indexOf('\n  }', i) + 4);
      // ★ 判据只取**代码**：注释里会解释「为什么不能用 context.palette」，
      //   拿原文做反向断言会被自家注释误伤（本钉初版正是这么假失败的）。
      final code = _stripLineComments(fn);

      // ★★ 2026-09-22（批次 M1）契约升级 —— 本钉从「钉实现」改为「钉不变式」。
      //
      // 旧判据（已作废）：`code` 必须含 `AppColors.textPrimary` / `AppColors.editorDarkText`。
      //   它钉的是**实现细节**（前景留在静态令牌上），而非**防护意图**。
      //   批次 M1 查明：该实现细节**不是唯一解**，且它带来的代价正是「编辑器轴
      //   游离于 palette 之外、加第 N 套主题要再长一族静态色」。
      //
      // 新判据（本处）钉的是**原始防护意图本身**，且**更强**：
      //   「全局主题翻暗时，编辑器前景**不得**跟着翻」
      //   —— 旧钉只能验证「没写 context.palette」，但**无法**回答
      //      「那它到底会不会随全局主题变」；新钉直接验证**取值来源的稳定性**：
      //      前景必须来自 `editorPaletteFor(...)`（由**编辑器预设 key** 决定），
      //      而**不得**来自 `context.palette`（由**全局 ThemeMode** 决定）。
      //
      // 语义等价性论证（为何新判据仍守住 R4）：
      //   实测反例（2026-09-22，WCAG 实算）：
      //     · 米纸底 vs AppPalette.dark.textPrimary  ⇒ 1.07:1（不可读）
      //     · 暗夜底 vs AppPalette.light.textPrimary ⇒ 1.15:1（不可读）
      //   ⇒ 「跟全局翻」无论哪个方向都不可读。旧实现的规避手段是「退回静态常量」；
      //     新实现的手段是「按**预设 key** 选 palette 实例」（暗夜⇒dark，其余⇒light），
      //     两者都满足「不随全局翻」，但后者仍是 palette 体系成员 ⇒ 可复用。
      expect(
        code,
        contains('editorPaletteFor('),
        reason:
            'R4：编辑器前景必须由**编辑器预设 key** 选 palette（editorPaletteFor），'
            '而非跟随全局 ThemeMode；否则「全局暗 + 米纸编辑器」下亮字压亮底不可读',
      );
      expect(fn, contains('R4'), reason: '注因必须在场，否则下批无从判断这是刻意而非漏迁');
      // ★ 反向钉（**保留不变**）：该函数**代码**内不得出现运行期全局前景取色
      //   —— 这是 R4 的核心禁令，无论实现怎么换都必须成立。
      expect(
        code.contains('context.palette.textPrimary') ||
            code.contains('context.palette.textSecondary'),
        isFalse,
        reason: '该处一旦吃全局 context.palette，「全局暗 + 米纸编辑器」下即不可读',
      );
    });
  });
}
