// ─────────────────────────────────────────────────────────────
// outline_entity_detail_page_test — 大纲实体详情页测试（大纲结构化批次）
//
//   1. 渲染：entityKey AppBar + 类型/状态徽标 + 别名 chips
//   2. 互链承载：大纲 → 角色 链接显示（类型徽标 + 名称）
//   3. 跳转：点击角色链接 → characterDetail 路由
//   4. 列表 onTap → 大纲详情页（AppBar 标题 = entityKey）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/setting_link_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/widgets/character/character_detail_page.dart';
import 'package:writingcoach/widgets/setting/outline_entity_detail_page.dart';
import 'package:writingcoach/widgets/setting/outline_entity_list_view.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;
  late String outlineId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '大纲详情页测试作品');
    final outlineRepo = OutlineRepository(db);
    await outlineRepo.insertEntity(
      manuscriptId: manuscriptId,
      entityType: 'volume',
      entityKey: '乡村起步（1-15万字）',
      aliases: ['第一卷'],
    );
    await outlineRepo.insertEntity(
      manuscriptId: manuscriptId,
      entityType: 'chapter',
      entityKey: '第一章：进城',
      aliases: ['进城'],
    );
    final entities = await outlineRepo.listEntities(manuscriptId);
    outlineId = entities.firstWhere((e) => e.entityKey.startsWith('乡村起步')).id;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost({required Widget home}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => home),
        GoRoute(
          path: AppRoutes.outlineDetail,
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return OutlineEntityDetailPage(
              entityId: extra['id'] as String? ?? '',
              manuscriptId: extra['manuscriptId'] as String? ?? '',
            );
          },
        ),
        GoRoute(
          path: AppRoutes.characterDetail,
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return CharacterDetailPage(
              characterId: extra['id'] as String? ?? '',
              manuscriptId: extra['manuscriptId'] as String? ?? '',
            );
          },
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('#1 渲染：AppBar + 类型/状态徽标 + 别名', (tester) async {
    await tester.pumpWidget(
      buildHost(
        home: OutlineEntityDetailPage(
          entityId: outlineId,
          manuscriptId: manuscriptId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '乡村起步（1-15万字）'), findsOneWidget);
    // volume 不在既有类型体系（character/setting/plot）→ 标签回退原值
    expect(find.text('volume'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('第一卷'), findsOneWidget);
    expect(find.text('关联设定'), findsOneWidget);
  });

  testWidgets('#2 互链承载：大纲 → 角色 链接显示', (tester) async {
    await CharacterFactRepository(db).upsertCharacter(
      manuscriptId: manuscriptId,
      name: '苏晚',
      firstSeenChapter: 1,
    );
    final char = (await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '苏晚'))!;
    await SettingLinkRepository(db).createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.outline,
      sourceId: outlineId,
      targetKind: SettingEntityKind.character,
      targetId: char.id,
      label: '本卷出场',
    );
    await tester.pumpWidget(
      buildHost(
        home: OutlineEntityDetailPage(
          entityId: outlineId,
          manuscriptId: manuscriptId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('苏晚 · 本卷出场'), findsOneWidget);
    expect(find.text('角色'), findsOneWidget);
  });

  testWidgets('#3 跳转：点击角色链接 → 角色详情页', (tester) async {
    await CharacterFactRepository(db).upsertCharacter(
      manuscriptId: manuscriptId,
      name: '苏晚',
      firstSeenChapter: 1,
    );
    final char = (await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '苏晚'))!;
    await SettingLinkRepository(db).createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.outline,
      sourceId: outlineId,
      targetKind: SettingEntityKind.character,
      targetId: char.id,
    );
    await tester.pumpWidget(
      buildHost(
        home: OutlineEntityDetailPage(
          entityId: outlineId,
          manuscriptId: manuscriptId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('苏晚'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '苏晚'), findsOneWidget);
  });

  testWidgets('#4 列表 onTap → 大纲详情页', (tester) async {
    await tester.pumpWidget(
      buildHost(home: OutlineEntityListView(manuscriptId: manuscriptId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('乡村起步（1-15万字）'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '乡村起步（1-15万字）'), findsOneWidget);
  });
}
