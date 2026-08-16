// ─────────────────────────────────────────────────────────────
// AbandonPracticeDialog 测试 — 放弃练习确认弹窗（缺口清单 C 类）
//
// 覆盖：渲染（图标/标题/文案/双按钮）+ 继续练习回调 +
// 确认跳过回调 + 阻断式（点击遮罩不关闭）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/abandon_practice_modal.dart';

void main() {
  Widget buildHost({
    required VoidCallback onContinue,
    required VoidCallback onConfirmSkip,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AbandonPracticeDialog.show(
                context,
                onContinue: onContinue,
                onConfirmSkip: onConfirmSkip,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('渲染：标题 + 文案 + 继续练习/确认跳过按钮', (tester) async {
    await tester.pumpWidget(buildHost(onContinue: () {}, onConfirmSkip: () {}));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('确定跳过本次练习？'), findsOneWidget);
    expect(find.text('已输入的内容将丢失，练习进度不会保存。'), findsOneWidget);
    expect(find.text('继续练习'), findsOneWidget);
    expect(find.text('确认跳过'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('点击「继续练习」→ onContinue 回调', (tester) async {
    var continued = false;
    await tester.pumpWidget(
      buildHost(onContinue: () => continued = true, onConfirmSkip: () {}),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('继续练习'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
    // 弹窗已关闭
    expect(find.text('确定跳过本次练习？'), findsNothing);
  });

  testWidgets('点击「确认跳过」→ onConfirmSkip 回调', (tester) async {
    var skipped = false;
    await tester.pumpWidget(
      buildHost(onContinue: () {}, onConfirmSkip: () => skipped = true),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确认跳过'));
    await tester.pumpAndSettle();

    expect(skipped, isTrue);
    expect(find.text('确定跳过本次练习？'), findsNothing);
  });

  testWidgets('阻断式：点击遮罩不关闭弹窗（barrierDismissible=false）', (tester) async {
    await tester.pumpWidget(buildHost(onContinue: () {}, onConfirmSkip: () {}));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 点击弹窗外部（遮罩区域）
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 弹窗仍在
    expect(find.text('确定跳过本次练习？'), findsOneWidget);
  });
}
