// ─────────────────────────────────────────────────────────────
// PracticeTaskCard widget 测试 — 练习任务卡片（T3 训练系统）
//
// 覆盖路径：
//   #1 渲染：Header + 症候 chip + 任务描述 + 目标 + 作答输入 + 跳过/提交
//   #2 空作答提交 → 不触发 onSubmit
//   #3 输入作答后提交 → 触发 onSubmit（内容已 trim）
//   #4 点击跳过 → 触发 onSkip
//   #5 submitting=true → 按钮禁用 + 提交中指示器
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/providers/practice_providers.dart';
import 'package:writingcoach/widgets/practice_task_card.dart';

/// 标准练习任务
PracticeTask buildTask() {
  return const PracticeTask(
    syndromeId: 'P003',
    syndromeName: '情绪标签化',
    taskDescription: '找出章节中 3 处情绪标签化表达，改写成动作与感官细节。',
    taskGoal: '对照评估标准：避免直接使用情绪词；用动作/环境侧面烘托',
  );
}

Widget buildCard({
  required void Function(String) onSubmit,
  required VoidCallback onSkip,
  bool submitting = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PracticeTaskCard(
        task: buildTask(),
        submitting: submitting,
        onSubmit: onSubmit,
        onSkip: onSkip,
      ),
    ),
  );
}

void main() {
  group('PracticeTaskCard', () {
    testWidgets('#1 渲染 Header + 症候 chip + 描述 + 目标 + 输入 + 按钮', (tester) async {
      await tester.pumpWidget(buildCard(onSubmit: (_) {}, onSkip: () {}));

      expect(find.text('练习任务'), findsOneWidget);
      expect(find.text('情绪标签化'), findsOneWidget);
      expect(find.text('任务描述'), findsOneWidget);
      expect(find.textContaining('找出章节中 3 处'), findsOneWidget);
      expect(find.text('练习目标'), findsOneWidget);
      expect(find.textContaining('避免直接使用情绪词'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
      expect(find.text('提交作答'), findsOneWidget);
    });

    testWidgets('#2 空作答提交 → 不触发 onSubmit', (tester) async {
      bool submitted = false;
      await tester.pumpWidget(
        buildCard(onSubmit: (_) => submitted = true, onSkip: () {}),
      );

      await tester.tap(find.text('提交作答'));
      await tester.pump();

      expect(submitted, isFalse);
    });

    testWidgets('#3 输入作答后提交 → 触发 onSubmit（trim 后内容）', (tester) async {
      String? submittedContent;
      await tester.pumpWidget(
        buildCard(onSubmit: (c) => submittedContent = c, onSkip: () {}),
      );

      await tester.enterText(find.byType(TextField), '  他攥紧拳头，指节发白。  ');
      await tester.tap(find.text('提交作答'));
      await tester.pump();

      expect(submittedContent, '他攥紧拳头，指节发白。');
    });

    testWidgets('#4 点击跳过 → 触发 onSkip', (tester) async {
      bool skipped = false;
      await tester.pumpWidget(
        buildCard(onSubmit: (_) {}, onSkip: () => skipped = true),
      );

      await tester.tap(find.text('跳过'));
      await tester.pump();

      expect(skipped, isTrue);
    });

    testWidgets('#5 submitting=true → 输入禁用 + 提交按钮显示加载中', (tester) async {
      await tester.pumpWidget(
        buildCard(onSubmit: (_) {}, onSkip: () {}, submitting: true),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
      // 提交中不显示文字按钮（显示 CircularProgressIndicator）
      expect(find.text('提交作答'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
