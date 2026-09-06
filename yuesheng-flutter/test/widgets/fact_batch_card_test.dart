// ─────────────────────────────────────────────────────────────
// fact_batch_card_test — FR-10 批次提示卡 Widget 测试（C78 批次3）
//
// 覆盖：
//   1. 卡片文案：本次沉淀 N 条人物事实（N>0 才有卡——注册表已拦 0）
//   2. 点入 → go_router 深链 /characters，extra 携 manuscriptId + since
//      （角色列表页据 since 进入「最近批次」过滤视图）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/providers/fact_batch_providers.dart';
import 'package:writingcoach/widgets/fact_batch_card.dart';

void main() {
  testWidgets('渲染沉淀条数；点入跳 /characters 并携带过滤起点', (tester) async {
    Object? capturedExtra;
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, __) => Scaffold(
            body: FactBatchCard(
              record: FactBatchRecord(
                count: 3,
                manuscriptId: 'ms-1',
                at: 1700000000,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/characters',
          builder: (_, state) {
            capturedExtra = state.extra;
            return const Scaffold(body: Text('角色页'));
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.textContaining('本次沉淀 3 条人物事实'), findsOneWidget);

    await tester.tap(find.text('查看 ›'));
    await tester.pumpAndSettle();

    expect(find.text('角色页'), findsOneWidget);
    expect(
      capturedExtra,
      isA<Map<String, dynamic>>()
          .having((m) => m['manuscriptId'], 'manuscriptId', 'ms-1')
          .having((m) => m['since'], 'since', 1700000000),
    );
  });
}
