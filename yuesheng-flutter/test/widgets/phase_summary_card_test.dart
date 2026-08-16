// ─────────────────────────────────────────────────────────────
// PhaseSummaryCard widget 测试 — 阶段总结卡片
//
// 真源：RN PhaseSummaryCard.tsx
// 覆盖：
//   1. passed → 训练达标 + 鼓励 + 统计（解决症候数/练习次数/进步趋势）
//   2. failed → 继续加油
//   3. partial → 部分达标
//   4. 症候变化列表（名称 + 趋势标签，>5 条截断）
//   5. 三按钮回调（继续训练/查看学员画像/返回对话）
//   6. fromMessageContent 合法 JSON 渲染
//   7. fromMessageContent 非法 JSON 兜底渲染
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/widgets/phase_summary_card.dart';

void main() {
  Widget buildCard(PhaseSummaryCard card) {
    return MaterialApp(home: Scaffold(body: card));
  }

  testWidgets('#1 passed → 训练达标 + 鼓励 + 统计行', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const PhaseSummaryCard(
          result: 'passed',
          resolvedSyndromeCount: 2,
          trainingCount: 5,
          trend: 'improving',
          syndromeChanges: [],
        ),
      ),
    );

    expect(find.text('训练达标'), findsOneWidget);
    expect(find.text('太棒了！你的努力得到了回报，继续保持！'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('解决症候数'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('练习次数'), findsOneWidget);
    expect(find.text('改善'), findsOneWidget);
    expect(find.text('进步趋势'), findsOneWidget);
    expect(find.text('继续训练'), findsOneWidget);
    expect(find.text('查看学员画像'), findsOneWidget);
    expect(find.text('返回对话'), findsOneWidget);
  });

  testWidgets('#2 failed → 继续加油', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const PhaseSummaryCard(
          result: 'failed',
          resolvedSyndromeCount: 0,
          trainingCount: 3,
          trend: 'worsening',
          syndromeChanges: [],
        ),
      ),
    );

    expect(find.text('继续加油'), findsOneWidget);
    expect(find.text('恶化'), findsOneWidget);
  });

  testWidgets('#3 partial → 部分达标', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const PhaseSummaryCard(
          result: 'partial',
          resolvedSyndromeCount: 1,
          trainingCount: 4,
          trend: 'stable',
          syndromeChanges: [],
        ),
      ),
    );

    expect(find.text('部分达标'), findsOneWidget);
    expect(find.text('稳定'), findsOneWidget);
  });

  testWidgets('#4 症候变化列表：名称 + 趋势标签 + 超 5 条截断', (tester) async {
    final changes = <SyndromeChangeItem>[
      for (var i = 1; i <= 7; i++)
        SyndromeChangeItem(
          syndromeId: 'P00$i',
          syndromeName: '症候$i',
          trend: i.isEven ? 'improving' : 'stable',
        ),
    ];
    await tester.pumpWidget(
      buildCard(
        PhaseSummaryCard(
          result: 'passed',
          resolvedSyndromeCount: 3,
          trainingCount: 6,
          trend: 'improving',
          syndromeChanges: changes,
        ),
      ),
    );

    expect(find.text('症候变化'), findsOneWidget);
    // 只显示前 5 条
    expect(find.text('症候1'), findsOneWidget);
    expect(find.text('症候5'), findsOneWidget);
    expect(find.text('症候6'), findsNothing);
    expect(find.text('症候7'), findsNothing);
  });

  testWidgets('#5 三按钮回调触发', (tester) async {
    var continued = false;
    var profile = false;
    var back = false;

    await tester.pumpWidget(
      buildCard(
        PhaseSummaryCard(
          result: 'passed',
          resolvedSyndromeCount: 1,
          trainingCount: 2,
          trend: 'stable',
          syndromeChanges: const [],
          onContinueTraining: () => continued = true,
          onViewProfile: () => profile = true,
          onBackToChat: () => back = true,
        ),
      ),
    );

    await tester.tap(find.text('继续训练'));
    await tester.tap(find.text('查看学员画像'));
    await tester.tap(find.text('返回对话'));
    await tester.pump();

    expect(continued, isTrue);
    expect(profile, isTrue);
    expect(back, isTrue);
  });

  testWidgets('#6 fromMessageContent 合法 JSON → 解析渲染', (tester) async {
    final payload = PhaseSummaryCardPayload(
      result: 'partial',
      resolvedSyndromeCount: 1,
      trainingCount: 4,
      trend: 'improving',
      syndromeChanges: const [
        SyndromeChangeItem(
          syndromeId: 'P001',
          syndromeName: '视角跳跃症',
          trend: 'improving',
        ),
      ],
    );
    await tester.pumpWidget(
      buildCard(
        PhaseSummaryCard.fromMessageContent(jsonEncode(payload.toJson())),
      ),
    );

    expect(find.text('部分达标'), findsOneWidget);
    expect(find.text('视角跳跃症'), findsOneWidget);
    expect(find.text('改善'), findsNWidgets(2)); // 统计趋势 + 症候变化趋势
  });

  testWidgets('#7 fromMessageContent 非法 JSON → 兜底渲染（不崩溃）', (tester) async {
    await tester.pumpWidget(
      buildCard(PhaseSummaryCard.fromMessageContent('not-json')),
    );

    expect(find.text('部分达标'), findsOneWidget);
  });
}
