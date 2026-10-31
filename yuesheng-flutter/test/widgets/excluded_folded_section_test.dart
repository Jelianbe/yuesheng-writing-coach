// ─────────────────────────────────────────────────────────────
// T-20261030-02 ·「本轮还考虑过」折叠呈现
//
// 设计说明：.ai/reports/2026-10-31-设计说明-30-02-L3折叠-excluded呈现.md
//   §3 教学判据 3（否定语义 + 弱视觉）/ 5（过载：默认 1 行，不推走报出症候）
//   §4 往轮分组（只分不并：同 ID 两轮 ⇒ 出现两次、分属不同组）
//   §5 失败态（历史读失败 ⇒ 本轮仍显示、历史不出现）
//
// 假绿纪律：每条 findsNothing 前有阳性对照；期望侧钉字面量（注册表名实测值）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';
import 'package:writingcoach/widgets/excluded_folded_section.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );

/// 放大视口（防懒构建让 findsNothing 空过），与既有 excluded 卡片用例同口径。
Future<void> pumpSection(
  WidgetTester tester,
  ExcludedFoldedSection section,
) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(section));
  await tester.pumpAndSettle();
}

const _five = [
  ParsedExclusion(syndromeId: 'P002', reason: '与主线视角问题相邻，证据不足'),
  ParsedExclusion(syndromeId: 'P017', reason: '关键事件已展开'),
  ParsedExclusion(syndromeId: 'P021', reason: '本段有场景化呈现'),
  ParsedExclusion(syndromeId: 'P001', reason: '情绪词命中但属有意为之'),
  ParsedExclusion(syndromeId: 'P999'),
];

void main() {
  group('折叠 / 展开', () {
    testWidgets('默认折叠：只有一行计数，逐条理由不可见', (tester) async {
      await pumpSection(tester, const ExcludedFoldedSection(excluded: _five));

      // 阳性对照：折叠行必须出现。
      expect(
        find.textContaining('本轮还考虑过'),
        findsAtLeastNWidgets(1),
        reason: 'excluded 非空 ⇒ 折叠行必须渲染',
      );
      expect(
        find.textContaining('5 项'),
        findsAtLeastNWidgets(1),
        reason: '折叠行必须给本轮计数（5 项）',
      );
      // 默认折叠 ⇒ 逐条理由不可见。
      expect(
        find.textContaining('证据不足'),
        findsNothing,
        reason: '默认折叠态不得平铺理由（判据 5：不把报出症候推出首屏）',
      );
      expect(
        find.textContaining('· 信息倾泻'),
        findsNothing,
        reason: '默认折叠态不得平铺条目行',
      );
    });

    testWidgets('展开：逐条出现且与单轮卡片逐字一致；再点收起', (tester) async {
      await pumpSection(tester, const ExcludedFoldedSection(excluded: _five));

      await tester.tap(find.textContaining('本轮还考虑过'));
      await tester.pumpAndSettle();

      // 阳性对照：展开后 5 条都在（含未知 ID 回退原串）。
      expect(
        find.text('· 信息倾泻：与主线视角问题相邻，证据不足'),
        findsOneWidget,
        reason: '展开后条目逐字沿用「· 名称：理由」形态（判据 1）',
      );
      expect(
        find.textContaining('· 跳跃叙事/过度概括：关键事件已展开'),
        findsAtLeastNWidgets(1),
        reason: '展开后每条都渲染',
      );
      expect(
        find.text('· P999'),
        findsOneWidget,
        reason: '未知 ID 回退原串；reason 空 ⇒ 不展示理由',
      );

      // 再点收起 ⇒ 理由消失。
      await tester.tap(find.textContaining('本轮还考虑过'));
      await tester.pumpAndSettle();
      expect(find.textContaining('证据不足'), findsNothing, reason: '再点一次必须收起');
    });

    testWidgets('N=0 且 M=0 ⇒ 整块不渲染', (tester) async {
      await pumpSection(tester, const ExcludedFoldedSection());
      expect(
        find.textContaining('本轮还考虑过'),
        findsNothing,
        reason: '无本轮、无往轮 ⇒ 不造空区',
      );
    });

    testWidgets('reduce motion：disableAnimations 下展开无时长（pumpAndSettle 不超时）', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(1200, 4000),
              disableAnimations: true,
            ),
            child: ExcludedFoldedSection(excluded: _five),
          ),
        ),
      );
      await tester.tap(find.textContaining('本轮还考虑过'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('证据不足'),
        findsAtLeastNWidgets(1),
        reason: 'reduce motion 下展开必须即时生效',
      );
    });
  });

  group('教学判据 3 · 否定语义 + 弱视觉', () {
    testWidgets('折叠行 12px / textTertiary / 含「还考虑过」不含肯定词', (tester) async {
      await pumpSection(tester, const ExcludedFoldedSection(excluded: _five));

      final finder = find.textContaining('本轮还考虑过');
      expect(finder, findsAtLeastNWidgets(1), reason: '阳性对照');
      final text = tester.widget<Text>(finder.first);
      expect(
        text.style?.fontSize,
        12,
        reason: '折叠行字号必须 12（弱于报出区；改大 ⇒ 判据 3 失真）',
      );
      expect(
        text.style?.color,
        AppPalette.light.textTertiary,
        reason: '折叠行必须用三级文字色（弱视觉）',
      );
      final label = text.data!;
      expect(label, contains('还考虑过'), reason: '必须保留否定语义');
      for (final forbidden in ['已排除', '问题清单', '确定问题']) {
        expect(
          label,
          isNot(contains(forbidden)),
          reason: '折叠行不得改写成肯定/中性词（$forbidden）',
        );
      }
    });

    testWidgets('展开条目 11px / textTertiary', (tester) async {
      await pumpSection(tester, const ExcludedFoldedSection(excluded: _five));
      await tester.tap(find.textContaining('本轮还考虑过'));
      await tester.pumpAndSettle();

      final item = tester.widget<Text>(find.text('· 信息倾泻：与主线视角问题相邻，证据不足'));
      expect(item.style?.fontSize, 11, reason: '展开条目维持 11px（与单轮卡片一致）');
      expect(item.style?.color, AppPalette.light.textTertiary);
    });
  });

  group('往轮分组（只分不并）', () {
    testWidgets('两轮各有记录 ⇒ 分组标题正确、同 ID 不合并', (tester) async {
      await pumpSection(
        tester,
        const ExcludedFoldedSection(
          excluded: [ParsedExclusion(syndromeId: 'P021', reason: '本轮有场景')],
          history: [
            ExcludedRoundGroup(
              roundNumber: 2,
              items: [ParsedExclusion(syndromeId: 'P017', reason: '第二轮')],
            ),
            ExcludedRoundGroup(
              roundNumber: 1,
              items: [ParsedExclusion(syndromeId: 'P017', reason: '第一轮')],
            ),
          ],
        ),
      );

      expect(
        find.textContaining('往轮另有 2 项'),
        findsAtLeastNWidgets(1),
        reason: '折叠行必须补往轮计数（行数合计，不去重）',
      );

      await tester.tap(find.textContaining('本轮还考虑过'));
      await tester.pumpAndSettle();

      expect(find.text('第 2 轮 · 1 项'), findsOneWidget);
      expect(find.text('第 1 轮 · 1 项'), findsOneWidget);
      // 同 ID 两轮 ⇒ 出现两次、分属不同组（不跨轮去重）。
      expect(
        find.text('· 跳跃叙事/过度概括：第二轮'),
        findsOneWidget,
        reason: '第 2 轮条目必须独立成行',
      );
      expect(
        find.text('· 跳跃叙事/过度概括：第一轮'),
        findsOneWidget,
        reason: '第 1 轮条目必须独立成行（不得合并成一条）',
      );
    });
  });

  group('卡片接线（DiagnosisCard）', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    testWidgets('读出往轮 excluded 并分组；本轮按 messageId 剔除', (tester) async {
      final sessionRepo = SessionRepository(db);
      final repo = DiagnosisRepository(db);
      final sid = await sessionRepo.createBlankSession();
      Future<void> commit(String mid, List<ParsedExclusion> excluded) =>
          repo.commitDiagnosis(
            DiagnosisInput(
              sessionId: sid,
              messageId: mid,
              syndromes: const [
                {'syndrome_id': 'P001', 'name': '情绪标签化', 'severity': 'L2'},
              ],
              suggestedActions: const [],
              confidence: 0.8,
              excluded: excluded,
            ),
          );
      await commit('msg-1', const [
        ParsedExclusion(syndromeId: 'P017', reason: '第一轮排除'),
      ]);
      await commit('msg-2', const [
        ParsedExclusion(syndromeId: 'P021', reason: '第二轮排除'),
      ]);
      await commit('msg-3', const [
        ParsedExclusion(syndromeId: 'P002', reason: '本轮排除'),
      ]);

      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          DiagnosisCard(
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
            sessionId: sid,
            messageId: 'msg-3',
            excluded: const [
              ParsedExclusion(syndromeId: 'P002', reason: '本轮排除'),
            ],
          ),
          overrides: [appDatabaseProvider.overrideWithValue(db)],
        ),
      );
      await tester.pumpAndSettle();

      // 阳性对照 + 折叠计数（本轮 1，往轮 2）。
      expect(
        find.textContaining('本轮还考虑过 1 项（往轮另有 2 项）'),
        findsAtLeastNWidgets(1),
        reason: '必须剔除本轮 msg-3 自身，往轮 = msg-1 + msg-2',
      );

      await tester.tap(find.textContaining('本轮还考虑过'));
      await tester.pumpAndSettle();

      expect(find.text('第 2 轮 · 1 项'), findsOneWidget, reason: 'msg-2 = 第 2 轮');
      expect(find.text('第 1 轮 · 1 项'), findsOneWidget, reason: 'msg-1 = 第 1 轮');
      expect(find.text('· 画面感缺失：第二轮排除'), findsOneWidget, reason: '往轮理由必须逐字展示');
      // 本轮（msg-3）不出现在往轮组里。
      expect(
        find.text('· 信息倾泻：本轮排除'),
        findsOneWidget,
        reason: '本轮条目只出现一次（本轮段），不得重复进往轮组',
      );
    });

    testWidgets('历史读失败 ⇒ 本轮折叠行仍渲染、历史段不出现', (tester) async {
      // 关库制造读失败（历史段应降级；本轮段不依赖库）。
      await db.close();
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          DiagnosisCard(
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
            sessionId: 'sid-x',
            messageId: 'msg-x',
            excluded: const [
              ParsedExclusion(syndromeId: 'P002', reason: '本轮排除'),
            ],
          ),
          overrides: [appDatabaseProvider.overrideWithValue(db)],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('本轮还考虑过 1 项'),
        findsAtLeastNWidgets(1),
        reason: '库读失败不得阻断本轮段',
      );
      await tester.tap(find.textContaining('本轮还考虑过'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('往轮另有'),
        findsNothing,
        reason: '历史读失败 ⇒ 历史计数不出现',
      );
      expect(find.text('· 信息倾泻：本轮排除'), findsOneWidget, reason: '本轮条目照常展开');
    });
  });

  group('教学判据 5 · 过载（360×640 首屏）', () {
    testWidgets('折叠态下最后一条报出症候仍在首屏内', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: DiagnosisCard(
              syndromeCount: 2,
              syndromes: const [
                DiagnosisSyndromeCard(
                  syndromeId: 'P001',
                  name: '情绪标签化',
                  severity: 'L2',
                  evidenceCount: 1,
                ),
                DiagnosisSyndromeCard(
                  syndromeId: 'P002',
                  name: '信息倾泻',
                  severity: 'L2',
                  evidenceCount: 1,
                ),
              ],
              suggestedActions: const [],
              confidence: 0.8,
              defaultExpanded: true,
              excluded: _five,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 阳性对照：折叠行在该视口内确实渲染。
      expect(
        find.textContaining('本轮还考虑过'),
        findsAtLeastNWidgets(1),
        reason: '阳性对照：折叠行必须渲染（否则下面的位置断言无意义）',
      );
      // 判据 5 的机器可判内核：折叠态只占 1 行（44 触控区 + 12 上间距）。
      // 若改回平铺 5 条 ⇒ 该块高度 ≈ 44 + 5×17 ≈ 130 ⇒ 红线变红。
      final sectionRect = tester.getRect(find.byType(ExcludedFoldedSection));
      expect(
        sectionRect.height,
        lessThanOrEqualTo(56),
        reason: '折叠态必须只占 1 行（height=${sectionRect.height}）',
      );
      // 首屏可见性：最后一条报出症候（P002）的详情块——取最后一个匹配（标签行在上）。
      final last = find.text('信息倾泻').last;
      final rect = tester.getRect(last);
      expect(
        rect.bottom,
        lessThanOrEqualTo(640),
        reason: '判据 5：默认折叠只占 1 行；改回平铺 5 条 ⇒ 报出症候被推出首屏（bottom=${rect.bottom}）',
      );
    });
  });
}
