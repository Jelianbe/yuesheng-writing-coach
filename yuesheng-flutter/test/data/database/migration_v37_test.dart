// ─────────────────────────────────────────────────────────────
// migration_v37_test — 条目标签 → v37 迁移路径测试
//
// v37 = 新建 setting_tag 表（Codex 式自由多标签，第二批）：
//   id / manuscript_id / entity_kind / entity_id / tag / created_at
//   + UNIQUE(manuscript_id, entity_kind, entity_id, tag)
//
// 覆盖：
//   1. v36 存量库升级 → setting_tag 表建立、可写、user_version = kSchemaHead
//   2. 幂等：v37 库重复打开不报错、不重复建表
//   3. 表级 UNIQUE 防重复（重复插同键抛异常）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import '../../test_support/schema_head.dart';

var _dbSeq = 0;

String _tempPath(String tag) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'yuesheng_v37_${tag}_${_dbSeq++}.db';

/// v36 存量库：manuscripts + setting_link（不含 setting_tag）。
String createV36LegacyDbFile() {
  final path = _tempPath('v36');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE manuscripts (
      id                  TEXT PRIMARY KEY,
      title               TEXT NOT NULL,
      genre               TEXT NOT NULL DEFAULT '',
      created_at          INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at          INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute('INSERT INTO manuscripts (id, title) VALUES (\'m1\', \'测试作品\')');
  db.execute('''
    CREATE TABLE setting_link (
      id                  TEXT PRIMARY KEY,
      manuscript_id       TEXT NOT NULL,
      source_kind         TEXT NOT NULL,
      source_id           TEXT NOT NULL,
      target_kind         TEXT NOT NULL,
      target_id           TEXT NOT NULL,
      label               TEXT NOT NULL DEFAULT '',
      created_at          INTEGER NOT NULL DEFAULT (unixepoch()),
      UNIQUE (manuscript_id, source_kind, source_id, target_kind, target_id)
    )
  ''');
  db.execute('PRAGMA user_version = 36');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v37_'),
    )) {
      f.deleteSync();
    }
  });

  test(
    '#1 v36 → v37 升级：setting_tag 表建立、可写、user_version=$kSchemaHead',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase(File(createV36LegacyDbFile())),
      );
      addTearDown(db.close);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), kSchemaHead);

      await db
          .into(db.settingTags)
          .insert(
            SettingTagsCompanion.insert(
              id: 't1',
              manuscriptId: 'm1',
              entityKind: 'character',
              entityId: 'c1',
              tag: '主角团',
            ),
          );
      final rows = await db.select(db.settingTags).get();
      expect(rows.length, 1);
      expect(rows.single.tag, '主角团');
    },
  );

  test('#2 幂等：v37 库重复打开不报错、不重复建表', () async {
    final path = createV36LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.close();
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    await db2.close();
  });

  test('#3 UNIQUE(manuscript_id, entity_kind, entity_id, tag) 防重复', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO manuscripts (id, title) VALUES ('m1', '测试稿')",
    );
    await db
        .into(db.settingTags)
        .insert(
          SettingTagsCompanion.insert(
            id: 't1',
            manuscriptId: 'm1',
            entityKind: 'world',
            entityId: 'w1',
            tag: '雾都',
          ),
        );
    await expectLater(
      db
          .into(db.settingTags)
          .insert(
            SettingTagsCompanion.insert(
              id: 't2',
              manuscriptId: 'm1',
              entityKind: 'world',
              entityId: 'w1',
              tag: '雾都',
            ),
          ),
      throwsA(anything),
    );
    await db.close();
  });
}
