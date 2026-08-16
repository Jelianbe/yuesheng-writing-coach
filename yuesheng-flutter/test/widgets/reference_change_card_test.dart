// ─────────────────────────────────────────────────────────────
// ReferenceChangeCard widget 测试 — 引用变更卡片
//
// 覆盖路径：
//   1. set_primary → 主引用已切换 + 类型标签 + 标题
//   2. add → 已添加引用
//   3. remove → 已移除引用
//   4. fromMessageContent 非法 JSON → 兜底渲染（不崩溃）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/widgets/reference_change_card.dart';

void main() {
  Widget buildCard(ReferenceChangeCard card) {
    return MaterialApp(home: Scaffold(body: card));
  }

  testWidgets('#1 set_primary → 主引用已切换 + 章节标签', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const ReferenceChangeCard(
          action: 'set_primary',
          refType: 'chapter',
          refTitle: '第一章 启程',
        ),
      ),
    );

    expect(find.text('主引用已切换'), findsOneWidget);
    expect(find.text('章节'), findsOneWidget);
    expect(find.text('已切换到「第一章 启程」'), findsOneWidget);
  });

  testWidgets('#2 add → 已添加引用', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const ReferenceChangeCard(
          action: 'add',
          refType: 'manuscript',
          refTitle: '测试小说',
        ),
      ),
    );

    expect(find.text('已添加引用'), findsOneWidget);
    expect(find.text('作品'), findsOneWidget);
    expect(find.text('已添加「测试小说」'), findsOneWidget);
  });

  testWidgets('#3 remove → 已移除引用', (tester) async {
    await tester.pumpWidget(
      buildCard(
        const ReferenceChangeCard(
          action: 'remove',
          refType: 'chapter',
          refTitle: '第二章',
        ),
      ),
    );

    expect(find.text('已移除引用'), findsOneWidget);
    expect(find.text('已移除「第二章」'), findsOneWidget);
  });

  testWidgets('#4 fromMessageContent 合法 JSON → 解析渲染', (tester) async {
    final payload = ReferenceChangeCardPayload(
      action: 'set_primary',
      refType: 'chapter',
      refTitle: '第一章',
    );
    await tester.pumpWidget(
      buildCard(
        ReferenceChangeCard.fromMessageContent(jsonEncode(payload.toJson())),
      ),
    );

    expect(find.text('主引用已切换'), findsOneWidget);
    expect(find.text('已切换到「第一章」'), findsOneWidget);
  });

  testWidgets('#5 fromMessageContent 非法 JSON → 兜底渲染', (tester) async {
    await tester.pumpWidget(
      buildCard(ReferenceChangeCard.fromMessageContent('not-json')),
    );

    // 兜底 action=add → 已添加引用
    expect(find.text('已添加引用'), findsOneWidget);
  });
}
