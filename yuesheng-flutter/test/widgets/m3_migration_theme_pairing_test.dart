// ─────────────────────────────────────────────────────────────
// M3 迁移成对断言（2026-09-22）
//
// M3 把 widget 层 119 处「裸色直读」（`AppColors.x`）迁到
// `context.palette.x`。迁移的**全部收益**是「这些色现在随主题翻」——
// 但本仓既有测试的 `_wrap` 多是裸 `MaterialApp`（无 palette 扩展），
// 会**静默回退 `AppPalette.light`** ⇒ 亮色断言照样通过，
// **迁移写错也无法被发现**（「假绿」的经典形态）。
//
// 本文件按 `bookshelf_empty_state_theme_test.dart` 既有范式补断言：
//   · `buildAppTheme()`  下 → 取值 == `AppColors.x`（亮色零变化）
//   · `buildDarkTheme()` 下 → 取值 == `AppPalette.dark.x`（真翻）
//                            且 **!= 亮色值**（防「焊死在某一份」）
//
// ★ 覆盖 M3 各类处置方式的代表：
//   ① `teaching_state_badge` —— `get _dotColor` → `_dotColorOf(context)`
//   ② `thinking_placeholder` —— 补 `BuildContext` 形参
//   ③ `knowledge_card`       —— `const TextStyle(...)` 内色（去 const）
//   ④ ★ **长尾现状钉**：`bookshelf_error_view` / `bookshelf_no_search_result`
//      / `growth_detail_error_view` 的**图标色**属 M3 未迁的 14 处
//      （落 `const Icon(...)`，去 const 代价待裁定）。
//      本组断言**钉住「它们当前不随主题翻」这一事实** —— 一旦后续批次
//      迁移它们，本组会变红提醒同步更新，而不是让现状**无人知晓**。
//      （仓内既有惯例：`long_tail_theme_test.dart` 正是干的这件事。）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/bookshelf_error_view.dart';
import 'package:writingcoach/widgets/bookshelf_no_search_result.dart';
import 'package:writingcoach/widgets/growth_detail_error_view.dart';
import 'package:writingcoach/widgets/knowledge_card.dart';
import 'package:writingcoach/widgets/teaching_state_badge.dart';
import 'package:writingcoach/widgets/writing/thinking_placeholder.dart';

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

  // ③ ★ 长尾现状钉（一）：`ConfidenceBar` 的 label 色
  //    —— `knowledge_card.dart:48` 仍是 `const TextStyle(color: AppColors.textTertiary)`，
  //    属 M3 未迁的 14 处之一。断言「两轴恒同值」= 确认它**不翻**。
  //    ★ 初版本文件误以为它已迁移（断言 == dark.textTertiary），实测红：
  //      暗色下仍是亮色值 0.396/0.423/0.462。**测试写错也会红**，
  //      这正是本文件要补的鉴别力（旧测试全是裸 MaterialApp，无法暴露）。
  group('③ 长尾现状钉（一）：ConfidenceBar label 色当前**不**随主题翻', () {
    testWidgets('两轴恒为 AppColors.textTertiary', (t) async {
      await _pump(
        t,
        buildAppTheme(),
        const ConfidenceBar(label: '诊断信心', value: 0.8),
      );
      final light = t.widget<Text>(find.text('诊断信心')).style!.color;
      expect(light, AppColors.textTertiary);

      await _pump(
        t,
        buildDarkTheme(),
        const ConfidenceBar(label: '诊断信心', value: 0.8),
      );
      expect(
        t.widget<Text>(find.text('诊断信心')).style!.color,
        light,
        reason:
            '本处仍是 `const TextStyle(AppColors.textTertiary)` ⇒ 不随主题翻。'
            '若变红 ⇒ 该处已迁移，请把本组移入「随主题翻」类。',
      );
    });

    testWidgets('同文件的 track/fill 色**已**随主题翻（半新半旧的对照）', (t) async {
      await _pump(
        t,
        buildDarkTheme(),
        const ConfidenceBar(label: '诊断信心', value: 0.8),
      );
      // fill 色已迁到 context.palette.primary（:60）
      final fill = t
          .widgetList<Container>(find.byType(Container))
          .where((w) => w.color == AppPalette.dark.primary);
      expect(fill, isNotEmpty, reason: 'fill 应已随主题翻到 dark.primary');
    });
  });

  // ④ ★ 长尾现状钉：这三个视图的**图标色**属 M3 未迁的 14 处
  //    （落 `const Icon(...)`）。断言「两主题下都是同一个静态值」
  //    —— 即**确认它不翻**。一旦迁移，本组变红 ⇒ 强制同步更新。
  group('④ 长尾现状钉：错误/空态图标色当前**不**随主题翻（14 处之一）', () {
    testWidgets('bookshelf_error_view 图标色两轴恒为 AppColors.danger', (t) async {
      await _pump(
        t,
        buildAppTheme(),
        BookshelfErrorView(message: '加载失败', onRetry: () {}),
      );
      final light = _iconColor(t, Icons.error_outline);
      expect(light, AppColors.danger);

      await _pump(
        t,
        buildDarkTheme(),
        BookshelfErrorView(message: '加载失败', onRetry: () {}),
      );
      expect(
        _iconColor(t, Icons.error_outline),
        light,
        reason:
            '本处仍是 `const Icon(AppColors.danger)` ⇒ 不随主题翻。'
            '若此断言变红，说明该处已迁移 —— 请把本组移入「随主题翻」类。',
      );
    });

    testWidgets('bookshelf_no_search_result 图标色两轴恒为 textTertiary', (t) async {
      await _pump(
        t,
        buildAppTheme(),
        const BookshelfNoSearchResult(query: 'xyz', searching: false),
      );
      final light = _iconColor(t, Icons.search_off);
      expect(light, AppColors.textTertiary);

      await _pump(
        t,
        buildDarkTheme(),
        const BookshelfNoSearchResult(query: 'xyz', searching: false),
      );
      expect(_iconColor(t, Icons.search_off), light);
    });

    testWidgets('growth_detail_error_view 图标色两轴恒为 AppColors.danger', (t) async {
      await _pump(
        t,
        buildAppTheme(),
        GrowthErrorView(error: '出错了', onRetry: () {}),
      );
      final light = _iconColor(t, Icons.error_outline);
      expect(light, AppColors.danger);

      await _pump(
        t,
        buildDarkTheme(),
        GrowthErrorView(error: '出错了', onRetry: () {}),
      );
      expect(_iconColor(t, Icons.error_outline), light);
    });
  });
}

// 顶层函数：给上面 `pairs` 表引用（避免在 const map 里写 lambda 的语法噪音）
Color _w(AppPalette p) => p.warning;
Color _pd(AppPalette p) => p.primaryDeep;
Color _p(AppPalette p) => p.primary;
Color _dt(AppPalette p) => p.disabledText;
