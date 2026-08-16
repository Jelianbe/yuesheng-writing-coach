// ─────────────────────────────────────────────────────────────
// 成长组件单元测试（批次 51b）— GrowthOverviewCard / AbilityChart /
// WritingCurveChart / SyndromeHistoryList
//
// 覆盖路径：
//   1. GrowthOverviewCard：三统计渲染 + 字数格式化 + 详情链接回调
//   2. AbilityChart：空态 / 六行渲染（分数/趋势/描述）
//   3. WritingCurveChart：空态 / 摘要行 + 图例 + 今天标签
//   4. SyndromeHistoryList：空态 / 发现/解决徽章 + 严重度 + limit
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/services/growth_service.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/ability_chart.dart';
import 'package:writingcoach/widgets/growth_overview_card.dart';
import 'package:writingcoach/widgets/syndrome_history_list.dart';
import 'package:writingcoach/widgets/writing_curve_chart.dart';

void main() {
  group('GrowthOverviewCard', () {
    testWidgets('#1 三统计 + 字数格式化 + 详情链接回调', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GrowthOverviewCard(
              totalWords: 12000,
              diagnosisCount: 8,
              resolvedCount: 3,
              onViewDetail: () => tapped = true,
            ),
          ),
        ),
      );

      // 字数格式化：12000 → 1.2万字
      expect(find.text('1.2万字'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('累计创作'), findsOneWidget);
      expect(find.text('诊断次数'), findsOneWidget);
      expect(find.text('已解决问题'), findsOneWidget);
      expect(find.text('诊断历史 / 成长详情'), findsOneWidget);

      await tester.tap(find.text('诊断历史 / 成长详情'));
      expect(tapped, isTrue);
    });

    testWidgets('#2 千位分隔符 + 无回调不显示链接', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GrowthOverviewCard(
              totalWords: 3256,
              diagnosisCount: 0,
              resolvedCount: 0,
            ),
          ),
        ),
      );

      expect(find.text('3,256字'), findsOneWidget);
      expect(find.text('诊断历史 / 成长详情'), findsNothing);
    });
  });

  group('AbilityChart', () {
    testWidgets('#3 空数据 → 空态文案', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AbilityChart(scores: const [])),
        ),
      );

      expect(find.text('能力图谱'), findsOneWidget);
      // 批次55：分层认知显式化（整体/表达两个层面）
      expect(find.text('从整体（情节/人物/结构）与表达（语言/细节）两个层面评估的六大写作能力'), findsOneWidget);
      expect(find.text('暂无能力数据'), findsOneWidget);
    });

    testWidgets('#4 六行渲染：维度/描述/分数/趋势', (tester) async {
      const scores = [
        AbilityScore(
          dimension: '情节构建',
          score: 80,
          trend: Trend.improving,
          description: '故事结构、节奏与冲突',
        ),
        AbilityScore(
          dimension: '语言表达',
          score: 45,
          trend: Trend.worsening,
          description: '用词、句式与节奏',
        ),
        AbilityScore(
          dimension: '逻辑连贯',
          score: 60,
          trend: Trend.stable,
          description: '因果关系与衔接',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AbilityChart(scores: scores)),
        ),
      );

      expect(find.text('情节构建'), findsOneWidget);
      expect(find.text('故事结构、节奏与冲突'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('↑'), findsOneWidget);
      expect(find.text('↓'), findsOneWidget);
      expect(find.text('→'), findsOneWidget);
    });

    test('#4b 分数/趋势色走月色竹青令牌（批次22 UI 打磨：无 Material 硬编码绿）', () {
      // 分数着色：≥80 正向绿（AppColors.success），非 Material 绿
      expect(AbilityChart.scoreColor(85), AppColors.success);
      expect(AbilityChart.scoreColor(80), AppColors.success);
      expect(AbilityChart.scoreColor(79), AppColors.primary);
      expect(AbilityChart.scoreColor(60), AppColors.primary);
      expect(AbilityChart.scoreColor(59), AppColors.warning);
      expect(AbilityChart.scoreColor(45), AppColors.warning);
      expect(AbilityChart.scoreColor(44), AppColors.danger);
      // 趋势箭头：improving 正向绿，worsening 矿物红
      expect(AbilityChart.trendGlyph(Trend.improving).$2, AppColors.success);
      expect(AbilityChart.trendGlyph(Trend.worsening).$2, AppColors.danger);
      expect(AbilityChart.trendGlyph(Trend.stable).$2, AppColors.textTertiary);
      // 全库不得再出现 Material 默认绿硬编码
      final source = AbilityChart.scoreColor(85).toString();
      expect(source.contains('2E7D32'), isFalse);
    });
  });

  group('WritingCurveChart', () {
    testWidgets('#5 空数据 → 空态文案', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WritingCurveChart(points: const [])),
        ),
      );

      expect(find.text('写作成长曲线'), findsOneWidget);
      expect(find.text('暂无写作记录'), findsOneWidget);
    });

    testWidgets('#6 摘要行 + 今天标签 + 图例', (tester) async {
      final nowUtc = DateTime.now().toUtc();
      final todayStr = _dateStr(nowUtc);
      final yesterday = nowUtc.subtract(const Duration(days: 1));
      final points = [
        WritingDataPoint(
          date: _dateStr(yesterday),
          timestamp: 0,
          wordCount: 800,
          diagnosisCount: 1,
        ),
        WritingDataPoint(
          date: todayStr,
          timestamp: 1,
          wordCount: 1200,
          diagnosisCount: 2,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WritingCurveChart(points: points)),
        ),
      );

      // 摘要行：总字数 2000（2,000字）/ 诊断 3 / 活跃天数 2
      expect(find.text('2,000字'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // "2" 出现两处：活跃天数 + 第二个点的诊断次数徽标
      expect(find.text('2'), findsNWidgets(2));
      expect(find.text('字数'), findsWidgets);
      expect(find.text('诊断'), findsWidgets);
      expect(find.text('活跃天数'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
    });
  });

  group('SyndromeHistoryList', () {
    testWidgets('#7 空数据 → 空态文案', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SyndromeHistoryList(events: const [])),
        ),
      );

      expect(find.text('症候追踪历史'), findsOneWidget);
      expect(find.text('暂无症候记录'), findsOneWidget);
    });

    testWidgets('#8 发现/解决徽章 + 严重度 + limit 提示', (tester) async {
      final events = [
        const SyndromeHistoryEvent(
          syndromeId: 's1',
          syndromeName: '情节断裂',
          severity: Severity.l3,
          eventType: 'resolved',
          timestamp: 1000,
          sessionId: 'sess',
        ),
        const SyndromeHistoryEvent(
          syndromeId: 's2',
          syndromeName: '情绪标签化',
          severity: Severity.l2,
          eventType: 'detected',
          timestamp: 500,
          sessionId: 'sess',
        ),
        const SyndromeHistoryEvent(
          syndromeId: 's3',
          syndromeName: '对话生硬',
          severity: Severity.l1,
          eventType: 'detected',
          timestamp: 100,
          sessionId: 'sess',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SyndromeHistoryList(events: events, limit: 2)),
        ),
      );

      // limit=2 → 只显示前 2 条 + 共 N 条提示
      expect(find.text('解决'), findsOneWidget);
      expect(find.text('发现'), findsOneWidget);
      expect(find.text('严重'), findsOneWidget);
      expect(find.text('中等'), findsOneWidget);
      expect(find.text('共 3 条记录'), findsOneWidget);
      expect(find.text('对话生硬'), findsNothing);
    });
  });
}

String _dateStr(DateTime utc) {
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}
