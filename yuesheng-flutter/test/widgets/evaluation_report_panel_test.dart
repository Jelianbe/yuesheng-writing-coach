// ─────────────────────────────────────────────────────────────
// EvaluationReportPanel widget 测试 — 训练评估报告面板
//
// 覆盖路径：
//   1. 渲染 header：趋势徽章 + 达标率
//   2. 展开详情：训练次数 / 达标率 / 严重度变化 + 趋势文案
//   3. 症候明细渲染
//   4. 关闭回调触发
//   5. 点击 header 收起/展开
//   6. E-1 复诊行：复诊渲染 / 首次不渲染 / 同严重度 / 无基线
//   7. E1-b② 成长记录入口：渲染 / 点击触发 / 未接线不渲染 / 与关闭并存
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

/// E-1 复诊夹具：单个症候，可指定复发字段。
EvaluationData _recurringReport({
  required int occurrences,
  int recurrences = 0,
  Severity? previousSeverity,
  EvaluationTrend trend = EvaluationTrend.improving,
  String summaryText = '整体进步明显，继续保持',
}) {
  return EvaluationData(
    round: 0,
    trend: trend,
    trainingCount: 3,
    passRate: 0.8,
    severityDelta: -1,
    summaryText: summaryText,
    syndromeDetails: [
      SyndromeEvaluationDetail(
        syndromeId: 's1',
        syndromeName: '叙事含糊',
        currentSeverity: Severity.l2,
        teachingState: TeachingState.inProgress,
        passCount: 2,
        totalCount: 3,
        trend: trend,
        occurrences: occurrences,
        recurrences: recurrences,
        previousSeverity: previousSeverity,
      ),
    ],
    generatedAt: 1700000000,
  );
}

Widget _wrap(
  EvaluationData report, {
  VoidCallback? onDismiss,
  VoidCallback? onOpenGrowth,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EvaluationReportPanel(
        evaluation: report,
        onDismiss: onDismiss,
        onOpenGrowth: onOpenGrowth,
      ),
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

    // ── E-1 复诊行 ──

    testWidgets('#8 复诊症候 → 渲染复诊行（第 N 次出现 + 严重度对比）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _recurringReport(
            occurrences: 3,
            recurrences: 2,
            previousSeverity: Severity.l3,
            summaryText: '整体进步明显，继续保持。叙事含糊 已第 3 次出现（其中再犯 2 次）',
          ),
        ),
      );

      // 复诊行：出现次数 + 「较上次 L3 → L2」严重度对比（summaryText 未提供的信息）
      expect(find.text('第 3 次出现 · 较上次 L3 → L2'), findsOneWidget);
      // 历史图标标识该行是「复诊」元信息
      expect(find.byIcon(Icons.history), findsOneWidget);
      // 行内小字与 summaryText 全局叙事并存，两者措辞不同（不重复）
      expect(find.textContaining('已第 3 次出现'), findsOneWidget);
    });

    testWidgets('#9 首次出现（非复诊）→ 不渲染复诊行', (tester) async {
      await tester.pumpWidget(_wrap(_report()));

      expect(find.byIcon(Icons.history), findsNothing);
      expect(find.textContaining('次出现'), findsNothing);
    });

    testWidgets('#10 复诊且与上次严重度相同 → 「与上次同为 L2」', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _recurringReport(
            occurrences: 2,
            previousSeverity: Severity.l2,
            trend: EvaluationTrend.stable,
            summaryText: '表现稳定，持续练习。叙事含糊 已第 2 次出现',
          ),
        ),
      );

      expect(find.text('第 2 次出现 · 与上次同为 L2'), findsOneWidget);
    });

    testWidgets('#11 复诊但无上次严重度基线 → 仅渲染次数', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _recurringReport(
            occurrences: 2,
            summaryText: '整体进步明显，继续保持。叙事含糊 已第 2 次出现',
          ),
        ),
      );

      expect(find.text('第 2 次出现'), findsOneWidget);
      expect(find.textContaining('上次'), findsNothing);
    });

    // ── E1-b② 成长记录入口（③「与成长页趋势贯通」）──

    testWidgets('#12 onOpenGrowth 非空 → 渲染「查看成长记录」并点击触发', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _wrap(_report(), onOpenGrowth: () => opened = true),
      );

      expect(find.text('查看成长记录'), findsOneWidget);
      expect(find.byIcon(Icons.insights_outlined), findsOneWidget);

      await tester.tap(find.text('查看成长记录'));
      await tester.pump();

      expect(opened, isTrue);
    });

    testWidgets('#13 onOpenGrowth 为空 → 不渲染入口（不留死按钮）', (tester) async {
      await tester.pumpWidget(_wrap(_report()));

      expect(find.text('查看成长记录'), findsNothing);
      expect(find.byIcon(Icons.insights_outlined), findsNothing);
      // 关闭按钮不受影响，动作区不因缺少主入口而消失
      expect(find.text('关闭'), findsOneWidget);
    });

    testWidgets('#14 入口与关闭并存：两者互不干扰', (tester) async {
      var opened = false;
      var dismissed = false;
      await tester.pumpWidget(
        _wrap(
          _report(),
          onOpenGrowth: () => opened = true,
          onDismiss: () => dismissed = true,
        ),
      );

      await tester.tap(find.text('查看成长记录'));
      await tester.pump();
      expect(opened, isTrue);
      expect(dismissed, isFalse);

      await tester.tap(find.text('关闭'));
      await tester.pump();
      expect(dismissed, isTrue);
    });

    testWidgets('#15 收起详情 → 动作区随详情隐藏（入口显隐与关闭一致）', (tester) async {
      await tester.pumpWidget(_wrap(_report(), onOpenGrowth: () {}));
      expect(find.text('查看成长记录'), findsOneWidget);

      await tester.tap(find.text('达标率 80%'));
      await tester.pump();

      expect(find.text('查看成长记录'), findsNothing);
      expect(find.text('关闭'), findsNothing);
    });
  });
}
