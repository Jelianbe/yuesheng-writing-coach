// ConfidenceBar 组件测试（批次 C 竹青化：Knowledge Card 置信条）
//
// 覆盖：
//   #1 渲染 label + 百分比
//   #2 百分比四舍五入正确（0.753 → 75%）
//   #3 填充宽度按 value 比例（FractionallySizedBox.widthFactor）
//   #4 label 可省略
//   #5 value 越界 clamp 到 [0,1]
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/knowledge_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ConfidenceBar', () {
    testWidgets('#1 渲染 label 与百分比', (tester) async {
      await tester.pumpWidget(
        _wrap(const ConfidenceBar(label: '诊断信心', value: 0.8)),
      );

      expect(find.text('诊断信心'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
    });

    testWidgets('#2 百分比四舍五入', (tester) async {
      await tester.pumpWidget(
        _wrap(const ConfidenceBar(label: '诊断信心', value: 0.753)),
      );

      expect(find.text('75%'), findsOneWidget);
      expect(find.text('76%'), findsNothing);
    });

    testWidgets('#3 填充宽度按 value 比例', (tester) async {
      await tester.pumpWidget(
        _wrap(const ConfidenceBar(label: '诊断信心', value: 0.25)),
      );

      final fraction = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fraction.widthFactor, closeTo(0.25, 0.001));
    });

    testWidgets('#4 label 可省略', (tester) async {
      await tester.pumpWidget(_wrap(const ConfidenceBar(value: 0.5)));

      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('诊断信心'), findsNothing);
    });

    testWidgets('#5 value 越界 clamp 到 [0,1]', (tester) async {
      await tester.pumpWidget(
        _wrap(const ConfidenceBar(label: '诊断信心', value: 1.6)),
      );

      final fraction = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fraction.widthFactor, 1.0);
      // 展示层同样 clamp，避免出现超 100% 的荒谬展示
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('160%'), findsNothing);
    });
  });
}
