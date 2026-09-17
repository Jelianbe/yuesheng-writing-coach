// ─────────────────────────────────────────────────────────────
// setting_tag_repository_test — 条目标签 DAO 测试（v37）
//
// 覆盖：
//   1. addTag 幂等（重复同键不产生重复行）
//   2. addTag 空白输入忽略
//   3. removeTag 删除 + 不存在静默
//   4. listForEntity 排序 + 跨实体隔离
//   5. replaceTags 重建（清空 + 去重排序写入）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/setting_link_repository.dart'
    show SettingEntityKind;
import 'package:writingcoach/data/repositories/setting_tag_repository.dart';

void main() {
  late AppDatabase db;
  late String manuscriptId;
  late SettingTagRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '标签测试作品');
    repo = SettingTagRepository(db);
  });

  tearDown(() => db.close());

  test('#1 addTag 幂等：重复添加只留一行', () async {
    await repo.addTag(manuscriptId, SettingEntityKind.character, 'c1', '主角团');
    await repo.addTag(manuscriptId, SettingEntityKind.character, 'c1', '主角团');
    expect(await repo.listForEntity(SettingEntityKind.character, 'c1'), [
      '主角团',
    ]);
  });

  test('#2 addTag 空白输入被忽略', () async {
    await repo.addTag(manuscriptId, SettingEntityKind.character, 'c1', '   ');
    expect(
      await repo.listForEntity(SettingEntityKind.character, 'c1'),
      isEmpty,
    );
  });

  test('#3 removeTag 删除；不存在静默不报错', () async {
    await repo.addTag(manuscriptId, SettingEntityKind.world, 'w1', '雾都');
    await repo.removeTag(manuscriptId, SettingEntityKind.world, 'w1', '雾都');
    expect(await repo.listForEntity(SettingEntityKind.world, 'w1'), isEmpty);
    await repo.removeTag(manuscriptId, SettingEntityKind.world, 'w1', '不存在');
  });

  test('#4 listForEntity 排序 + 跨实体隔离', () async {
    await repo.addTag(manuscriptId, SettingEntityKind.character, 'c1', '悬疑');
    await repo.addTag(manuscriptId, SettingEntityKind.character, 'c1', '主角团');
    await repo.addTag(manuscriptId, SettingEntityKind.world, 'w1', '雾都');
    expect(await repo.listForEntity(SettingEntityKind.character, 'c1'), [
      '主角团',
      '悬疑',
    ]);
    expect(await repo.listForEntity(SettingEntityKind.world, 'w1'), ['雾都']);
  });

  test('#5 replaceTags 重建：清空旧标签 + 去重排序写入', () async {
    await repo.addTag(manuscriptId, SettingEntityKind.setting, 's1', '武器');
    await repo.addTag(manuscriptId, SettingEntityKind.setting, 's1', '旧标签');
    await repo.replaceTags(manuscriptId, SettingEntityKind.setting, 's1', [
      '关键道具',
      '武器',
      '关键道具',
    ]);
    expect(await repo.listForEntity(SettingEntityKind.setting, 's1'), [
      '关键道具',
      '武器',
    ]);
  });
}
