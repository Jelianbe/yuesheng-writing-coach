// growth_narrative_card_test — 「与上次相比」叙事卡 widget 挂载测试
// （T-20261018-03 · B 议题 · 对齐 T-20261018-02 dispatcher 挂载测试先例）
//
// 覆盖（验收：叙事卡渲染 + 条目逐字断言）：
//   #W1 有叙事 ⇒ 卡题/锚点/能力行/症候行逐字渲染
//   #W2 空叙事守则：调用方不挂载（本测试直接验证空叙事时卡片不渲染——
//         挂载决策在 growth_page；此处验证纯函数空叙事 ⇒ isEmpty）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/features/growth/growth_narrative_card.dart';
import 'package:writingcoach/services/growth_narrative.dart';

void main() {
  Widget buildCard(GrowthNarrative narrative) {
    return MaterialApp(
      home: Scaffold(body: GrowthNarrativeCard(narrative: narrative)),
    );
  }

  testWidgets('#W1 有叙事 ⇒ 卡题/锚点/条目逐字渲染', (tester) async {
    final narrative = GrowthNarrative(
      anchorLabel: '对照 上次评估',
      items: const [
        NarrativeItem(type: NarrativeItemType.ability, text: '能力评分 42 → 51'),
        NarrativeItem(
          type: NarrativeItemType.severity,
          text: '指代不清 · 第 3 次出现 · 较上次 L3 → L2',
        ),
      ],
    );

    await tester.pumpWidget(buildCard(narrative));
    await tester.pumpAndSettle();

    // R-027 已批文案逐字（卡题① + 锚点⑤ + 能力行③ + 症候行②）
    expect(find.text('与上次相比'), findsOneWidget);
    expect(find.text('对照 上次评估'), findsOneWidget);
    expect(find.text('能力评分 42 → 51'), findsOneWidget);
    expect(find.text('指代不清 · 第 3 次出现 · 较上次 L3 → L2'), findsOneWidget);
  });

  test('#W2 空叙事 ⇒ isEmpty（调用方据此不挂载，不出死卡）', () {
    const narrative = GrowthNarrative(anchorLabel: '', items: []);
    expect(narrative.isEmpty, isTrue);
  });
}
