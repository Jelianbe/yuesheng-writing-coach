// ─────────────────────────────────────────────────────────────
// SyndromeDetailModal widget 测试 — 症候详情弹层
//
// 覆盖路径：
//   1. 完整渲染：症候 chip + 统计行（出现次数/趋势/首次发现）+ 趋势变化 + 诊断记录
//   2. 空记录：无 recentPoints → 暂无趋势数据 / 暂无诊断记录
//   3. 关闭按钮 → 弹层关闭
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/syndrome_tracker.dart';
import 'package:writingcoach/widgets/syndrome_detail_modal.dart';

void main() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  SyndromeTracked makeTracked({
    List<SyndromeTrendPoint> points = const [],
    String currentSeverity = 'L3',
    int occurrenceCount = 3,
    String trend = 'worsening',
  }) {
    return SyndromeTracked(
      syndromeId: 'P003',
      name: '情绪标签化',
      currentSeverity: currentSeverity,
      firstSeen: now - 86400, // 1 天前
      lastSeen: now,
      occurrenceCount: occurrenceCount,
      trend: trend,
      recentPoints: points,
    );
  }

  Future<void> openModal(WidgetTester tester, SyndromeTracked tracked) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SyndromeDetailModal(syndrome: tracked),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('#1 完整渲染：chip/统计/趋势/记录', (tester) async {
    final tracked = makeTracked(
      points: [
        SyndromeTrendPoint(
          timestamp: now - 3600,
          severity: 'L1',
          diagnosisId: 'd1',
        ),
        SyndromeTrendPoint(timestamp: now, severity: 'L3', diagnosisId: 'd2'),
      ],
    );

    await openModal(tester, tracked);

    // 症候 chip
    expect(find.text('情绪标签化'), findsOneWidget);
    expect(find.text('L3'), findsOneWidget);

    // 统计行
    expect(find.text('出现次数'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('趋势'), findsOneWidget);
    expect(find.text('加重'), findsOneWidget); // trend=worsening
    expect(find.text('首次发现'), findsOneWidget);
    expect(find.text('1 天前'), findsOneWidget); // formatRelativeTime(now-86400)

    // 趋势变化 section + 图例
    expect(find.text('趋势变化'), findsOneWidget);
    expect(find.text('最近 2 次诊断'), findsOneWidget);

    // 诊断记录 section：严重度标签
    expect(find.text('诊断记录'), findsOneWidget);
    expect(find.text('轻微'), findsOneWidget); // L1
    expect(find.text('严重'), findsOneWidget); // L3
  });

  testWidgets('#2 空记录 → 暂无趋势数据 / 暂无诊断记录', (tester) async {
    final tracked = makeTracked(points: const [], occurrenceCount: 1);

    await openModal(tester, tracked);

    expect(find.text('暂无趋势数据'), findsOneWidget);
    expect(find.text('暂无诊断记录'), findsOneWidget);
  });

  testWidgets('#3 关闭按钮 → 弹层关闭', (tester) async {
    final tracked = makeTracked(points: const []);

    await openModal(tester, tracked);
    expect(find.text('情绪标签化'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('情绪标签化'), findsNothing);
  });
}
