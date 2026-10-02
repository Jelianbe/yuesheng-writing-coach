// ─────────────────────────────────────────────────────────────
// whole_chapter_mode_bar_test — M4 第二格「完整章模式」开关（ADR-C137 批1）
//
// 覆盖 ADR §6 验收 1（本批部分）：完整章模式入口 widget 测试过
//   ① 开关存在：初始显示「这一章我自己写」入口；
//   ② 激活后模式状态/引导断言：最小支持提示 + 引导清单出现；
//   ③ 可随时退回：退出按钮切回 idle（无强制锁定）；
//   ④ R-009 形态审计：零代写/零打分/零处方措辞。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/writing/whole_chapter_mode_bar.dart';
import 'package:writingcoach/features/writing/whole_chapter_mode_provider.dart';

Widget _buildBar(String chapterId) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: WholeChapterModeBar(chapterId: chapterId)),
    ),
  );
}

void main() {
  const chapterId = 'ch-wcm-1';

  testWidgets('① 开关存在：初始显示「这一章我自己写」入口，未激活无引导', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));
    // 入口文案可见（开关可达）。
    expect(find.text('这一章我自己写（完整章）'), findsOneWidget);
    // 未激活时不显示最小支持引导。
    expect(find.text('完整章模式：目标字数达成前，我只在你叫我时说话，不代写'), findsNothing);
  });

  testWidgets('② 点入口 → 激活：显示最小支持模式状态 + 引导清单', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));

    await tester.tap(find.byKey(const Key('wholeChapterModeToggle')));
    await tester.pump();

    // 激活态模式状态提示（明写最小支持、不代写）。
    expect(find.text('完整章模式：目标字数达成前，我只在你叫我时说话，不代写'), findsOneWidget);
    // 引导清单全部出现（正向锁形态）。
    for (final n in kWholeChapterMinimalSupportNotes) {
      expect(find.text(n), findsOneWidget);
    }
    // 状态已写入 provider（激活态）。
    final ctx = tester.element(find.byType(WholeChapterModeBar));
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(wholeChapterDraftingProvider(chapterId)), isTrue);
  });

  testWidgets('③ 可随时退回：退出按钮切回 idle，无强制锁定', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));
    await tester.tap(find.byKey(const Key('wholeChapterModeToggle')));
    await tester.pump();
    expect(find.text('完整章模式：目标字数达成前，我只在你叫我时说话，不代写'), findsOneWidget);

    // 退出 = 随时退回求助（一键即回，无二次确认拦截）。
    await tester.tap(find.byKey(const Key('wholeChapterModeExit')));
    await tester.pump();
    expect(find.text('这一章我自己写（完整章）'), findsOneWidget);
    expect(find.text('完整章模式：目标字数达成前，我只在你叫我时说话，不代写'), findsNothing);
    final ctx = tester.element(find.byType(WholeChapterModeBar));
    expect(
      ProviderScope.containerOf(
        ctx,
      ).read(wholeChapterDraftingProvider(chapterId)),
      isFalse,
    );
  });

  testWidgets('④ R-009 形态审计：引导文案零代写/零打分/零处方措辞', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));
    await tester.tap(find.byKey(const Key('wholeChapterModeToggle')));
    await tester.pump();

    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(WholeChapterModeBar),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .join('\n');

    // 正向：最小支持/可退回形态必须在场。
    expect(texts, contains('不代写'));
    expect(texts, contains('你叫我时说话'));
    expect(texts, contains('退出'));

    // 反向：不含代写/打分/处方形态措辞（R-009 红线）。
    for (final banned in [
      '给你写',
      '替你把',
      '帮你写',
      '成段',
      '整段',
      '范文',
      '我来写',
      '打分为',
      '评分',
      '建议你应该',
      '处方',
      '必须改',
    ]) {
      expect(
        texts,
        isNot(contains(banned)),
        reason: '引导文案不得含代写/打分/处方形态：$banned',
      );
    }
  });

  testWidgets('⑤ 开关状态按章节隔离：另一章节默认关闭', (tester) async {
    await tester.pumpWidget(_buildBar(chapterId));
    await tester.tap(find.byKey(const Key('wholeChapterModeToggle')));
    await tester.pump();
    expect(find.text('完整章模式：目标字数达成前，我只在你叫我时说话，不代写'), findsOneWidget);

    // 换一个 chapterId（新 family 实例）→ 默认 idle。
    await tester.pumpWidget(_buildBar('ch-other-9'));
    expect(find.text('这一章我自己写（完整章）'), findsOneWidget);
    expect(find.text('完整章模式：目标字数达成前，我只在你叫我时说话，不代写'), findsNothing);
  });
}
