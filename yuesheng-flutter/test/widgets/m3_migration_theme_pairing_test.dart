// ─────────────────────────────────────────────────────────────
// M3+M4 迁移成对断言（2026-09-22，M4 批升级）
//
// M3 把 widget 层 119 处「裸色直读」（`AppColors.x`）迁到
// `context.palette.x`；M4 把最后 14 处 `const` 上下文长尾一并迁完
// ⇒ **`lib/widgets` + `lib/pages` 代码区裸色归零**（守卫基线 14/11 → 0/0）。
//
// 迁移的**全部收益**是「这些色现在随主题翻」—— 但本仓既有测试的 `_wrap`
// 多是裸 `MaterialApp`（无 palette 扩展），会**静默回退 `AppPalette.light`**
// ⇒ 亮色断言照样通过，**迁移写错也无法被发现**（「假绿」的经典形态）。
//
// 本文件按 `bookshelf_empty_state_theme_test.dart` 既有范式补断言：
//   · `buildAppTheme()`  下 → 取值 == `AppColors.x`（亮色零变化）
//   · `buildDarkTheme()` 下 → 取值 == `AppPalette.dark.x`（真翻）
//                            且 **!= 亮色值**（防「焊死在某一份」）
//
// ★ 覆盖 M3+M4 各类处置方式的代表：
//   ① `teaching_state_badge` —— `get _dotColor` → `_dotColorOf(context)`
//   ② `thinking_placeholder` —— 补 `BuildContext` 形参
//   ③ `knowledge_card`       —— `const TextStyle(...)` 内色（去 const）
//   ④ 三个错误/空态视图的**图标色** —— 原落 `const Icon(...)`，
//      M4 批去 const 后已随主题翻
//
// ★★ 本文件 M4 批的**语义反转**（重要先例）：
//   M3 批时 ③④ 两组是「**长尾现状钉**」—— 断言「两轴恒同值」以钉住
//   「当前不随主题翻」。M4 批迁完后该断言**必红**，故本轮把两组**整体
//   改写为「随主题翻」**（亮 == 静态令牌、暗 == dark 令牌 且 != 亮）。
//   ⇒ 纪律：**现状钉是「带保质期的断言」**，钉的对象一旦被修，
//     断言必须**同步反转**，而不是删掉了事（删了就等于放弃鉴别力）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/features/bookshelf/bookshelf_error_view.dart';
import 'package:writingcoach/features/bookshelf/bookshelf_no_search_result.dart';
import 'package:writingcoach/features/growth/growth_detail_error_view.dart';
import 'package:writingcoach/widgets/knowledge_card.dart';
import 'package:writingcoach/widgets/teaching_state_badge.dart';
import 'package:writingcoach/features/writing/thinking_placeholder.dart';

Future<void> _pump(WidgetTester t, ThemeData theme, Widget child) async {
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await t.pumpAndSettle();
}

/// ★ `ThinkingPlaceholder` 内含 `CircularProgressIndicator`（**无限动画**）
///   ⇒ `pumpAndSettle` 永不收敛，会 `pumpAndSettle timed out`。
///   这类控件必须用单帧 `pump()`（建树与取色一帧即完成）。
Future<void> _pumpOnce(WidgetTester t, ThemeData theme, Widget child) async {
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await t.pump();
}

/// 取第一个带非空 BoxDecoration 色的 `Container` 的装饰色。
Color _containerColor(WidgetTester t) {
  final c = t
      .widgetList<Container>(find.byType(Container))
      .firstWhere(
        (w) =>
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color != null,
      );
  return (c.decoration as BoxDecoration).color!;
}

/// 取图标色。
Color _iconColor(WidgetTester t, IconData icon) =>
    t.widget<Icon>(find.byIcon(icon).first).color!;

void main() {
  // ① 状态徽章 —— M3 里唯一「getter → 方法」的结构性改造。
  //    4 个状态色各来自不同令牌（warning / primaryDeep / primary /
  //    disabledText），最能暴露「迁移时接错令牌」。
  group('① TeachingStateBadge 圆点色随主题翻（getter → 方法）', () {
    const lightCases = <TeachingState, Color>{
      TeachingState.identified: AppColors.warning,
      TeachingState.inProgress: AppColors.primaryDeep,
      TeachingState.consolidating: AppColors.primary,
      TeachingState.mastered: AppColors.disabledText,
    };

    testWidgets('亮色：四态色 == AppColors 对应令牌', (t) async {
      for (final e in lightCases.entries) {
        await _pump(t, buildAppTheme(), TeachingStateBadge(state: e.key));
        expect(_containerColor(t), e.value, reason: '${e.key} 亮色错');
      }
    });

    testWidgets('暗色：四态色 == AppPalette.dark 且均 != 亮色', (t) async {
      // 逐 case 显式对照（不玩花活，便于阅读与排错）
      const pairs = <TeachingState, (Color light, Color Function(AppPalette))>{
        TeachingState.identified: (AppColors.warning, _w),
        TeachingState.inProgress: (AppColors.primaryDeep, _pd),
        TeachingState.consolidating: (AppColors.primary, _p),
        TeachingState.mastered: (AppColors.disabledText, _dt),
      };
      for (final e in pairs.entries) {
        await _pump(t, buildDarkTheme(), TeachingStateBadge(state: e.key));
        final dark = e.value.$2(AppPalette.dark);
        expect(_containerColor(t), dark, reason: '${e.key} 未翻到暗色');
        expect(
          dark,
          isNot(e.value.$1),
          reason: '${e.key} 的令牌在亮/暗两轴同值 ⇒ 本组断言无鉴别力，须换判据',
        );
      }
    });

    testWidgets('暗色：标签文字色 == dark.textTertiary 且 != 亮色', (t) async {
      await _pump(
        t,
        buildDarkTheme(),
        const TeachingStateBadge(
          state: TeachingState.identified,
          showLabel: true,
        ),
      );
      final label = t.widget<Text>(
        find.text(teachingStateLabels[TeachingState.identified]!),
      );
      expect(label.style!.color, AppPalette.dark.textTertiary);
      expect(label.style!.color, isNot(AppColors.textTertiary));
    });
  });

  // ② 思考占位 —— M3 处置是「补 BuildContext 形参」。
  //    注意：其文字样式走 `context.text.subBody`（**样式族**，非色令牌），
  //    `subBody.color == palette.textSecondary`（见 app_typography.dart:52）。
  //    ⇒ 断言必须用 textSecondary，而非 textTertiary
  //      （初版本文件写错过，实测暗色 0.396/0.423/0.462 != 0.604/0.628/0.651）。
  group('② ThinkingPlaceholder 文字色随主题翻（补形参）', () {
    testWidgets('亮色 == AppColors.textSecondary', (t) async {
      await _pumpOnce(t, buildAppTheme(), const ThinkingPlaceholder());
      final txt = t.widget<Text>(find.byType(Text).first);
      expect(txt.style!.color, AppColors.textSecondary);
    });

    testWidgets('暗色 == dark.textSecondary 且 != 亮色', (t) async {
      await _pumpOnce(t, buildDarkTheme(), const ThinkingPlaceholder());
      final txt = t.widget<Text>(find.byType(Text).first);
      expect(txt.style!.color, AppPalette.dark.textSecondary);
      expect(txt.style!.color, isNot(AppColors.textSecondary));
    });
  });

  // ③ `ConfidenceBar` label 色 —— 原 M3 长尾（`knowledge_card.dart:48` 的
  //    `const TextStyle(color: AppColors.textTertiary)`），M4 去 const 已迁。
  //    ★ 本组由 M3 的「现状钉」**反转为「随主题翻」**（见文件头「语义反转」）。
  group('③ ConfidenceBar label 色随主题翻（原 const 长尾，M4 已迁）', () {
    testWidgets('亮色 == AppColors.textTertiary', (t) async {
      await _pump(
        t,
        buildAppTheme(),
        const ConfidenceBar(label: '诊断信心', value: 0.8),
      );
      expect(
        t.widget<Text>(find.text('诊断信心')).style!.color,
        AppColors.textTertiary,
      );
    });

    testWidgets('暗色 == dark.textTertiary 且 != 亮色', (t) async {
      await _pump(
        t,
        buildDarkTheme(),
        const ConfidenceBar(label: '诊断信心', value: 0.8),
      );
      final dark = t.widget<Text>(find.text('诊断信心')).style!.color;
      expect(
        dark,
        AppPalette.dark.textTertiary,
        reason: '本处应已随主题翻；若红 ⇒ 迁移回退了（或令牌接错）',
      );
      expect(
        dark,
        isNot(AppColors.textTertiary),
        reason: '暗色仍取到亮色静态值 ⇒ 该处**没有真的翻**',
      );
    });

    testWidgets('同文件 track/fill 色亦随主题翻（不再半新半旧）', (t) async {
      await _pump(
        t,
        buildDarkTheme(),
        const ConfidenceBar(label: '诊断信心', value: 0.8),
      );
      // fill 色已迁到 context.palette.primary（:78）
      final fill = t
          .widgetList<Container>(find.byType(Container))
          .where((w) => w.color == AppPalette.dark.primary);
      expect(fill, isNotEmpty, reason: 'fill 应已随主题翻到 dark.primary');
    });
  });

  // ④ 三个错误/空态视图的**图标色** —— 原落 `const Icon(...)`（M3 长尾），
  //    M4 批去 const 后已随主题翻。
  //    ★ 本组同样由「现状钉」**反转为「随主题翻」**。
  group('④ 错误/空态视图图标色随主题翻（原 const 长尾，M4 已迁）', () {
    testWidgets('bookshelf_error_view：亮 == danger，暗 == dark.danger 且 != 亮', (
      t,
    ) async {
      await _pump(
        t,
        buildAppTheme(),
        BookshelfErrorView(message: '加载失败', onRetry: () {}),
      );
      expect(_iconColor(t, Icons.error_outline), AppColors.danger);

      await _pump(
        t,
        buildDarkTheme(),
        BookshelfErrorView(message: '加载失败', onRetry: () {}),
      );
      final dark = _iconColor(t, Icons.error_outline);
      expect(dark, AppPalette.dark.danger);
      expect(dark, isNot(AppColors.danger), reason: '未真的翻');
    });

    testWidgets(
      'bookshelf_no_search_result：亮 == textTertiary，暗 == dark 且 != 亮',
      (t) async {
        await _pump(
          t,
          buildAppTheme(),
          const BookshelfNoSearchResult(query: 'xyz', searching: false),
        );
        expect(_iconColor(t, Icons.search_off), AppColors.textTertiary);

        await _pump(
          t,
          buildDarkTheme(),
          const BookshelfNoSearchResult(query: 'xyz', searching: false),
        );
        final dark = _iconColor(t, Icons.search_off);
        expect(dark, AppPalette.dark.textTertiary);
        expect(dark, isNot(AppColors.textTertiary), reason: '未真的翻');
      },
    );

    testWidgets(
      'growth_detail_error_view：亮 == danger，暗 == dark.danger 且 != 亮',
      (t) async {
        await _pump(
          t,
          buildAppTheme(),
          GrowthErrorView(error: '出错了', onRetry: () {}),
        );
        expect(_iconColor(t, Icons.error_outline), AppColors.danger);

        await _pump(
          t,
          buildDarkTheme(),
          GrowthErrorView(error: '出错了', onRetry: () {}),
        );
        final dark = _iconColor(t, Icons.error_outline);
        expect(dark, AppPalette.dark.danger);
        expect(dark, isNot(AppColors.danger), reason: '未真的翻');
      },
    );
  });
}

// 顶层函数：给上面 `pairs` 表引用（避免在 const map 里写 lambda 的语法噪音）
Color _w(AppPalette p) => p.warning;
Color _pd(AppPalette p) => p.primaryDeep;
Color _p(AppPalette p) => p.primary;
Color _dt(AppPalette p) => p.disabledText;
