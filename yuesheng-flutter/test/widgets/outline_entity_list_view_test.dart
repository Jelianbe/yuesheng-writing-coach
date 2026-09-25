// ─────────────────────────────────────────────────────────────
// outline_entity_list_view_test — 「资料」Tab 大纲子列表三态
//
// 2026-09-20 三态债收敛：本页 _load() 此前**零 try/catch**（读库抛错会冒泡成
// 未捕获异步错误 / 卡转圈），且无 error 分支。补 try/catch + SettingErrorState 后，
// 锁死两条：① 读库抛错 ⇒ 错误态 + 重试；② 正常空库 ⇒ 空态（成对，防「永远错误」）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/features/app_settings/outline_entity_list_view.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '大纲三态测试');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: OutlineEntityListView(manuscriptId: manuscriptId)),
      ),
    );
  }

  testWidgets('#1 正常空库 ⇒ 空态（无手动新建入口，不给 CTA）', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(find.text('还没有大纲实体'), findsOneWidget);
    expect(find.text('加载大纲实体失败，请重试'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('#2 读库抛错 ⇒ 错误态 + 重试，不谎报「还没有大纲实体」', (tester) async {
    // _load 只读 outline_entity 表，drop 掉它 ⇒ listEntities 抛错
    await db.customStatement('DROP TABLE outline_entity');
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(find.text('还没有大纲实体'), findsNothing);
    expect(find.text('加载大纲实体失败，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
