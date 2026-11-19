// ─────────────────────────────────────────────────────────────
// yue_sheet_test — 批次68 弹窗统一入口
// 断言 showYueModalBottomSheet 打开/关闭/返回值行为不被封装破坏。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_theme.dart' show AppSpacing;
import 'package:writingcoach/theme/app_theme.dart';
import 'package:writingcoach/widgets/yue_sheet.dart';

Widget _host(Widget Function(BuildContext) triggerBuilder) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Builder(
      builder: (context) =>
          Scaffold(body: Center(child: triggerBuilder(context))),
    ),
  );
}

void main() {
  group('批次68 showYueModalBottomSheet 统一弹窗', () {
    testWidgets('#1 打开后显示内容（builder 正常渲染）', (tester) async {
      await tester.pumpWidget(
        _host(
          (context) => TextButton(
            onPressed: () => showYueModalBottomSheet<void>(
              context: context,
              builder: (_) => const SizedBox(
                height: 200,
                child: Center(child: Text('统一弹窗内容')),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('统一弹窗内容'), findsOneWidget);
    });

    testWidgets('#2 点击 barrier 关闭', (tester) async {
      await tester.pumpWidget(
        _host(
          (context) => TextButton(
            onPressed: () => showYueModalBottomSheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 200),
            ),
            child: const Text('打开'),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      // 点击 barrier（sheet 之外的区域）关闭
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('#3 返回值正常传递', (tester) async {
      String? result;
      await tester.pumpWidget(
        _host(
          (context) => TextButton(
            onPressed: () async {
              result = await showYueModalBottomSheet<String>(
                context: context,
                builder: (sheetCtx) => SizedBox(
                  height: 200,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetCtx, '选了A'),
                    child: const Text('选A'),
                  ),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选A'));
      await tester.pumpAndSettle();

      expect(result, '选了A');
    });
  });

  // ── 2026-11-19 新增：正文区左右内边距守护 ──────────────────
  //
  // 缺陷史：`YueSheetScaffold` 的标题行与操作行都有 `AppSpacing.lg` 左右
  // 内边距，**正文区却裸挂在 SingleChildScrollView 下** ⇒ 教练人设编辑面板
  // 的输入框横向顶到屏幕边缘（舰长 2026-11-19 走查发现）。全仓 7 个表单
  // 弹层共用本骨架，属公共层缺陷，不是单页样式瑕疵。
  //
  // 断言方式：以**同层的 Divider 作几何参照**。Divider 横跨整个 sheet 宽、
  // 不带 padding，因此它的左右边缘就是 sheet 内容框的真实边界；正文的左/右
  // 边缘相对它必须恰为 AppSpacing.lg。这样判据不依赖 sheet 宽度常量
  // （Material 3 会把 bottom sheet 限到 640 并居中，写死屏幕宽会算出 96 而非 16）。
  //
  // 为什么不用「标题文字左边缘」作参照：Text 的 getTopRight 是墨迹右缘，
  // 不是可用区右缘，右边界上会假红。
  group('YueSheetScaffold 正文内边距（2026-11-19 缺陷回归）', () {
    /// 打开弹层并返回 (sheet 内容框矩形, 正文 probe 矩形)。
    Future<(Rect, Rect)> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          (context) => TextButton(
            onPressed: () => showYueModalBottomSheet<void>(
              context: context,
              builder: (_) => YueSheetScaffold(
                title: '标题锚点',
                actions: const [SizedBox.shrink()],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    SizedBox(key: Key('body-probe'), height: 40),
                  ],
                ),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      return (
        tester.getRect(find.byType(Divider)),
        tester.getRect(find.byKey(const Key('body-probe'))),
      );
    }

    testWidgets('#4 正文左边缘 = sheet 左边缘 + lg（不贴边）', (tester) async {
      final (sheet, body) = await openSheet(tester);

      // 贴边缺陷下 body.left == sheet.left（差值 0），本断言变红。
      expect(body.left - sheet.left, AppSpacing.lg);
    });

    testWidgets('#5 正文右边缘 = sheet 右边缘 − lg（不越界）', (tester) async {
      final (sheet, body) = await openSheet(tester);

      // 贴边缺陷下差值为 0，本断言变红。
      expect(sheet.right - body.right, AppSpacing.lg);
    });

    testWidgets('#6 正文宽度 = sheet 宽 − 2×lg（防单侧补齐冒充两侧）', (tester) async {
      final (sheet, body) = await openSheet(tester);

      // 只补左边或只补右边都能骗过 #4/#5 中的一条；本断言要求两侧同时到位。
      expect(body.width, sheet.width - AppSpacing.lg * 2);
    });
  });
}
