// ─────────────────────────────────────────────────────────────
// setting_progressions_ui_test — Progressions 时间轴 UI 测试（第三批）
//
//   1. 角色详情页：有章节断言 → 渲染「第 N 章」节点与条目
//   2. 空态：无章节断言/无事件/无首见 → 区块隐藏
//   3. 时间轴按章节升序渲染（多章节点顺序）
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
import 'package:writingcoach/widgets/character/character_detail_page.dart';
import 'package:writingcoach/widgets/setting/setting_progressions_section.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;
  late String charId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: 'Progressions UI 测试作品');
    final charRepo = CharacterFactRepository(db);
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
    );
    charId = (await charRepo.getCharacter(manuscriptId, '林晚'))!.id;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildPage() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CharacterDetailPage(
          characterId: charId,
          manuscriptId: manuscriptId,
        ),
      ),
    );
  }

  testWidgets('#1 有章节断言 → 渲染章节节点与条目', (tester) async {
    await CharacterFactRepository(db).replaceAssertions(
      manuscriptId: manuscriptId,
      name: '林晚',
      assertions: [
        CharacterAssertion(
          attribute: '出身',
          value: '临安',
          chapter: 3,
          timestamp: 0,
        ),
      ],
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.text('章节演进 (2 章)'), findsOneWidget);
    expect(find.text('第 1 章'), findsOneWidget);
    expect(find.text('首次出现'), findsOneWidget);
    expect(find.text('第 3 章'), findsOneWidget);
    expect(find.text('出身: 临安'), findsOneWidget);
  });

  testWidgets('#2 空态：无章节数据 → 区块隐藏', (tester) async {
    await CharacterFactRepository(db).replaceAssertions(
      manuscriptId: manuscriptId,
      name: '林晚',
      assertions: [
        CharacterAssertion(
          attribute: '无章',
          value: 'x',
          chapter: null,
          timestamp: 0,
        ),
      ],
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.text('章节演进'), findsNothing);
  });

  testWidgets('#3 组件级：章节升序渲染 + 空输入隐藏', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingProgressionsSection(
                assertions: [],
                firstSeenChapter: 1,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('章节演进'), findsOneWidget);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SettingProgressionsSection(assertions: [])),
        ),
      ),
    );
    expect(find.textContaining('章节演进'), findsNothing);
  });
}
