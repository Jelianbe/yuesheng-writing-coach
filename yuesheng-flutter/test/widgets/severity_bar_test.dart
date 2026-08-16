import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/widgets/severity_bar.dart';

void main() {
  group('SeverityBar', () {
    testWidgets('#1 渲染 3 段色块（L1/L2/L3 各 1 个）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 1, l2: 1, l3: 1)),
          ),
        ),
      );

      // 验证 3 个色块 Container（排除外层）
      final blocks = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color != null,
        ),
      );
      expect(blocks.length, 3);
    });

    testWidgets('#2 L1 色块 = #E8F0EE', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 2, l2: 0, l3: 0)),
          ),
        ),
      );

      final l1Block = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFE8F0EE),
        ),
      );
      expect(l1Block.length, 1); // 合并为 1 段，宽度按比例
    });

    testWidgets('#3 L2 色块 = #F5E6B8', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 0, l2: 1, l3: 0)),
          ),
        ),
      );

      final l2Block = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFF5E6B8),
        ),
      );
      expect(l2Block.length, 1);
    });

    testWidgets('#4 L3 色块 = #E8C5C5', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 0, l2: 0, l3: 1)),
          ),
        ),
      );

      final l3Block = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFE8C5C5),
        ),
      );
      expect(l3Block.length, 1);
    });

    testWidgets('#5 全 0 → 渲染空状态占位（灰底）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeverityBar(counts: SeverityCounts(l1: 0, l2: 0, l3: 0)),
          ),
        ),
      );

      // 空状态：1 个灰色 Container
      final emptyBlock = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFE0E4E0),
        ),
      );
      expect(emptyBlock.length, 1);
    });

    testWidgets('#6 比例正确：L1=2,L2=1,L3=1 → 总 4 份，L1 占 50%', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: SeverityBar(counts: SeverityCounts(l1: 2, l2: 1, l3: 1)),
            ),
          ),
        ),
      );

      // L1 段宽度 = 400 * 2/4 = 200
      // 用 Flex 或 Expanded 的 flex 验证比例
      final expanded = tester
          .widgetList<Expanded>(find.byType(Expanded))
          .toList();
      expect(expanded.length, 3); // 3 段
      expect(expanded[0].flex, 2); // L1 flex=2
      expect(expanded[1].flex, 1); // L2 flex=1
      expect(expanded[2].flex, 1); // L3 flex=1
    });
  });
}
