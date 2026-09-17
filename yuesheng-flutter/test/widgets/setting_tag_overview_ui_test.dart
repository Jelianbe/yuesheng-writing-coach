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
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/setting_link_repository.dart'
    show SettingEntityKind;
import 'package:writingcoach/data/repositories/setting_tag_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
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
}
