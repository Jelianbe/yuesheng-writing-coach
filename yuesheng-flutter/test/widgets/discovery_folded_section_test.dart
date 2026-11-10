// ─────────────────────────────────────────────────────────────
// S3 控件测试（T-20261108-02 · R-027 已批 2026-11-08）
// 覆盖三条落地判据（报批单 §五）：
//   ① 未配置 ⇒ 明示文案、无展开符、无空列表；
//   ② 已配置零条目 ⇒ 「本次全部已归类」，与①文案逐字不同；
//   ③ 有条目 ⇒ 默认收起，展开逐条 reason + 原句锚点 + 底部声明。
// 附 S0（section null ⇒ 不渲染任何内容）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/discovery_card_payload.dart';
import 'package:writingcoach/widgets/discovery_folded_section.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('S0：section null ⇒ 不渲染任何文案/图标（短文轮 / 旧消息）', (tester) async {
    await tester.pumpWidget(_wrap(const DiscoveryFoldedSection(section: null)));
    expect(find.text('验证层未启用，本次无清单外发现'), findsNothing);
    expect(find.text('本次全部已归类'), findsNothing);
    expect(find.text('未归类现象'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('判据①：未配置 ⇒ 明示文案，无展开符，无列表', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const DiscoveryFoldedSection(
          section: DiscoverySectionCard(configured: false),
        ),
      ),
    );
    expect(find.text('验证层未启用，本次无清单外发现'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    // 不显示空列表（无条目摘要行）。
    expect(find.textContaining('条不在症候清单内'), findsNothing);
  });

  testWidgets('判据②：已配置零条目 ⇒ 「本次全部已归类」，与①文案逐字不同', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const DiscoveryFoldedSection(
          section: DiscoverySectionCard(configured: true),
        ),
      ),
    );
    expect(find.text('本次全部已归类'), findsOneWidget);
    expect(find.text('验证层未启用，本次无清单外发现'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.textContaining('条不在症候清单内'), findsNothing);
  });

  testWidgets('判据③：默认收起；展开后逐条 reason + 原句锚点 + 底部声明', (tester) async {
    const section = DiscoverySectionCard(
      configured: true,
      unclassified: [
        DiscoveryNoteCard(reason: '短理由', anchorQuotes: ['原文一句', '原文二句']),
        DiscoveryNoteCard(reason: '长理由', anchorQuotes: ['原文三句']),
      ],
    );
    await tester.pumpWidget(
      _wrap(const DiscoveryFoldedSection(section: section)),
    );

    // 收起态：标题 + 条数摘要可见；reason 与锚点不可见（不挤占主判）。
    expect(find.text('未归类现象'), findsOneWidget);
    expect(find.text('2 条不在症候清单内'), findsOneWidget);
    expect(find.textContaining('说明：'), findsNothing);
    expect(find.textContaining('原句：'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    await tester.tap(find.text('未归类现象'));
    await tester.pumpAndSettle();

    // 展开态：逐条 reason + 逐条锚点（多条全渲染）+ 底部边界声明。
    expect(find.textContaining('1. 原句：「原文一句」'), findsOneWidget);
    expect(find.textContaining('原句：「原文二句」'), findsOneWidget);
    expect(find.textContaining('2. 原句：「原文三句」'), findsOneWidget);
    expect(find.textContaining('说明：短理由'), findsOneWidget);
    expect(find.textContaining('说明：长理由'), findsOneWidget);
    expect(find.text('这些现象暂不在症候清单内，仅记录，供你参考。'), findsOneWidget);
  });

  testWidgets('判据③补：reason 超阈值出「展开全文」，点后给全文并可收起', (tester) async {
    final longReason = '这是一条超出自述理由折叠阈值的说明，' * 12; // > 60 字
    const section = DiscoverySectionCard(
      configured: true,
      unclassified: [
        DiscoveryNoteCard(reason: '短', anchorQuotes: ['q']),
        DiscoveryNoteCard(reason: '', anchorQuotes: []), // 占位不参与断言
      ],
    );
    final withLong = DiscoverySectionCard(
      configured: true,
      unclassified: [
        const DiscoveryNoteCard(reason: '短理由', anchorQuotes: ['q1']),
        DiscoveryNoteCard(reason: longReason, anchorQuotes: const ['q2']),
      ],
    );
    expect(withLong.unclassified.length, 2);
    expect(section.configured, isTrue); // 构造防呆（本测试真实输入是 withLong）

    await tester.pumpWidget(_wrap(DiscoveryFoldedSection(section: withLong)));
    await tester.tap(find.text('未归类现象'));
    await tester.pumpAndSettle();

    expect(find.text('展开全文'), findsOneWidget); // 仅长理由那条
    await tester.tap(find.text('展开全文'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    expect(find.textContaining('说明：$longReason'), findsOneWidget); // 全文可读
  });
}
