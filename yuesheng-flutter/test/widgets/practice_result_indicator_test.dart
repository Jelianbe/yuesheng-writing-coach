// ─────────────────────────────────────────────────────────────
// PracticeResultIndicator widget 测试 — 练习结果指示器（T3 训练系统）
//
// 覆盖路径：
//   #1 passed → 达标文案（竹青）
//   #2 partial → 部分达标文案
//   #3 failed → 未达标文案 + 「再试一次」按钮（onRetry 非空时）
//   #4 点击「关闭」→ 触发 onDismiss
//   #5 details 非空 → 展示详情文本
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/practice_result_indicator.dart';

Widget buildResult({
  required TrainingResult result,
  String? details,
  VoidCallback? onDismiss,
  VoidCallback? onRetry,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PracticeResultIndicator(
        result: result,
        details: details,
        onDismiss: onDismiss,
        onRetry: onRetry,
      ),
    ),
  );
}

void main() {
  group('PracticeResultIndicator', () {
    testWidgets('#1 passed → 达标文案', (tester) async {
      await tester.pumpWidget(
        buildResult(result: TrainingResult.passed, onDismiss: () {}),
      );

      expect(find.textContaining('达标'), findsOneWidget);
      expect(find.text('再试一次'), findsNothing);
    });

    testWidgets('#2 partial → 部分达标文案', (tester) async {
      await tester.pumpWidget(
        buildResult(result: TrainingResult.partial, onDismiss: () {}),
      );

      expect(find.textContaining('部分达标'), findsOneWidget);
      expect(find.text('再试一次'), findsNothing);
    });

    testWidgets('#3 failed + onRetry → 未达标文案 + 再试一次按钮', (tester) async {
      await tester.pumpWidget(
        buildResult(
          result: TrainingResult.failed,
          onDismiss: () {},
          onRetry: () {},
        ),
      );

      expect(find.textContaining('未达标'), findsOneWidget);
      expect(find.text('再试一次'), findsOneWidget);
    });

    testWidgets('#4 点击关闭 → 触发 onDismiss', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        buildResult(
          result: TrainingResult.passed,
          onDismiss: () => dismissed = true,
        ),
      );

      await tester.tap(find.text('关闭'));
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('#5 details 非空 → 展示详情文本', (tester) async {
      await tester.pumpWidget(
        buildResult(
          result: TrainingResult.passed,
          details: '你成功替换了 3 处情绪词。',
          onDismiss: () {},
        ),
      );

      expect(find.text('你成功替换了 3 处情绪词。'), findsOneWidget);
    });
  });
}
