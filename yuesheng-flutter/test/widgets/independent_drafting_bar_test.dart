// ─────────────────────────────────────────────────────────────
// independent_drafting_bar_test — M4 独立起稿开关 + 结构性提问引导（ADR-C134 批3）
//
// 覆盖验收判据 3（M4）：
//   ① 起稿模式入口可达、可切换（开关 UI）；
//   ② 起稿引导不含代写文本（R-009 形态审计：正向锁结构性提问形态 +
//      反向断言不含代写措辞）；
//   ③ completion 标记落库可观测（仓储层测试见 edit_diff_event_repository_test #7；
//      本文件只测 UI 开关与引导文案形态）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/writing/independent_drafting_bar.dart';

Widget _buildBar(String chapterId) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: IndependentDraftingBar(chapterId: chapterId)),
    ),
  );
}

void main() {
  const chapterId = 'ch-idt-1';

  testWidgets('① 入口可达：初始显示「这次我自己来」入口', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));
    // 入口文案可见（开关可达）。
    expect(find.text('这次我自己来（独立起稿）'), findsOneWidget);
    // 未激活时不显示引导清单。
    expect(find.text('本次独立起稿：教练只给结构性提问，不代写'), findsNothing);
  });

  testWidgets('② 点入口 → 激活：显示提示 + 结构性提问清单，可退出', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));

    // 点击入口开关。
    await tester.tap(find.byKey(const Key('independentDraftingToggle')));
    await tester.pump();

    // 激活提示出现（明写不代写）。
    expect(find.text('本次独立起稿：教练只给结构性提问，不代写'), findsOneWidget);
    // 结构性提问清单全部出现（正向锁形态）。
    for (final q in kIndependentDraftingQuestions) {
      expect(find.text(q), findsOneWidget);
    }

    // 退出按钮可切换回 idle。
    await tester.tap(find.byKey(const Key('independentDraftingExit')));
    await tester.pump();
    expect(find.text('这次我自己来（独立起稿）'), findsOneWidget);
    expect(find.text('本次独立起稿：教练只给结构性提问，不代写'), findsNothing);
  });

  testWidgets('③ R-009 形态审计：引导文案零代写措辞', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));
    await tester.tap(find.byKey(const Key('independentDraftingToggle')));
    await tester.pump();

    // 收集引导条全部可见文案。
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(IndependentDraftingBar),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .join('\n');

    // 正向：结构性提问形态必须在场。
    expect(texts, contains('开头要立住什么'));
    expect(texts, contains('不代写'));

    // 反向：不含代写形态措辞（R-009 红线）。
    for (final banned in ['给你写', '替你把', '帮你写', '成段', '整段', '范文', '我来写']) {
      expect(texts, isNot(contains(banned)), reason: '引导文案不得含代写形态：$banned');
    }
  });

  testWidgets('④ 开关状态按章节隔离：另一章节默认关闭', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));
    await tester.tap(find.byKey(const Key('independentDraftingToggle')));
    await tester.pump();
    expect(find.text('本次独立起稿：教练只给结构性提问，不代写'), findsOneWidget);

    // 换一个 chapterId（新 family 实例）→ 默认 idle。
    await tester.pumpWidget(_buildBar('ch-other-2'));
    expect(find.text('这次我自己来（独立起稿）'), findsOneWidget);
    expect(find.text('本次独立起稿：教练只给结构性提问，不代写'), findsNothing);
  });
}
