// ThinkingChain 组件测试（批次 C 竹青化）
//
// 覆盖：
//   #1 默认折叠：显示标题 + 步骤数徽标，不显示步骤内容
//   #2 展开：显示步骤 label / detail / 编号
//   #3 置信点：confidence 非空时渲染置信点；null 时不渲染
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/thinking_chain.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _steps = [
  ThinkingStep(label: '文本分析', detail: '扫描文本，定位 6 处问题片段'),
  ThinkingStep(label: '症候匹配', detail: '匹配 情绪标签化、视角漂移'),
  ThinkingStep(label: '建议生成', detail: '生成 2 条改写建议', confidence: 0.8),
];

void main() {
  group('ThinkingChain 折叠/展开', () {
    testWidgets('#1 默认折叠：标题 + 徽标可见，步骤内容不可见', (tester) async {
      await tester.pumpWidget(
        _wrap(const ThinkingChain(title: '诊断依据', steps: _steps)),
      );

      expect(find.text('诊断依据'), findsOneWidget);
      expect(find.text('3 步'), findsOneWidget);
      // 折叠态：步骤 label 不可见
      expect(find.text('文本分析'), findsNothing);
      expect(find.text('建议生成'), findsNothing);
    });

    testWidgets('#2 点击 header 展开：步骤 label/detail/编号可见', (tester) async {
      await tester.pumpWidget(
        _wrap(const ThinkingChain(title: '诊断依据', steps: _steps)),
      );

      await tester.tap(find.text('诊断依据'));
      await tester.pumpAndSettle();

      expect(find.text('文本分析'), findsOneWidget);
      expect(find.text('扫描文本，定位 6 处问题片段'), findsOneWidget);
      expect(find.text('症候匹配'), findsOneWidget);
      expect(find.text('建议生成'), findsOneWidget);
      expect(find.text('生成 2 条改写建议'), findsOneWidget);
      // 编号 1/2/3
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('#3 置信点：confidence 非空渲染，null 不渲染', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ThinkingChain(
            title: '诊断依据',
            steps: _steps,
            initiallyExpanded: true,
          ),
        ),
      );

      // confidence=0.8 的步骤渲染置信点（3 颗圆点），其余步骤不渲染
      // 断言方式：Container 圆点数量——通过 find.byWidgetPredicate
      final dots = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      );
      final confidenceDots = dots.where((c) {
        final deco = c.decoration! as BoxDecoration;
        return deco.shape == BoxShape.circle &&
            (c.constraints?.maxWidth ?? 0) <= 4.1;
      });
      // 3 步中仅 1 步有置信点 → 恰好 3 颗
      expect(confidenceDots.length, 3);
    });
  });

  group('ThinkingChain 初始展开', () {
    testWidgets('#4 initiallyExpanded=true 直接显示步骤', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ThinkingChain(
            title: '诊断依据',
            steps: _steps,
            initiallyExpanded: true,
          ),
        ),
      );

      expect(find.text('文本分析'), findsOneWidget);
      expect(find.text('症候匹配'), findsOneWidget);
    });
  });
}
