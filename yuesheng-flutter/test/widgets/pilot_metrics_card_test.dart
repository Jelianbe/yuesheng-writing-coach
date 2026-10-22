// pilot_metrics_card_test — 「引文锚定」卡 widget 挂载测试
// （T-20261018-06 · D 议题 · 设计批 §六 测试计划 9~12；
//   对齐 T-20261018-03 growth_narrative_card_test 先例）
//
// 覆盖（R-027 五条逐字 + 隐私端到端边界）：
//   #W1 有数据 ⇒ 卡题/说明/数值行/隐私注记逐字渲染
//   #W2 零引文（有记录）⇒ 空态文案④ + 不出「0%」假读数
//   #W3 隐私边界端到端：payload 含引文原文哨兵 ⇒ 经纯函数装配后挂卡，
//        UI 树找不到哨兵串（原文结构上到不了 UI）
//   #W4 卡文案无 syndromeId / 无 R-009 评价词黑名单

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/features/growth/pilot_metrics_card.dart';
import 'package:writingcoach/services/pilot_metrics_summary.dart';

Widget buildCard(PilotMetricsSummary summary) {
  return MaterialApp(
    home: Scaffold(body: PilotMetricsCard(summary: summary)),
  );
}

void main() {
  group('T-20261018-06「引文锚定」卡（widget）', () {
    testWidgets('#W1 有数据 ⇒ R-027 五条逐字渲染', (tester) async {
      const summary = PilotMetricsSummary(aerPercent: 87, evidenceCount: 15);

      await tester.pumpWidget(buildCard(summary));
      await tester.pumpAndSettle();

      expect(find.text('引文锚定'), findsOneWidget); // ① 卡题
      expect(find.text('诊断摘出的引文，能在你的原文里找到的比例'), findsOneWidget); // ② 说明
      expect(find.text('引文锚定率 87% · 共 15 条引文'), findsOneWidget); // ③ 数值行
      expect(find.text('所有数据只存在本机'), findsOneWidget); // ⑤ 隐私注记
    });

    testWidgets('#W2 零引文（有 anchor_probe 记录）⇒ 空态④，不出 0%', (tester) async {
      const summary = PilotMetricsSummary(aerPercent: null, evidenceCount: 0);

      await tester.pumpWidget(buildCard(summary));
      await tester.pumpAndSettle();

      expect(find.text('暂无引文数据'), findsOneWidget); // ④ 空态
      expect(find.textContaining('引文锚定率 0%'), findsNothing); // 不出假读数
      // 空态下卡题/隐私注记仍在（卡仍渲染，只缺数值行）
      expect(find.text('引文锚定'), findsOneWidget);
    });

    testWidgets('#W3 隐私边界端到端：引文原文哨兵到不了 UI 树', (tester) async {
      const sentinel = '__SENTINEL_RAW__';
      // 模拟真实链路：含原文片段的 payload ⇒ 纯函数装配 ⇒ 挂卡
      final payload =
          '{"v":1,"src":100,"syn":1,"emp":0,"n":2,"items":['
          '{"s":"syn_x","k":"ok_exact","o":1,"l":${sentinel.length},"h":"$sentinel"},'
          '{"s":"syn_x","k":"fail","o":1,"l":${sentinel.length},"h":"$sentinel"}]}';
      final summary = buildPilotMetricsSummary([payload], version: 1);
      expect(summary, isNotNull);

      await tester.pumpWidget(buildCard(summary!));
      await tester.pumpAndSettle();

      expect(find.text(sentinel), findsNothing);
      expect(find.textContaining(sentinel), findsNothing);
      // syndromeId 同样到不了 UI（口径②）
      expect(find.textContaining('syn_x'), findsNothing);
      // 聚合读数照常呈现
      expect(find.text('引文锚定率 50% · 共 2 条引文'), findsOneWidget);
    });

    testWidgets('#W4 卡文案无 R-009 评价词黑名单', (tester) async {
      const summary = PilotMetricsSummary(aerPercent: 100, evidenceCount: 9);

      await tester.pumpWidget(buildCard(summary));
      await tester.pumpAndSettle();

      // 黑名单含 B 项八字 + 本卡追加「准确/可靠」（AER 是高比率也不许吹）
      for (final word in PilotMetricsText.bannedWords) {
        expect(
          find.textContaining(word),
          findsNothing,
          reason: '评价词不得出现: $word',
        );
      }
    });
  });
}
