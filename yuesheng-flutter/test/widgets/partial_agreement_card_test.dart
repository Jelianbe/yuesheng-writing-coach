// ─────────────────────────────────────────────────────────────
// PartialAgreementCard widget 测试 — 部分认同反馈卡片
//
// 真源：RN PartialAgreementCard.tsx
// 覆盖：
//   1. 渲染（标题/severity 徽标/症候名/提示/输入框/快速选项/双按钮）
//   2. 空输入 → 提交禁用；输入后提交 → onSubmit(feedback, null)
//   3. 快速选项点击 → onSubmit(value, value)
//   4. 跳过此症候 → onSkip
//   5. fromMessageContent 合法 JSON 渲染
//   6. fromMessageContent 非法 JSON 兜底渲染
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/widgets/partial_agreement_card.dart';

void main() {
  Widget buildCard(PartialAgreementCard card) {
    return MaterialApp(home: Scaffold(body: card));
  }

  testWidgets('#1 渲染：标题 + severity 徽标 + 症候名 + 双按钮 + 3 快速选项', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const PartialAgreementCard(
          syndromeId: 'P001',
          syndromeName: '视角跳跃症',
          severity: 'L2',
        ),
      ),
    );

    expect(find.text('请补充不符合的地方'), findsOneWidget);
    expect(find.text('L2'), findsOneWidget);
    expect(find.text('视角跳跃症'), findsOneWidget);
    expect(find.text('告诉我哪些描述不准确，我会调整诊断结果。'), findsOneWidget);
    expect(find.text('快速选项：'), findsOneWidget);
    expect(find.text('症状描述不准'), findsOneWidget);
    expect(find.text('缺少某个问题'), findsOneWidget);
    expect(find.text('严重度不对'), findsOneWidget);
    expect(find.text('跳过此症候'), findsOneWidget);
    expect(find.text('提交反馈'), findsOneWidget);
  });

  testWidgets('#2 空输入 → 提交禁用；输入后提交 → onSubmit(feedback, null)', (tester) async {
    String? submittedFeedback;
    String? submittedQuick;

    await tester.pumpWidget(
      buildCard(
        PartialAgreementCard(
          syndromeId: 'P001',
          syndromeName: '视角跳跃症',
          severity: 'L2',
          onSubmit: (feedback, quickOption) {
            submittedFeedback = feedback;
            submittedQuick = quickOption;
          },
        ),
      ),
    );

    // 空输入：提交按钮禁用
    final submitBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '提交反馈'),
    );
    expect(submitBtn.onPressed, isNull);

    // 输入反馈
    await tester.enterText(find.byType(TextField), '我觉得问题不严重');
    await tester.pump();

    // 输入后：提交可用，点击触发回调（quickOption 为 null）
    await tester.tap(find.text('提交反馈'));
    await tester.pump();

    expect(submittedFeedback, '我觉得问题不严重');
    expect(submittedQuick, isNull);
    // 提交后输入框清空
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('#3 快速选项点击 → onSubmit(value, value)', (tester) async {
    String? submittedFeedback;
    String? submittedQuick;

    await tester.pumpWidget(
      buildCard(
        PartialAgreementCard(
          syndromeId: 'P001',
          syndromeName: '视角跳跃症',
          severity: 'L2',
          onSubmit: (feedback, quickOption) {
            submittedFeedback = feedback;
            submittedQuick = quickOption;
          },
        ),
      ),
    );

    await tester.tap(find.text('症状描述不准'));
    await tester.pump();

    expect(submittedFeedback, 'symptom_inaccurate');
    expect(submittedQuick, 'symptom_inaccurate');
  });

  testWidgets('#4 跳过此症候 → onSkip 触发', (tester) async {
    var skipped = false;

    await tester.pumpWidget(
      buildCard(
        PartialAgreementCard(
          syndromeId: 'P001',
          syndromeName: '视角跳跃症',
          severity: 'L2',
          onSkip: () => skipped = true,
        ),
      ),
    );

    await tester.tap(find.text('跳过此症候'));
    await tester.pump();

    expect(skipped, isTrue);
  });

  testWidgets('#5 fromMessageContent 合法 JSON → 解析渲染', (tester) async {
    final payload = PartialAgreementCardPayload(
      syndromeId: 'P001',
      syndromeName: '视角跳跃症',
      severity: 'L3',
    );
    await tester.pumpWidget(
      buildCard(
        PartialAgreementCard.fromMessageContent(jsonEncode(payload.toJson())),
      ),
    );

    expect(find.text('视角跳跃症'), findsOneWidget);
    expect(find.text('L3'), findsOneWidget);
  });

  testWidgets('#6 fromMessageContent 非法 JSON → 兜底渲染（不崩溃）', (tester) async {
    await tester.pumpWidget(
      buildCard(PartialAgreementCard.fromMessageContent('not-json')),
    );

    expect(find.text('请补充不符合的地方'), findsOneWidget);
  });

  testWidgets('#7 批次81 未接 onSubmit 提交反馈 → 保留文本（杜绝静默清空）', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const PartialAgreementCard(
          syndromeId: 'P001',
          syndromeName: '视角跳跃症',
          severity: 'L2',
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '我觉得问题不严重');
    await tester.pump();
    await tester.tap(find.text('提交反馈'));
    await tester.pump();

    // 无外部回调（反馈未被消费）：输入保留，不假装已提交清空
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '我觉得问题不严重',
    );
  });

  testWidgets('#8 批次81 quickOptionLabel value → 中文 label', (tester) async {
    expect(quickOptionLabel('symptom_inaccurate'), '症状描述不准');
    expect(quickOptionLabel('missing_problem'), '缺少某个问题');
    expect(quickOptionLabel('severity_wrong'), '严重度不对');
    // 未命中 → 原样返回，保证文案不丢
    expect(quickOptionLabel('unknown_option'), 'unknown_option');
  });
}
