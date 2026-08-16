// ─────────────────────────────────────────────────────────────
// SubphaseIndicator widget 测试 — P2 子阶段胶囊
//
// 覆盖路径：
//   1. DIAGNOSIS → 诊断中
//   2. PRACTICE → 练习中
//   3. FEEDBACK → 反馈中
//   4. null → 不渲染
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/subphase_indicator.dart';

void main() {
  Widget buildIndicator(TeachingSubphase? subphase) {
    return MaterialApp(
      home: Scaffold(body: SubphaseIndicator(subphase: subphase)),
    );
  }

  testWidgets('#1 DIAGNOSIS → 诊断中', (tester) async {
    await tester.pumpWidget(buildIndicator(TeachingSubphase.diagnosis));

    expect(find.text('诊断中'), findsOneWidget);
  });

  testWidgets('#2 PRACTICE → 练习中', (tester) async {
    await tester.pumpWidget(buildIndicator(TeachingSubphase.practice));

    expect(find.text('练习中'), findsOneWidget);
  });

  testWidgets('#3 FEEDBACK → 反馈中', (tester) async {
    await tester.pumpWidget(buildIndicator(TeachingSubphase.feedback));

    expect(find.text('反馈中'), findsOneWidget);
  });

  testWidgets('#4 null → 不渲染', (tester) async {
    await tester.pumpWidget(buildIndicator(null));

    expect(find.text('诊断中'), findsNothing);
    expect(find.text('练习中'), findsNothing);
    expect(find.text('反馈中'), findsNothing);
  });
}
