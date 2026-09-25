// ─────────────────────────────────────────────────────────────
// pending_confirm_card_test — AI 抽取断言确认卡 Widget 测试
//
// 批次：2026-09-16 设定资料库第一批（确认卡 UI 闭环）
// 覆盖：
//   1. 空列表 → 不渲染
//   2. 有 pending → 渲染标题（条数）+ 人物·属性·值 + 证据摘录
//   3. 点「确认」→ DB 断言变 confirmed + onChanged 回调触发
//   4. 点「拒绝」→ 弹理由单（可跳过）→ DB 断言变 rejected
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/features/character/pending_confirm_card.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late CharacterFactRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    repo = CharacterFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  CharacterAssertion pending(
    String attribute,
    String value, {
    String? evidence,
  }) => CharacterAssertion(
    attribute: attribute,
    value: value,
    chapter: 3,
    timestamp: 1000,
    status: 'pending',
    evidence: evidence,
  );

  Future<(CharacterFact, CharacterAssertion)> seed(
    String name,
    CharacterAssertion a,
  ) async {
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: name,
      firstSeenChapter: 1,
      assertions: [a],
    );
    final row = (await repo.getCharacter(manuscriptId, name))!;
    return (row, a);
  }

  Widget buildHost(
    List<(CharacterFact, CharacterAssertion)> items, {
    required VoidCallback onChanged,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: PendingConfirmCard(
            manuscriptId: manuscriptId,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('#1 空列表不渲染', (tester) async {
    await tester.pumpWidget(buildHost(const [], onChanged: () {}));
    expect(find.byType(PendingConfirmCard), findsOneWidget);
    expect(find.textContaining('待确认'), findsNothing);
  });

  testWidgets('#2 有 pending → 渲染标题 + 人物·属性·值 + 证据摘录', (tester) async {
    final item = await seed('阿禾', pending('职业', '捕快', evidence: '原文：他是一名捕快'));
    await tester.pumpWidget(buildHost([item], onChanged: () {}));
    expect(find.text('AI 抽取待确认 · 1 条'), findsOneWidget);
    expect(find.text('阿禾 · 职业 · 捕快'), findsOneWidget);
    expect(find.text('原文：他是一名捕快'), findsOneWidget);
  });

  testWidgets('#3 点确认 → DB 变 confirmed + 回调触发', (tester) async {
    final item = await seed('阿禾', pending('职业', '捕快'));
    var changed = 0;
    await tester.pumpWidget(buildHost([item], onChanged: () => changed++));
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    final row = (await repo.getCharacter(manuscriptId, '阿禾'))!;
    final a = CharacterFactRepository.parseAssertions(row.assertions).single;
    expect(a.status, 'confirmed');
    expect(changed, 1);
  });

  testWidgets('#4 点拒绝 → 理由单可跳过 → DB 变 rejected', (tester) async {
    final item = await seed('阿禾', pending('职业', '捕快'));
    var changed = 0;
    await tester.pumpWidget(buildHost([item], onChanged: () => changed++));
    await tester.tap(find.widgetWithText(OutlinedButton, '拒绝'));
    await tester.pumpAndSettle();
    // 理由单出现；选「不填理由，直接拒绝」
    await tester.tap(find.text('不填理由，直接拒绝'));
    await tester.pumpAndSettle();

    final row = (await repo.getCharacter(manuscriptId, '阿禾'))!;
    final a = CharacterFactRepository.parseAssertions(row.assertions).single;
    expect(a.status, 'rejected');
    expect(changed, 1);
  });

  testWidgets('#5 点拒绝 → 选理由 chip 写入 rejectReason', (tester) async {
    final item = await seed('阿禾', pending('职业', '捕快'));
    await tester.pumpWidget(buildHost([item], onChanged: () {}));
    await tester.tap(find.widgetWithText(OutlinedButton, '拒绝'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('抽取错误'));
    await tester.pumpAndSettle();

    final row = (await repo.getCharacter(manuscriptId, '阿禾'))!;
    final a = CharacterFactRepository.parseAssertions(row.assertions).single;
    expect(a.status, 'rejected');
    expect(a.rejectReason, '抽取错误');
  });
}
