import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/proficiency_ring.dart';

void main() {
  group('ProficiencyRing 视觉规范（月色竹青）', () {
    testWidgets('#V1 CustomPaint 存在（进度环绘制）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.5,
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('#V2 默认 size=120', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.5,
            ),
          ),
        ),
      );
      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 120);
      expect(sizedBox.height, 120);
    });
  });

  group('ProficiencyRing 等级标签', () {
    testWidgets('#L1 beginner → 显示"新手"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.5,
            ),
          ),
        ),
      );
      expect(find.text('新手'), findsOneWidget);
    });

    testWidgets('#L2 elementary → 显示"入门"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.elementary,
              confidence: 0.6,
            ),
          ),
        ),
      );
      expect(find.text('入门'), findsOneWidget);
    });

    testWidgets('#L3 intermediate → 显示"进阶"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.intermediate,
              confidence: 0.7,
            ),
          ),
        ),
      );
      expect(find.text('进阶'), findsOneWidget);
    });

    testWidgets('#L4 advanced → 显示"熟练"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.advanced,
              confidence: 0.85,
            ),
          ),
        ),
      );
      expect(find.text('熟练'), findsOneWidget);
    });
  });

  group('ProficiencyRing 方案 A 进度语义', () {
    testWidgets('#P1 beginner → progress=0.25（环画 1/4）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.9, // 高置信度，不应影响 progress
            ),
          ),
        ),
      );
      final ring = tester.widget<ProficiencyRing>(find.byType(ProficiencyRing));
      expect(ring.progressForTest, 0.25);
    });

    testWidgets('#P2 elementary → progress=0.5', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.elementary,
              confidence: 0.5,
            ),
          ),
        ),
      );
      final ring = tester.widget<ProficiencyRing>(find.byType(ProficiencyRing));
      expect(ring.progressForTest, 0.5);
    });

    testWidgets('#P3 intermediate → progress=0.75', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.intermediate,
              confidence: 0.4,
            ),
          ),
        ),
      );
      final ring = tester.widget<ProficiencyRing>(find.byType(ProficiencyRing));
      expect(ring.progressForTest, 0.75);
    });

    testWidgets('#P4 advanced → progress=1.0（环满）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.advanced,
              confidence: 0.8,
            ),
          ),
        ),
      );
      final ring = tester.widget<ProficiencyRing>(find.byType(ProficiencyRing));
      expect(ring.progressForTest, 1.0);
    });

    testWidgets('#P5 不显示百分比文本', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.7,
            ),
          ),
        ),
      );
      // 不应出现"50%"或任何 % 文本
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('ProficiencyRing 数据不足', () {
    testWidgets('#D1 confidence < 0.3 → 显示"数据不足"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.0,
            ),
          ),
        ),
      );
      expect(find.text('数据不足'), findsOneWidget);
    });

    testWidgets('#D2 数据不足 → progress=0（环空）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.advanced, // 即使高级
              confidence: 0.1, // 但置信度不足
            ),
          ),
        ),
      );
      final ring = tester.widget<ProficiencyRing>(find.byType(ProficiencyRing));
      expect(ring.progressForTest, 0.0);
    });

    testWidgets('#D3 confidence=0.3 边界 → 不算数据不足', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProficiencyRing(
              level: ProficiencyLevel.beginner,
              confidence: 0.3, // 边界值
            ),
          ),
        ),
      );
      // confidence=0.3 不算不足，应显示等级标签
      expect(find.text('新手'), findsOneWidget);
      expect(find.text('数据不足'), findsNothing);
    });
  });
}
