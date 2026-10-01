// ─────────────────────────────────────────────────────────────
// micro_task_card_wall_test — ADR-C121 30 秒微任务卡片墙 widget 测试
//
// 覆盖：
//   1. 列表态：三张卡 + 副标题 + 素材练习声明
//   2. 选卡 → 填写态：任务/约束/小钩子三块 + 声明
//   3. 字数门槛：<50 字提交禁用 + 提示；≥50 字可提交
//   4. 提交回调：(text, cardId) 上抛 + 弹层关闭
//   5. 「换一个」：变体 prompt 切换（不重置已输入文本）
// ═══════════════════════════════════════════════════════════
// R-009 核验点：断言无范文/示例句存在（卡片只给任务约束）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/onboarding/micro_task_card_wall.dart';
import 'package:writingcoach/services/onboarding_flow.dart';

void main() {
  Future<void> openWall(
    WidgetTester tester, {
    required void Function(String text, String cardId) onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showMicroTaskWallSheet(
                  ctx,
                  entry: 'auto',
                  onSubmit: onSubmit,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('#1 列表态：三张卡 + 副标题 + 声明', (tester) async {
    await openWall(tester, onSubmit: (_, _) {});

    expect(find.text('写第一句 · 30 秒微任务'), findsOneWidget);
    expect(find.text(kMicroTaskWallSubtitle), findsOneWidget);
    for (final card in kMicroTaskCards) {
      expect(find.text(card.title), findsOneWidget);
    }
    expect(find.text(kMicroTaskDisclaimer), findsOneWidget);
  });

  testWidgets('#2 选卡 → 填写态：任务/约束/小钩子三块', (tester) async {
    await openWall(tester, onSubmit: (_, _) {});

    final card = kMicroTaskCards.first;
    await tester.tap(find.text(card.title));
    await tester.pumpAndSettle();

    expect(find.text(card.title), findsOneWidget);
    expect(find.text('任务'), findsOneWidget);
    expect(find.text(card.prompt), findsOneWidget);
    expect(find.text('约束'), findsOneWidget);
    expect(find.text(card.constraint), findsOneWidget);
    expect(find.text('小钩子'), findsOneWidget);
    expect(find.text(card.hook), findsOneWidget);
    // R-009：填写态不得出现任何范文/示例句（只给约束）
    expect(find.textContaining('例如'), findsNothing);
  });

  testWidgets('#3 字数门槛：<50 提交禁用，≥50 可提交', (tester) async {
    await openWall(tester, onSubmit: (_, _) {});

    final card = kMicroTaskCards.first;
    await tester.tap(find.text(card.title));
    await tester.pumpAndSettle();

    // 按钮文案带动态字数，用 textContaining + ancestor 定位 FilledButton
    final submitBtn = find.ancestor(
      of: find.textContaining('让教练诊断'),
      matching: find.byType(FilledButton),
    );
    expect(
      tester.widget<FilledButton>(submitBtn).onPressed,
      isNull,
      reason: '<50 字不可提交（可诊断门槛）',
    );

    // 49 字 → 仍禁用 + 提示
    await tester.enterText(find.byType(TextField), '一' * 49);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(submitBtn).onPressed,
      isNull,
      reason: '49 字仍未达门槛',
    );
    expect(find.textContaining('再写一点'), findsOneWidget);

    // 50 字 → 可提交
    await tester.enterText(find.byType(TextField), '一' * 50);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submitBtn).onPressed, isNotNull);
  });

  testWidgets('#4 提交：回调收到 (text, cardId) 且弹层关闭', (tester) async {
    String? submittedText;
    String? submittedCard;
    await openWall(
      tester,
      onSubmit: (text, cardId) {
        submittedText = text;
        submittedCard = cardId;
      },
    );

    final card = kMicroTaskCards[1]; // dialogue_disagree
    await tester.tap(find.text(card.title));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '一' * 60);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('让教练诊断'));
    await tester.pumpAndSettle();

    expect(submittedText, hasLength(60));
    expect(submittedCard, card.id);
    expect(find.text(card.title), findsNothing, reason: '弹层已关闭');
  });

  testWidgets('#5 「换一个」切换变体 prompt（不重置已输入文本）', (tester) async {
    await openWall(tester, onSubmit: (_, _) {});

    final card = kMicroTaskCards.first;
    await tester.tap(find.text(card.title));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '已有草稿');
    await tester.tap(find.text('换一个'));
    await tester.pumpAndSettle();

    expect(find.text(card.prompt), findsNothing);
    expect(find.text(card.variants.first), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '已有草稿',
      reason: '换一个不重置已写内容（避免学员白写）',
    );
  });
}
