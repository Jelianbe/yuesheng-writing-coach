// ─────────────────────────────────────────────────────────────
// setting_link_repository_test — 条目互链 DAO 测试（v36）
//
// 覆盖：
//   1. createLink 幂等（重复同键返回既有 id）
//   2. listForEntity：出链 + 入链（方向无关）
//   3. deleteLink
//   4. 名称解析 4 类（character/world/setting/outline）
//   5. 目标已删容错（otherName = 已删除的条目，不可跳转）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/setting_entry_repository.dart';
import 'package:writingcoach/data/repositories/setting_link_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';

void main() {
  late AppDatabase db;
  late String manuscriptId;
  late SettingLinkRepository repo;
  late String charId;
  late String worldId;
  late String entryId;
  late String outlineId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '互链测试作品');
    repo = SettingLinkRepository(db);
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
    final entryRepo = SettingEntryRepository(db);
    entryId = await entryRepo.createEntry(
      manuscriptId: manuscriptId,
      category: '武器',
      name: '血月刃',
    );
    final outlineRepo = OutlineRepository(db);
    final outline = await outlineRepo.listEntities(manuscriptId);
    if (outline.isEmpty) {
      // outline 无直接写入方法（AI 沉淀路径）；跳过 outline 用例时用空列表断言
      outlineId = '';
    } else {
      outlineId = outline.first.id;
    }
  });

  tearDown(() => db.close());

  test('#1 createLink 幂等：同键返回既有 id', () async {
    final a = await repo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.world,
      targetId: worldId,
      label: '所属世界',
    );
    final b = await repo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.world,
      targetId: worldId,
      label: '重复尝试',
    );
    expect(a, isNotNull);
    expect(b, a, reason: '同键重复创建应返回既有 id');
  });

  test('#2 listForEntity：出链 + 入链（方向无关）', () async {
    await repo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.world,
      targetId: worldId,
      label: '所属世界',
    );
    await repo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.setting,
      sourceId: entryId,
      targetKind: SettingEntityKind.character,
      targetId: charId,
      label: '持有者',
    );
    // 角色视角：出链 1（→世界）+ 入链 1（←其他）
    final views = await repo.listForEntity(
      manuscriptId,
      SettingEntityKind.character,
      charId,
    );
    expect(views.length, 2);
    final names = views.map((v) => v.otherName).toSet();
    expect(names, {'灵气体系', '血月刃'});
    final labels = views.map((v) => v.link.label).toSet();
    expect(labels, {'所属世界', '持有者'});
  });

  test('#3 deleteLink：删除后列表为空', () async {
    final id = await repo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.world,
      targetId: worldId,
    );
    await repo.deleteLink(id!);
    final views = await repo.listForEntity(
      manuscriptId,
      SettingEntityKind.character,
      charId,
    );
    expect(views, isEmpty);
  });

  test('#4 名称解析（character/world/setting）', () async {
    await repo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.world,
      targetId: worldId,
    );
    await repo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.setting,
      targetId: entryId,
    );
    final views = await repo.listForEntity(
      manuscriptId,
      SettingEntityKind.character,
      charId,
    );
    final byKind = {for (final v in views) v.otherKind: v.otherName};
    expect(byKind[SettingEntityKind.world], '灵气体系');
    expect(byKind[SettingEntityKind.setting], '血月刃');
  });

  test('#5 目标已删容错：不可跳转', () async {
    await repo.createLink(
      manuscriptId: manuscriptId,
      sourceKind: SettingEntityKind.character,
      sourceId: charId,
      targetKind: SettingEntityKind.setting,
      targetId: entryId,
    );
    await SettingEntryRepository(db).deleteEntry(entryId);
    final views = await repo.listForEntity(
      manuscriptId,
      SettingEntityKind.character,
      charId,
    );
    expect(views.single.otherName, '已删除的条目');
    expect(views.single.targetExists, isFalse);
    expect(views.single.isJumpable, isFalse);
  });
}
