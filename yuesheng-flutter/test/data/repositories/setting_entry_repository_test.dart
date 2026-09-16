// ─────────────────────────────────────────────────────────────
// setting_entry_repository_test — 「其他」开放容器 DAO（第二批）
//
// 覆盖：CRUD / setParticipate / listParticipating 过滤 / listCategories
// distinct / 作品级隔离 / 删除。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/setting_entry_repository.dart';

void main() {
  late AppDatabase db;
  late SettingEntryRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SettingEntryRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '设定库稿', genre: '小说');
  });

  tearDown(() async => db.close());

  test('#1 新建 → 默认不参与诊断，列表可查', () async {
    final id = await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '武器',
      name: '血月刃',
      description: '以血养刃，月圆时锋锐倍增。',
    );
    final entries = await repo.listEntries(manuscriptId);
    expect(entries, hasLength(1));
    expect(entries.single.id, id);
    expect(entries.single.participate, isFalse, reason: '默认不参与诊断');
    expect(entries.single.description, contains('以血养刃'));
  });

  test('#2 勾选参与诊断 → listParticipating 命中；取消后不再命中', () async {
    final id = await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '规则怪谈',
      name: '镜中人',
    );
    // 勾选前零注入
    expect(await repo.listParticipating(manuscriptId), isEmpty);
    await repo.setParticipate(id, true);
    final participating = await repo.listParticipating(manuscriptId);
    expect(participating, hasLength(1));
    expect(participating.single.name, '镜中人');
    await repo.setParticipate(id, false);
    expect(await repo.listParticipating(manuscriptId), isEmpty);
  });

  test('#3 更新条目（类别/名称/正文）→ 落库生效', () async {
    final id = await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '武器',
      name: '血月刃',
      description: '初版',
    );
    await repo.updateEntry(
      id,
      category: '法器',
      name: '血月刃（改）',
      description: '二版',
    );
    final entries = await repo.listEntries(manuscriptId);
    expect(entries.single.category, '法器');
    expect(entries.single.name, '血月刃（改）');
    expect(entries.single.description, '二版');
  });

  test('#4 listCategories distinct（空类别排除）', () async {
    await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '武器',
      name: '血月刃',
    );
    await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '武器',
      name: '青霜剑',
    );
    await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '组织',
      name: '观星阁',
    );
    final cats = await repo.listCategories(manuscriptId);
    expect(cats.toSet(), {'武器', '组织'});
  });

  test('#5 删除条目 + 作品级隔离', () async {
    final id = await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '武器',
      name: '血月刃',
    );
    final otherMs = await ManuscriptRepository(
      db,
    ).createManuscript(title: '另一本', genre: '小说');
    await repo.createEntry(manuscriptId: otherMs, category: '武器', name: '霜寒枪');
    expect(await repo.listEntries(otherMs), hasLength(1));

    await repo.deleteEntry(id);
    expect(await repo.listEntries(manuscriptId), isEmpty);
    expect(await repo.listEntries(otherMs), hasLength(1), reason: '作品级隔离');
  });
}
