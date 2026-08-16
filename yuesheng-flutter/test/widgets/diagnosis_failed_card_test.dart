// ─────────────────────────────────────────────────────────────
// DiagnosisFailedCard widget 测试 — 诊断失败卡片
//
// 真源：RN DiagnosisFailedCard.tsx
// 覆盖：
//   1. 渲染（标题/提示/默认 3 条建议/双按钮）
//   2. 自定义建议注入
//   3. failureCount >= 阈值 → 多次失败提示；< 阈值 → 不显示
//   4. 双按钮回调（补充内容/继续对话）
//   5. fromMessageContent 合法 JSON 渲染
//   6. fromMessageContent 非法 JSON 兜底渲染
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/widgets/diagnosis_failed_card.dart';

void main() {
  Widget buildCard(DiagnosisFailedCard card) {
    return MaterialApp(home: Scaffold(body: card));
  }

  testWidgets('#1 渲染：标题 + 提示 + 默认 3 建议 + 双按钮', (tester) async {
    await tester.pumpWidget(
      buildCard(const DiagnosisFailedCard(failureCount: 1)),
    );

    expect(find.text('未检测到明显问题'), findsOneWidget);
    expect(find.text('你可以尝试补充更多写作内容或具体描述遇到的问题。'), findsOneWidget);
    expect(find.text('建议：'), findsOneWidget);
    expect(find.text('上传一段你最近写的文章'), findsOneWidget);
    expect(find.text('描述你写作时卡住的场景'), findsOneWidget);
    expect(find.text('具体说说遇到的问题'), findsOneWidget);
    expect(find.text('补充内容'), findsOneWidget);
    expect(find.text('继续对话'), findsOneWidget);
  });

  testWidgets('#2 自定义建议注入优先', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const DiagnosisFailedCard(
          failureCount: 1,
          suggestions: ['自定义建议一', '自定义建议二'],
        ),
      ),
    );

    expect(find.text('自定义建议一'), findsOneWidget);
    expect(find.text('自定义建议二'), findsOneWidget);
    expect(find.text('上传一段你最近写的文章'), findsNothing);
  });

  testWidgets('#3 failureCount >= 2 → 显示多次失败提示', (tester) async {
    await tester.pumpWidget(
      buildCard(const DiagnosisFailedCard(failureCount: 2)),
    );

    expect(find.text('提示：多次诊断失败后建议主动描述问题'), findsOneWidget);
  });

  testWidgets('#4 failureCount < 2 → 不显示提示', (tester) async {
    await tester.pumpWidget(
      buildCard(const DiagnosisFailedCard(failureCount: 1)),
    );

    expect(find.text('提示：多次诊断失败后建议主动描述问题'), findsNothing);
  });

  testWidgets('#5 双按钮回调触发', (tester) async {
    var added = false;
    var chatted = false;

    await tester.pumpWidget(
      buildCard(
        DiagnosisFailedCard(
          failureCount: 1,
          onAddContent: () => added = true,
          onContinueChat: () => chatted = true,
        ),
      ),
    );

    await tester.tap(find.text('补充内容'));
    await tester.tap(find.text('继续对话'));
    await tester.pump();

    expect(added, isTrue);
    expect(chatted, isTrue);
  });

  testWidgets('#6 fromMessageContent 合法 JSON → 解析渲染 + 提示', (tester) async {
    final payload = DiagnosisFailedCardPayload(failureCount: 3);
    await tester.pumpWidget(
      buildCard(
        DiagnosisFailedCard.fromMessageContent(jsonEncode(payload.toJson())),
      ),
    );

    expect(find.text('未检测到明显问题'), findsOneWidget);
    expect(find.text('提示：多次诊断失败后建议主动描述问题'), findsOneWidget);
  });

  testWidgets('#7 fromMessageContent 非法 JSON → 兜底渲染（不崩溃）', (tester) async {
    await tester.pumpWidget(
      buildCard(DiagnosisFailedCard.fromMessageContent('not-json')),
    );

    expect(find.text('未检测到明显问题'), findsOneWidget);
  });
}
