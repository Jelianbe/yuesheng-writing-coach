// ─────────────────────────────────────────────────────────────
// T-20261024-05 批 2 · excluded 字段全链 —— 判据 4「渲染可展示」
//
// 落点（报批稿 ①6）：
//   - widgets/diagnosis_card.dart：新增「本轮还考虑过」渲染区块
//     （遍历 excluded；syndrome_id 反查 kSyndromeRegistry 取 name；
//       未知 ID 回退原串；reason 非空才展示）
//   - services/message_card_service.dart：DTO excluded 透传（本测试直接构造
//     DiagnosisCard，接线面由施工方按报批稿 ①6 完成）
//
// 假绿纪律（flutter-widget-test-false-green）：
//   ① 视口放大 + reset 复位（防懒构建容器让 findsNothing 空过）；
//   ⑧ 阳性对照一律 findsAtLeastNWidgets(1)（不用 findsOneWidget，防计数遮蔽语义断言）；
//   ① 每条 findsNothing 之前必有阳性对照（先证明区块/卡片真的渲染了）；
//   ⑦ 期望侧钉字面量（「信息倾泻」= P002 注册表名实测值，不调生产 helper 生成）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

/// 放大视口后 pump（防懒构建：展开态区块在默认 800×600 视口外时
/// 「找不到」与「还没构建」外观相同 —— 本文件所有 findsNothing 依赖此前提）。
Future<void> pumpExpanded(WidgetTester tester, DiagnosisCard card) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(card));
  await tester.pumpAndSettle();
}

DiagnosisCard _card({List<ParsedExclusion>? excluded}) => DiagnosisCard(
  syndromeCount: 1,
  syndromes: const [
    DiagnosisSyndromeCard(
      syndromeId: 'P001',
      name: '情绪标签化',
      severity: 'L2',
      evidenceCount: 1,
    ),
  ],
  suggestedActions: const [],
  confidence: 0.8,
  defaultExpanded: true,
  // null 时传 const []（= 施工方缺省默认值），不显式传 null 覆盖默认参数。
  excluded: excluded ?? const [],
);

void main() {
  group('判据 4 · 渲染可展示（「本轮还考虑过」区块）', () {
    testWidgets('W1 正向：excluded 非空 → 区块渲染，ID 反查注册表取名，reason 展示', (
      tester,
    ) async {
      await pumpExpanded(
        tester,
        _card(
          excluded: const [
            ParsedExclusion(syndromeId: 'P002', reason: '与主线视角问题相邻，证据不足'),
          ],
        ),
      );

      // 阳性对照：区块标题出现（至少 1 个，防计数遮蔽）。
      expect(
        find.text('本轮还考虑过'),
        findsAtLeastNWidgets(1),
        reason: 'excluded 非空时必须渲染「本轮还考虑过」区块',
      );
      // ID 反查注册表取名：P002 = 信息倾泻（syndromeNameOf 实测字面量，
      // 期望侧钉死 —— 不调生产 helper 生成，否则断言永真）。
      // 渲染行形态（施工 :1026）：'· $name：$reason' 合体串 ⇒ 用 textContaining。
      expect(
        find.textContaining('信息倾泻'),
        findsAtLeastNWidgets(1),
        reason: 'excluded ID P002 必须反查 kSyndromeRegistry 显示「信息倾泻」',
      );
      // reason 非空 → 理由文本展示。
      expect(
        find.textContaining('证据不足'),
        findsAtLeastNWidgets(1),
        reason: 'reason 非空时必须随区块展示理由文本',
      );
    });

    testWidgets('W2 未知 ID 回退原串；reason 为空 → 不展示理由', (tester) async {
      await pumpExpanded(
        tester,
        _card(
          excluded: const [ParsedExclusion(syndromeId: 'P999', reason: '')],
        ),
      );

      // 阳性对照先立：区块确实渲染了（否则下面的 findsNothing 是空过）。
      expect(
        find.text('本轮还考虑过'),
        findsAtLeastNWidgets(1),
        reason: 'excluded 非空时区块必须出现',
      );
      // 未知 ID 回退原串：P999 不在注册表 → 原样展示 ID（渲染行 '· P999' 合体 ⇒ textContaining）。
      expect(
        find.textContaining('P999'),
        findsAtLeastNWidgets(1),
        reason: '未知 excluded ID 必须回退原串「P999」，不得凭空猜名',
      );
      // reason 为空 → 不展示理由行（absent 断言有阳性对照背书）。
      expect(
        find.textContaining('证据不足'),
        findsNothing,
        reason: 'reason 为空时不得展示理由文本（区块仍在，只是没有理由行）',
      );
    });

    testWidgets('W3 防误删：excluded 缺省 → 区块不渲染（卡片主体照常渲染）', (tester) async {
      await pumpExpanded(tester, _card());

      // 阳性对照：卡片主体确实渲染了（防「整块卡片没渲染」让 absent 断言空过）。
      expect(
        find.text('本次诊断'),
        findsAtLeastNWidgets(1),
        reason: '卡片主体必须照常渲染（本断言是下面 absent 断言的阳性对照）',
      );
      expect(
        find.text('情绪标签化'),
        findsAtLeastNWidgets(1),
        reason: '既有症候标签行必须照常渲染（本批不改既有渲染）',
      );
      // 防误删：无 excluded ⇒ 不渲染区块。
      expect(
        find.text('本轮还考虑过'),
        findsNothing,
        reason: 'excluded 缺省时不得渲染「本轮还考虑过」区块（防误删既有渲染面）',
      );
    });
  });
}
