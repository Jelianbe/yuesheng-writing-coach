// ─────────────────────────────────────────────────────────────
// setting_tag_overview_ui_test — 标签总览页 UI 测试（标签批次后续）
//
//   1. 空态：无标签时显示引导文案
//   2. 分组渲染：标签组 + 条目（类型徽标 + 名称）
//   3. 组件级：跨实体分组按类型排序
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/setting_link_repository.dart'
    show SettingEntityKind;
import 'package:writingcoach/data/repositories/setting_tag_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/widgets/character/character_detail_page.dart';
import 'package:writingcoach/widgets/setting/setting_tag_overview_page.dart';

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
    ).createManuscript(title: '标签总览 UI 测试作品');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildPage() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: SettingTagOverviewPage(manuscriptId: manuscriptId),
      ),
    );
  }

  /// 带路由的 host（跳转测试用）：总览页 → 角色/世界观详情页。
  Widget buildHost() {
    final router = GoRouter(
      initialLocation: AppRoutes.settingTagOverview,
      routes: [
        GoRoute(
          path: AppRoutes.settingTagOverview,
          builder: (_, _) => SettingTagOverviewPage(manuscriptId: manuscriptId),
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

  testWidgets('#1 空态：无标签时显示引导文案', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有标签'), findsOneWidget);
  });

  testWidgets('#2 分组渲染：标签组 + 条目 + 类型徽标', (tester) async {
    await CharacterFactRepository(db).upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
    );
    await WorldFactRepository(
      db,
    ).upsertWorld(manuscriptId: manuscriptId, name: '雾都');
    final charId = (await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '林晚'))!.id;
    final worldId = (await WorldFactRepository(
      db,
    ).getWorld(manuscriptId, '雾都'))!.id;
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.character, charId, '主角团');
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.world, worldId, '主角团');
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.text('#主角团 (2)'), findsOneWidget);
    expect(find.text('林晚'), findsOneWidget);
    expect(find.text('雾都'), findsOneWidget);
    expect(find.text('角色'), findsOneWidget);
    expect(find.text('世界观'), findsOneWidget);
  });

  testWidgets('#3 组件级：跨实体按类型排序（角色先于世界观）', (tester) async {
    await CharacterFactRepository(db).upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
    );
    await WorldFactRepository(
      db,
    ).upsertWorld(manuscriptId: manuscriptId, name: '雾都');
    final charId = (await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '林晚'))!.id;
    final worldId = (await WorldFactRepository(
      db,
    ).getWorld(manuscriptId, '雾都'))!.id;
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.world, worldId, '主角团');
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.character, charId, '主角团');
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    // ListTile 顺序：林晚（角色）在雾都（世界观）前
    final lin = tester.getTopLeft(find.text('林晚'));
    final wu = tester.getTopLeft(find.text('雾都'));
    expect(lin.dy < wu.dy, true, reason: '角色条目应排在世界观条目前');
  });

  testWidgets('#4 e2e：AI 抽取落库（pending）→ 打标签 → 总览展示', (tester) async {
    // 模拟 AI 抽取落库（_persistCharacterFacts 同款：断言 pending 待确认）
    await CharacterFactRepository(db).upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
      assertions: [
        CharacterAssertion(
          attribute: '身份',
          value: '守夜人',
          chapter: 1,
          timestamp: 1,
          status: 'pending',
          source: 'ai',
        ),
      ],
    );
    final charId = (await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '林晚'))!.id;
    // 用户打标签（AI 写入条目与用户组织链路互通）
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.character, charId, '主角团');
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.text('#主角团 (1)'), findsOneWidget);
    expect(find.text('林晚'), findsOneWidget);
    // 条目已落库且标签链路生效 → AI 写入未失效
    final row = await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '林晚');
    expect(row, isNotNull);
    expect(row!.assertions, contains('pending'));
  });

  testWidgets('#5 跳转：总览点击角色条目 → 角色详情页', (tester) async {
    await CharacterFactRepository(db).upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
    );
    final charId = (await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '林晚'))!.id;
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.character, charId, '主角团');
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('林晚'));
    await tester.pumpAndSettle();
    // 角色详情页 AppBar 标题 = 角色名
    expect(find.widgetWithText(AppBar, '林晚'), findsOneWidget);
  });

  // ── 三态债收敛（2026-09-20）：加载失败不得伪装成「还没有标签」 ──

  testWidgets('#6 读库抛错 ⇒ 显示错误态 + 重试，不谎报「还没有标签」', (tester) async {
    // 先让库里**确实有标签**（证明「有数据却读失败」≠「没数据」）
    await CharacterFactRepository(db).upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
    );
    final charId = (await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '林晚'))!.id;
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.character, charId, '主角团');
    // 制造真实读库异常：_load 会读 world_fact 表，drop 掉它 ⇒ listWorlds 抛错
    await db.customStatement('DROP TABLE world_fact');

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // 判据 5：不得伪装空数据 ⇒ 不出现「还没有标签」
    expect(find.textContaining('还没有标签'), findsNothing);
    // 判据 6：错误态可重试 ⇒ 出现重试按钮
    expect(find.text('加载标签失败，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('#7 成对负例：正常空库（未抛错）仍显示空态，不误报错误', (tester) async {
    // 防「永远显示错误态」的退化实现：库正常、无标签 ⇒ 走空态而非错误态
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.text('加载标签失败，请重试'), findsNothing);
    expect(find.text('重试'), findsNothing);
    expect(find.textContaining('还没有标签'), findsOneWidget);
  });
}
