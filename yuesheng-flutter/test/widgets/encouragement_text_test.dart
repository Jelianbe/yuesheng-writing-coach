// ─────────────────────────────────────────────────────────────
// EncouragementText widget 测试 — 教练鼓励文案
//
// 覆盖路径：
//   1. 固定 text 直接显示
//   2. seed 稳定随机（同一 seed 结果一致）
//   3. 15 条文案池全覆盖（seed 0..14 各不相同）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/encouragement_text.dart';

void main() {
  Widget buildText(EncouragementText text) {
    return MaterialApp(home: Scaffold(body: text));
  }

  testWidgets('#1 固定 text 直接显示', (tester) async {
    await tester.pumpWidget(buildText(const EncouragementText(text: '固定鼓励文案')));

    expect(find.text('固定鼓励文案'), findsOneWidget);
  });

  testWidgets('#2 seed 稳定随机（同一 seed 结果一致）', (tester) async {
    await tester.pumpWidget(buildText(const EncouragementText(seed: 3)));

    expect(find.text(getEncouragementBySeed(3)), findsOneWidget);
  });

  testWidgets('#3 15 条文案池全覆盖（seed 0..14 各不相同）', (tester) async {
    final texts = <String>{};
    for (var i = 0; i < encouragements.length; i++) {
      texts.add(getEncouragementBySeed(i));
    }
    expect(texts.length, encouragements.length);
  });
}
