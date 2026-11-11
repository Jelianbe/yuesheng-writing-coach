// ─────────────────────────────────────────────────────────────
// growth_first_screen_order_test — 成长 Tab 首屏顺序契约（IA-3）
//
// 真源：`T-20261111-01` U1 设计稿 §IA-3（舰长 2026-11-11 批）
// 目标：首屏第一块是**能力画像**；三个「去别处」的行下沉到**症候概览之后**。
//
// 为什么用「顺序 + 完全在内」而不是像素常量：
//   顺序关系与屏宽无关，最稳；fold 判据一律配负对照，否则在「页面很短」时恒真。
//
// 视口口径：360×740 是平台唯一形态；但真实运行在 `_AppShell` 里，
// 底部 `NavigationBar` 默认 80dp（`.ai/PROJECT.md §2`）⇒ **内容区只有 660**。
// 因此 fold 断言一律对 660 判定，而不是 740。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/features/growth/growth_page.dart';
import 'package:writingcoach/providers/app_providers.dart';

void main() {
  /// 视口高 740；`_AppShell` 底部导航 80 ⇒ 内容区底边 = 660
  const viewportH = 740.0;
  const navBarH = 80.0;
  const contentBottom = viewportH - navBarH;

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// 造「老用户」：1 条诊断结果 ⇒ `activeProblems` 非空 ⇒ 走非空内容分支
  Future<void> seedDiagnosis() async {
    final s = await SessionRepository(db).createBlankSession();
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.diagnosisResults)
        .insert(
          DiagnosisResultsCompanion.insert(
            id: 'dr-order-1',
            sessionId: s,
            messageId: 'msg-order-1',
            syndromes: Value(
              jsonEncode([
                {
                  'syndrome_id': 'P002',
                  'name': '信息倾泻',
                  'severity': 'L2',
                  'evidence': ['例1'],
                },
              ]),
            ),
            suggestedActions: const Value('[]'),
            confidence: const Value(0.85),
            timestamp: Value(ts),
            createdAt: Value(ts),
          ),
        );
  }

  Widget buildPage() => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: GrowthPage()),
  );

  Future<void> usePhone(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360, viewportH));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  double topOf(WidgetTester t, Finder f) => t.getRect(f.first).top;

  group('IA-3 成长首屏顺序契约', () {
    testWidgets('能力画像 → 症候概览 → 快捷入口，顺序严格在前', (tester) async {
      await usePhone(tester);
      await seedDiagnosis();
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final proficiency = find.text('能力画像');
      final severity = find.text('症候概览');
      final quickEntry = find.text('写作诊断');

      // 负对照：三者必须都真实存在，否则下面的比较毫无意义
      expect(proficiency, findsOneWidget);
      expect(severity, findsOneWidget);
      expect(quickEntry, findsOneWidget);

      expect(
        topOf(tester, proficiency),
        lessThan(topOf(tester, severity)),
        reason: '能力画像是本 Tab 的任务，必须排在症候概览之前',
      );
      expect(
        topOf(tester, severity),
        lessThan(topOf(tester, quickEntry)),
        reason: '三个「去别处」的行必须沉到症候概览之后',
      );
    });

    testWidgets('fold 契约：能力画像整卡在内容区（660）内', (tester) async {
      await usePhone(tester);
      await seedDiagnosis();
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // 「共 N 次写作会话」是能力画像卡的**最后一行** ⇒ 它的 bottom
      // 加上卡片内边距就是卡底。用它代替私有 `_Card` 类型（不可引用）。
      final lastLine = find.textContaining('次写作会话');
      expect(lastLine, findsOneWidget);

      final cardBottom = tester.getRect(lastLine).bottom;
      expect(
        cardBottom,
        lessThanOrEqualTo(contentBottom),
        reason: '能力画像卡必须整卡落在内容区内（含底部导航 80dp 后的 $contentBottom）',
      );
    });

    testWidgets('fold 负对照：「思考题回顾」不在首屏内', (tester) async {
      await usePhone(tester);
      await seedDiagnosis();
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // 没有这条，上一条可能在「整页很短、所有卡片都塞得下」时恒真。
      final reflection = find.textContaining('思考题回顾', skipOffstage: false);
      expect(reflection, findsOneWidget);
      expect(
        topOf(tester, reflection),
        greaterThan(contentBottom),
        reason: '思考题回顾必须仍在 fold 之下，才能证明上一条测的是位置而非页长',
      );
    });

    testWidgets('空态对齐：新用户仍能看见快捷入口（不被 IA-3 误伤）', (tester) async {
      await usePhone(tester);
      // 不播种 ⇒ totalSessions=0 且无活跃问题 ⇒ 空态分支
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('还没有写作记录'), findsOneWidget);
      // 新用户的第一次写作诊断正是从快捷入口进的；空态不给 = 把人堵死
      expect(find.text('写作诊断'), findsOneWidget);
      expect(find.text('学习进度'), findsOneWidget);
      expect(find.text('教学资料'), findsOneWidget);
    });
  });
}
