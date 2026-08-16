// ─────────────────────────────────────────────────────────────
// TeachingStateBadge widget 测试 — 教学状态徽章
//
// 覆盖路径：
//   1. identified → 刚识别
//   2. in_progress → 训练中
//   3. consolidating → 趋稳中
//   4. mastered → 已掌握
//   5. showLabel=false → 只渲染色点（无文字）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/teaching_state_badge.dart';

void main() {
  Widget buildBadge(TeachingState state, {bool showLabel = true}) {
    return MaterialApp(
      home: Scaffold(
        body: TeachingStateBadge(state: state, showLabel: showLabel),
      ),
    );
  }

  testWidgets('#1 identified → 刚识别', (tester) async {
    await tester.pumpWidget(buildBadge(TeachingState.identified));

    expect(find.text('刚识别'), findsOneWidget);
  });

  testWidgets('#2 in_progress → 训练中', (tester) async {
    await tester.pumpWidget(buildBadge(TeachingState.inProgress));

    expect(find.text('训练中'), findsOneWidget);
  });

  testWidgets('#3 consolidating → 趋稳中', (tester) async {
    await tester.pumpWidget(buildBadge(TeachingState.consolidating));

    expect(find.text('趋稳中'), findsOneWidget);
  });

  testWidgets('#4 mastered → 已掌握', (tester) async {
    await tester.pumpWidget(buildBadge(TeachingState.mastered));

    expect(find.text('已掌握'), findsOneWidget);
  });

  testWidgets('#5 showLabel=false → 无文字标签', (tester) async {
    await tester.pumpWidget(
      buildBadge(TeachingState.identified, showLabel: false),
    );

    expect(find.text('刚识别'), findsNothing);
  });
}
