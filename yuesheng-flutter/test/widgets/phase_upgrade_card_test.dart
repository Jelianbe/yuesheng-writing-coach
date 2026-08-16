// ─────────────────────────────────────────────────────────────
// PhaseUpgradeCard widget 测试 — 阶段升级卡片
//
// 覆盖路径：
//   1. P1_WORLD → 世界观阶段 + 解锁描述 + 鼓励语
//   2. P2_PRACTICE_LOOP → 练习循环阶段 + 解锁
//   3. 未知阶段 → 兜底「新阶段」
//   4. fromMessageContent 合法/非法 JSON
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/widgets/phase_upgrade_card.dart';

void main() {
  Widget buildCard(PhaseUpgradeCard card) {
    return MaterialApp(home: Scaffold(body: card));
  }

  testWidgets('#1 P1_WORLD → 世界观阶段 + 解锁 + 鼓励', (tester) async {
    await tester.pumpWidget(
      buildCard(const PhaseUpgradeCard(from: 'P0_ENGAGE', to: 'P1_WORLD')),
    );

    expect(find.text('进入新阶段！'), findsOneWidget);
    expect(find.text('世界观阶段'), findsOneWidget);
    expect(find.text('解锁：世界观构建与场景描写训练'), findsOneWidget);
    expect(find.text('你的写作之旅迈出了第一步！'), findsOneWidget);
  });

  testWidgets('#2 P2_PRACTICE_LOOP → 练习循环阶段', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const PhaseUpgradeCard(from: 'P1_WORLD', to: 'P2_PRACTICE_LOOP'),
      ),
    );

    expect(find.text('练习循环阶段'), findsOneWidget);
    expect(find.text('解锁：系统化写作练习循环'), findsOneWidget);
    expect(find.text('持续练习是进步的阶梯！'), findsOneWidget);
  });

  testWidgets('#3 未知阶段 → 兜底「新阶段」', (tester) async {
    await tester.pumpWidget(
      buildCard(const PhaseUpgradeCard(from: 'P0_ENGAGE', to: 'PX_UNKNOWN')),
    );

    expect(find.text('新阶段'), findsOneWidget);
    expect(find.text('解锁：更多学习功能'), findsOneWidget);
    expect(find.text('继续加油！'), findsOneWidget);
  });

  testWidgets('#4 fromMessageContent 合法 JSON → 解析渲染', (tester) async {
    final payload = PhaseUpgradeCardPayload(
      from: 'P1_WORLD',
      to: 'P2_PRACTICE_LOOP',
      reason: '诊断反馈建议升级',
    );
    await tester.pumpWidget(
      buildCard(
        PhaseUpgradeCard.fromMessageContent(jsonEncode(payload.toJson())),
      ),
    );

    expect(find.text('练习循环阶段'), findsOneWidget);
    expect(find.text('诊断反馈建议升级'), findsOneWidget);
  });

  testWidgets('#5 fromMessageContent 非法 JSON → 兜底渲染', (tester) async {
    await tester.pumpWidget(
      buildCard(PhaseUpgradeCard.fromMessageContent('not-json')),
    );

    expect(find.text('进入新阶段！'), findsOneWidget);
    expect(find.text('世界观阶段'), findsOneWidget); // 兜底 to=P1_WORLD
  });
}
