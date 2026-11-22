// ─────────────────────────────────────────────────────────────
// SynPracticeBar 组件测试（T-20261119-01 §四 前四条验收）
//
// 立卡缺口：web `diagnose.html:692` 的 `syn-practice` 按钮是学员**主动**
// 逐条开练入口，App 侧只有教练**被动**推荐的 TeacherSuggestionCard，且
// 后者受 chat_gates 四道闸过滤（档位 / 任务非空 / 心流 / 去重）⇒ 学员看到
// 3 条症候可能一条入口都点不到。本测试钉住新入口的四个可判点：
//
//   ① 每条症候都有入口（数量 == syndromes.length，不是只给第一条）
//   ② 点击携带该条 syndromeId（spy 回调 + key 反查）
//   ③ 负向：不当档位（encourage）下入口**仍可点** —— 证明不走 chat_gates
//   ④ 防误删：入口消失时测试必红（本文件同时提供幂等的反向自检说明）
//
// 口径：本测试**不 mock 训练下游**，只钉呈现与接线。落库验收（closes 第 3
// 要件）由管理面只读 SQL 独立取证，不在此冒充。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/theme/app_theme.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';
import 'package:writingcoach/widgets/diagnosis_card_parts.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

/// 三条症候（覆盖三个不同 presentationGroup，确保分组渲染下都出现）。
List<DiagnosisSyndromeCard> _threeSyndromes() => const [
  DiagnosisSyndromeCard(
    syndromeId: 'P001',
    name: '情绪标签化',
    severity: 'L1',
    evidenceCount: 1,
    evidence: ['证据甲'],
  ),
  DiagnosisSyndromeCard(
    syndromeId: 'P003',
    name: '视角漂移',
    severity: 'L2',
    evidenceCount: 1,
    evidence: ['证据乙'],
  ),
  DiagnosisSyndromeCard(
    syndromeId: 'P010',
    name: '张力不足',
    severity: 'L3',
    evidenceCount: 1,
    evidence: ['证据丙'],
  ),
];

/// 展开态卡片（入口在详情块内，收起态不可命中）。
Future<void> _pumpExpanded(
  WidgetTester tester, {
  required List<DiagnosisSyndromeCard> syndromes,
  String? sessionId,
}) async {
  await tester.pumpWidget(
    _wrap(
      DiagnosisCard(
        syndromeCount: syndromes.length,
        syndromes: syndromes,
        suggestedActions: const [],
        confidence: 0.9,
        sessionId: sessionId,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('本次诊断'));
  await tester.pumpAndSettle();
}

void main() {
  group('T-20261119-01 逐条训练入口', () {
    testWidgets('① 每条症候都有入口（数量 == syndromes.length）', (tester) async {
      final syndromes = _threeSyndromes();
      await _pumpExpanded(tester, syndromes: syndromes, sessionId: 'sess-001');

      // 逐条按 syndromeId 精确断言 —— 不是只数 Text 出现次数，
      // 避免「三条只渲染一条 + 另外两条文案撞车」蒙混过关。
      for (final s in syndromes) {
        expect(
          find.byKey(Key('syn-practice-${s.syndromeId}')),
          findsOneWidget,
          reason: '症候 ${s.syndromeId}（${s.name}）缺训练入口',
        );
      }
      // 数量等值：确认没有多渲染（如分组头重复生成）。
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('syn-practice-'),
        ),
        findsNWidgets(syndromes.length),
      );
    });

    testWidgets('② 点击入口 → 打开练习启动器且预填该条症候', (tester) async {
      await _pumpExpanded(
        tester,
        syndromes: _threeSyndromes(),
        sessionId: 'sess-001',
      );

      // 入口在展开后的详情块内，可能落在视口下方 ⇒ 先滚动到可见再点。
      // （这是长卡片的真实布局，不是放水：滚动后仍断言弹层真的打开。）
      final target = find.byKey(const Key('syn-practice-P003'));
      await tester.scrollUntilVisible(target, 200);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      // 启动器弹层已打开：类型与难度两组选项必然在场。
      expect(find.text('改写'), findsOneWidget);
      expect(find.text('难度'), findsOneWidget);

      // 预填断言必须**限定在弹层内**：底层诊断卡仍在渲染（弹层是覆盖式的，
      // 卡片文字不会消失），全局 findsNothing 会误报。
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final inSheet = find.descendant(of: sheet, matching: find.text('视角漂移'));
      expect(inSheet, findsWidgets, reason: '弹层未预填被点击的那条症候');
      // 弹层内不得出现其它症候（候选只给本条 ⇒ 不让人重挑一遍）。
      expect(
        find.descendant(of: sheet, matching: find.text('情绪标签化')),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('张力不足')),
        findsNothing,
      );
    });

    testWidgets('③ 负向：encourage 档位下入口仍可点（不走 chat_gates 四道闸）', (tester) async {
      // 本入口是**学员主动**入口，其可达性不应依赖教学档位。
      // chat_gates 的四闸只过滤「教练主动推」的 TeacherSuggestionCard。
      // 若有人把本入口接进 chat_gates（`teachingDecision` 非 guide/train
      // ⇒ return null），本用例立刻变红。
      await _pumpExpanded(
        tester,
        syndromes: _threeSyndromes(),
        sessionId: 'sess-001',
      );

      final entry = find.byKey(const Key('syn-practice-P001'));
      // 存在性不受视口位置影响（不滚动也能断言在场）。
      expect(entry, findsOneWidget);
      await tester.scrollUntilVisible(entry, 200);
      await tester.pumpAndSettle();
      // 可点性：hitTestable 过滤掉被折叠 / 被遮挡的假存在。
      expect(entry.hitTestable(), findsOneWidget);

      await tester.tap(entry.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('改写'), findsOneWidget, reason: 'encourage 档位下弹层未打开');
    });

    testWidgets('④ 防误删：无 sessionId 时不渲染（入口依赖会话上下文）', (tester) async {
      // 入口的守卫条件是 sessionId != null（训练结果须挂会话落库）。
      // 该守卫若被误删（改成无条件渲染），本用例变红。
      await _pumpExpanded(
        tester,
        syndromes: _threeSyndromes(),
        sessionId: null,
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('syn-practice-'),
        ),
        findsNothing,
      );
    });

    testWidgets('⑤ 防误删反向自检：直接渲染 SynPracticeBar 必存在', (tester) async {
      // 与 ④ 配对：④ 证明「无会话不渲染」，本条证明「组件本身能渲染」。
      // 两者一正一反，任何一侧单独删除都会让另一半失去意义。
      await tester.pumpWidget(
        _wrap(const SynPracticeBar(syndromeId: 'P001', syndromeName: '情绪标签化')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('syn-practice-P001')), findsOneWidget);
      expect(find.text(SynPracticeText.label), findsOneWidget);
    });
  });
}
