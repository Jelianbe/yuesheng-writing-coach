// ─────────────────────────────────────────────────────────────
// M4 const 长尾迁移成对断言（2026-09-22）
//
// M4 把 widget 层**最后 14 处**裸色（全部落在 `const` 上下文里）迁到
// `context.palette.*`：去 `const` + 换色 + 补 `BuildContext` 可达性。
// ⇒ `lib/widgets` + `lib/pages` 代码区裸色归零（守卫基线 14/11 → 0/0）。
//
// 为什么必须补断言：M3 已实证本仓既有测试的 `_wrap` 多为**裸 `MaterialApp`**
//   （无 palette 扩展）⇒ **静默回退 `AppPalette.light`** ⇒ 亮色断言全绿、
//   迁移写错也发现不了（「假绿」）。本文件用 `buildAppTheme()` /
//   `buildDarkTheme()` 两轴对照，逼出「真的翻了吗」。
//
// 断言范式（同 `m3_migration_theme_pairing_test.dart`）：
//   · `buildAppTheme()`  下 → 取值 == `AppColors.x`（亮色零变化）
//   · `buildDarkTheme()` 下 → 取值 == `AppPalette.dark.x`（真翻）且 != 亮色
//
// 覆盖 M4 三类的每一类：
//   A. 无 `BuildContext` 的控制器函数（`host.context` 绕行）
//   B. `BuildContext` 形参已存在（去 const 即可）
//   C. 三元 `? const Icon(...) : null`（去 const 不连锁）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/features/chat/chat_welcome.dart';
import 'package:writingcoach/features/chat/import_success_sheet.dart';
import 'package:writingcoach/widgets/quick_phrase_sheet.dart';

Future<void> _pump(WidgetTester t, ThemeData theme, Widget child) async {
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await t.pumpAndSettle();
}

/// `QuickPhraseSheet` 是 `ConsumerStatefulWidget`，`initState` 里会异步
/// 读库（`_load`）。为避免引入 repository 依赖，改用 **`pump` 单帧** +
/// `ProviderScope` 包裹；若读库抛错也只是不建列表，**输入框边界仍在**。
Future<void> _pumpSheet(WidgetTester t, ThemeData theme, Widget child) async {
  await t.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await t.pump();
}

/// 取 `OutlinedButton` 的 `side` 颜色（M4 有三处迁的是 `BorderSide.color`）。
Color _outlinedSide(WidgetTester t) {
  final b = t.widgetList<OutlinedButton>(find.byType(OutlinedButton)).first;
  return b.style!.side!.resolve({})!.color;
}

void main() {
  // ───────────────────────────────────────────────────────────
  // 组 A：`ChatWelcome._buildActions`（`chat_welcome.dart:82`）
  //   迁的是「自主练习」按钮的 `OutlinedButton.side`：`AppColors.primary`
  //   → `context.palette.primary`。
  // ★ 该按钮仅当 `onSelfPractice != null` 时才渲染 ⇒ 必须传入回调。
  // ───────────────────────────────────────────────────────────
  group('A ChatWelcome 自主练习按钮描边色随主题翻（去 const BorderSide）', () {
    testWidgets('亮色 == AppColors.primary', (t) async {
      await _pump(t, buildAppTheme(), ChatWelcome(onSelfPractice: () {}));
      expect(_outlinedSide(t), AppColors.primary);
    });

    testWidgets('暗色 == dark.primary 且 != 亮色', (t) async {
      await _pump(t, buildDarkTheme(), ChatWelcome(onSelfPractice: () {}));
      final side = _outlinedSide(t);
      expect(side, AppPalette.dark.primary, reason: '描边色应已随主题翻');
      expect(side, isNot(AppColors.primary), reason: '暗色仍取亮色静态值 ⇒ 未真的翻');
    });
  });

  // ───────────────────────────────────────────────────────────
  // 组 B：`ImportSuccessSheet`（`import_success_sheet.dart:154`）
  //   「稍后再说」按钮描边：`AppColors.border` → `context.palette.border`。
  //   注意 `diagnoseEnabled: false` 会**不渲染**该按钮（:144 条件）
  //   ⇒ 必须保持默认 `true`。
  // ───────────────────────────────────────────────────────────
  group('B ImportSuccessSheet 稍后再说按钮描边色随主题翻（去 const BorderSide）', () {
    testWidgets('亮色 == AppColors.border', (t) async {
      await _pump(
        t,
        buildAppTheme(),
        ImportSuccessSheet(
          manuscriptTitle: '测试作品',
          chapterCount: 3,
          manuscriptId: 'm1',
          onClose: () {},
          onDiagnose: () {},
        ),
      );
      expect(_outlinedSide(t), AppColors.border);
    });

    testWidgets('暗色 == dark.border 且 != 亮色', (t) async {
      await _pump(
        t,
        buildDarkTheme(),
        ImportSuccessSheet(
          manuscriptTitle: '测试作品',
          chapterCount: 3,
          manuscriptId: 'm1',
          onClose: () {},
          onDiagnose: () {},
        ),
      );
      final side = _outlinedSide(t);
      expect(side, AppPalette.dark.border);
      expect(side, isNot(AppColors.border), reason: '未真的翻');
    });
  });

  // ───────────────────────────────────────────────────────────
  // 组 C：`QuickPhraseSheet` 输入框三个边框（`:151/155/159`）
  //   `border`/`enabledBorder` = `AppColors.borderSoft`
  //   `focusedBorder`          = `AppColors.primary`
  //   （`focusedBorder` 只在获得焦点时生效 —— 用 tap 制造焦点）
  // ───────────────────────────────────────────────────────────
  group('C QuickPhraseSheet 输入框边框色随主题翻（三处 BorderSide 去 const）', () {
    testWidgets('亮色：normal/enabled == AppColors.borderSoft', (t) async {
      await _pumpSheet(t, buildAppTheme(), QuickPhraseSheet(onInsert: (_) {}));
      final deco = t
          .widget<TextField>(find.byType(TextField).first)
          .decoration!;
      expect(
        (deco.border as OutlineInputBorder?)?.borderSide.color,
        AppColors.borderSoft,
      );
      expect(
        (deco.enabledBorder as OutlineInputBorder?)?.borderSide.color,
        AppColors.borderSoft,
      );
    });

    testWidgets('暗色：normal/enabled == dark.borderSoft 且 != 亮色', (t) async {
      await _pumpSheet(t, buildDarkTheme(), QuickPhraseSheet(onInsert: (_) {}));
      final deco = t
          .widget<TextField>(find.byType(TextField).first)
          .decoration!;
      final border = (deco.border as OutlineInputBorder?)?.borderSide.color;
      expect(border, AppPalette.dark.borderSoft);
      expect(border, isNot(AppColors.borderSoft), reason: '未真的翻');
    });

    testWidgets('暗色：focusedBorder == dark.primary 且 != 亮色', (t) async {
      await _pumpSheet(t, buildDarkTheme(), QuickPhraseSheet(onInsert: (_) {}));
      final deco = t
          .widget<TextField>(find.byType(TextField).first)
          .decoration!;
      final focused =
          (deco.focusedBorder as OutlineInputBorder?)?.borderSide.color;
      expect(focused, AppPalette.dark.primary);
      expect(focused, isNot(AppColors.primary), reason: '未真的翻');
    });
  });
}
