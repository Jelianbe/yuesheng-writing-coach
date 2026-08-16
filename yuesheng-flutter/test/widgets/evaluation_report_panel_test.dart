// ─────────────────────────────────────────────────────────────
// EvaluationReportPanel widget 测试 — 训练评估报告面板
//
// 覆盖路径：
//   1. 渲染 header：趋势徽章 + 达标率
//   2. 展开详情：训练次数 / 达标率 / 严重度变化 + 趋势文案
//   3. 症候明细渲染
//   4. 关闭回调触发
//   5. 点击 header 收起/展开
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/types/display_types.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/evaluation_report_panel.dart';

EvaluationData _report({
  EvaluationTrend trend = EvaluationTrend.improving,
  bool withSeverityDelta = true,
  bool withSyndromes = true,
}) {
  return EvaluationData(
    round: 0,
    trend: trend,
    trainingCount: 3,
    passRate: 0.8,
    severityDelta: withSeverityDelta ? -1 : null,
    summaryText: '整体进步明显，继续保持',
    syndromeDetails: withSyndromes
        ? [
            SyndromeEvaluationDetail(
              syndromeId: 's1',
              syndromeName: '叙事含糊',
              currentSeverity: Severity.l2,
              teachingState: TeachingState.inProgress,
              passCount: 2,
              totalCount: 3,
              trend: EvaluationTrend.improving,
            ),
          ]
        : const [],
    generatedAt: 1700000000,
  );
}

Widget _wrap(EvaluationData report, {VoidCallback? onDismiss}) {
  return MaterialApp(
    home: Scaffold(
      body: EvaluationReportPanel(evaluation: report, onDismiss: onDismiss),
    ),
  );
}

void main() {
  group('EvaluationReportPanel', () {
    testWidgets('#1 渲染 header：趋势徽章 + 达标率', (tester) async {
      await tester.pumpWidget(_wrap(_report()));

      // 「改善」出现 2 处：header 趋势徽章 + 症候明细趋势
      expect(find.text('改善'), findsNWidgets(2));
      expect(find.text('达标率 80%'), findsOneWidget);
    });

    testWidgets('#2 展开详情：训练次数 / 达标率 / 严重度变化 + 趋势文案', (tester) async {
      await tester.pumpWidget(_wrap(_report()));

      expect(find.text('3'), findsOneWidget);
      expect(find.text('训练次数'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('达标率'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
      expect(find.text('严重度变化'), findsOneWidget);
      expect(find.text('整体进步明显，继续保持'), findsOneWidget);
    });

    testWidgets('#3 症候明细渲染', (tester) async {
      await tester.pumpWidget(_wrap(_report()));

      expect(find.text('症候明细'), findsOneWidget);
      expect(find.text('叙事含糊'), findsOneWidget);
      expect(find.text('达标 2/3 · 严重度 L2'), findsOneWidget);
      // 教学状态徽章（inProgress → 「训练中」）——训练反馈感知阶段迁移
      expect(find.text('训练中'), findsOneWidget);
    });

    testWidgets('#3b 症候教学状态徽章：identified/consolidating 标签渲染', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvaluationData(
            round: 0,
            trend: EvaluationTrend.improving,
            trainingCount: 3,
            passRate: 0.8,
            severityDelta: -1,
            summaryText: '整体进步明显，继续保持',
            syndromeDetails: [
              SyndromeEvaluationDetail(
                syndromeId: 's1',
                syndromeName: '叙事含糊',
                currentSeverity: Severity.l2,
                teachingState: TeachingState.identified,
                passCount: 2,
                totalCount: 3,
                trend: EvaluationTrend.improving,
              ),
              SyndromeEvaluationDetail(
                syndromeId: 's2',
                syndromeName: '对话无区分度',
                currentSeverity: Severity.l1,
                teachingState: TeachingState.consolidating,
                passCount: 3,
                totalCount: 3,
                trend: EvaluationTrend.improving,
              ),
            ],
            generatedAt: 1700000000,
          ),
        ),
      );

      expect(find.text('刚识别'), findsOneWidget);
      expect(find.text('趋稳中'), findsOneWidget);
    });

    testWidgets('#4 点击关闭 → onDismiss 触发', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        _wrap(_report(), onDismiss: () => dismissed = true),
      );

      await tester.tap(find.text('关闭'));
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('#5 点击 header 收起/展开', (tester) async {
      await tester.pumpWidget(_wrap(_report()));
      expect(find.text('训练次数'), findsOneWidget);

      // 点击 header 收起（用 header 唯一的「达标率」文本定位）
      await tester.tap(find.text('达标率 80%'));
      await tester.pump();
      expect(find.text('训练次数'), findsNothing);

      // 再点展开
      await tester.tap(find.text('达标率 80%'));
      await tester.pump();
      expect(find.text('训练次数'), findsOneWidget);
    });

    testWidgets('#6 无严重度变化 → 不显示该项', (tester) async {
      await tester.pumpWidget(_wrap(_report(withSeverityDelta: false)));

      expect(find.text('严重度变化'), findsNothing);
    });

    testWidgets('#7 达标率进度条渲染（值随 passRate + 展开时可见）', (tester) async {
      await tester.pumpWidget(_wrap(_report()));

      // 展开态：进度条存在且值 = 0.8
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.8, 0.001));
      expect(bar.minHeight, 6);

      // 收起后进度条隐藏（详情区收起）
      await tester.tap(find.text('达标率 80%'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
