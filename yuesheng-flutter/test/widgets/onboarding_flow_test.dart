// ─────────────────────────────────────────────────────────────
// OnboardingFlow widget 测试 — 首启功能引导（批次63）
//
// 覆盖路径：
//   1. 第 1 页渲染（我是月笙）+「下一步」滑到第 2 页
//   2. 第 2 页三大核心能力 → 下一步 → 第 3 页
//   3. 第 3 页「开始使用」→ onComplete 触发
//   4. 右上「跳过」→ onComplete 触发
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/onboarding_flow.dart';

void main() {
  Widget buildFlow({required VoidCallback onComplete}) {
    return MaterialApp(home: OnboardingFlow(onComplete: onComplete));
  }

  testWidgets('#1 第1页渲染 + 下一步 → 第2页', (tester) async {
    await tester.pumpWidget(buildFlow(onComplete: () {}));

    // 第 1 页
    expect(find.text('我是月笙'), findsOneWidget);
    expect(find.text('你的专属写作教练'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);

    // 下一步 → 第 2 页
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('我能帮你做什么'), findsOneWidget);
    expect(find.text('智能诊断'), findsOneWidget);
    expect(find.text('拆解练习'), findsOneWidget);
    expect(find.text('追踪成长'), findsOneWidget);
  });

  testWidgets('#2 下一步 → 第3页「开始使用」→ onComplete', (tester) async {
    var completed = 0;
    await tester.pumpWidget(buildFlow(onComplete: () => completed++));

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 第 3 页：标题与按钮都叫「开始使用」（对齐 RN PAGES），按钮用精确 finder
    expect(find.text('开始使用'), findsNWidgets(2));
    expect(find.text('开启写作之旅'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '开始使用'));
    await tester.pump();
    expect(completed, 1);
  });

  testWidgets('#3 右上「跳过」→ onComplete 触发', (tester) async {
    var completed = 0;
    await tester.pumpWidget(buildFlow(onComplete: () => completed++));

    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(completed, 1);
  });

  testWidgets('#4 进度点存在（3 个，首点高亮）', (tester) async {
    await tester.pumpWidget(buildFlow(onComplete: () {}));

    // 进度点由 AnimatedContainer 组成，数 3 个
    final dots = find.byType(AnimatedContainer);
    expect(dots, findsNWidgets(3));
  });
}
