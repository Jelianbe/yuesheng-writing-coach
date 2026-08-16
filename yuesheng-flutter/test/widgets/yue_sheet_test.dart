// ─────────────────────────────────────────────────────────────
// yue_sheet_test — 批次68 弹窗统一入口
// 断言 showYueModalBottomSheet 打开/关闭/返回值行为不被封装破坏。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/main.dart';
import 'package:writingcoach/widgets/yue_sheet.dart';

Widget _host(Widget Function(BuildContext) triggerBuilder) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Builder(
      builder: (context) => Scaffold(body: Center(child: triggerBuilder(context))),
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
}
