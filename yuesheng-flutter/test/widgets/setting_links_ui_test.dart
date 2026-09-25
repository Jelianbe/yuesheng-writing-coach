// ─────────────────────────────────────────────────────────────
// setting_links_ui_test — 条目互链 UI（伪数据注入 · 详情页关联区块）
//
// 覆盖（角色详情页为宿主，世界观目标）：
//   1. 空态：还没有关联的设定条目
//   2. 展示：对方名称 + 类型 + 关系名
//   3. 跳转：点击可跳转项 → 进入世界观详情页
//   4. 添加：弹窗选类型/条目 → 列表出现
//   5. 删除：确认后列表空
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/setting_link_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/features/character/character_detail_page.dart';
import 'package:writingcoach/features/world/world_fact_detail_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;
  late String charId;
  late String worldId;
  late SettingLinkRepository linkRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '互链 UI 测试');
    final charRepo = CharacterFactRepository(db);
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
    );
    charId = (await charRepo.getCharacter(manuscriptId, '林晚'))!.id;
    final worldRepo = WorldFactRepository(db);
    await worldRepo.upsertWorld(manuscriptId: manuscriptId, name: '灵气体系');
    worldId = (await worldRepo.getWorld(manuscriptId, '灵气体系'))!.id;
    linkRepo = SettingLinkRepository(db);
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => CharacterDetailPage(
            characterId: charId,
            manuscriptId: manuscriptId,
          ),
        ),
        GoRoute(
          path: AppRoutes.worldDetail,
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return WorldFactDetailPage(
              worldId: extra['id'] as String? ?? '',
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

  testWidgets('#1 空态：还没有关联的设定条目', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(find.text('关联设定'), findsOneWidget);
    expect(find.text('还没有关联的设定条目'), findsOneWidget);
  });

  testWidgets('#2 展示：名称 + 类型 + 关系名', (tester) async {
    await linkRepo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.world,
      targetId: worldId,
      label: '所属世界',
    );
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(find.text('灵气体系 · 所属世界'), findsOneWidget);
    expect(find.textContaining('世界观'), findsWidgets);
  });

  testWidgets('#3 跳转：点击互链项进入世界观详情页', (tester) async {
    await linkRepo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.world,
      targetId: worldId,
    );
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('灵气体系'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('灵气体系'));
    await tester.pumpAndSettle();
    // 世界观详情页 AppBar 标题 = 主题名
    expect(find.widgetWithText(AppBar, '灵气体系'), findsOneWidget);
  });

  testWidgets('#4 添加：弹窗选类型/条目 → 列表出现', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加关联'));
    await tester.pumpAndSettle();
    // 弹窗默认角色类型 → 目标列表含「灵气体系」需切到世界观
    await tester.tap(find.text('世界观'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('灵气体系'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('灵气体系'), findsOneWidget, reason: '添加后列表展示');
  });

  testWidgets('#5 删除：确认后列表空', (tester) async {
    await linkRepo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.world,
      targetId: worldId,
    );
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.link_off));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.link_off));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(find.text('还没有关联的设定条目'), findsOneWidget);
  });
}
