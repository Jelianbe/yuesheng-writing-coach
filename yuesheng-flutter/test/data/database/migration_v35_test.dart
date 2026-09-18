// ─────────────────────────────────────────────────────────────
// migration_v35_test — 设定资料库第二批 L2 → v35 迁移路径测试
//
// v35 = character_fact 加 pinned 列（用户钉选，退化层名片注入）：
//   INTEGER NOT NULL DEFAULT 0
//
// 覆盖：
//   1. v34 存量库升级 → pinned 列建立、默认值 0、可写、user_version = kSchemaHead
//   2. 幂等：v35 库重复打开不报错、不重复加列
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
    'yuesheng_v35_${tag}_${_dbSeq++}.db';

/// v34 存量库：character_fact（含 description、无 pinned）+ setting_entry。
String createV34LegacyDbFile() {
  final path = _tempPath('v34');
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


    CREATE TABLE character_fact (


      id                  TEXT PRIMARY KEY,


      manuscript_id       TEXT NOT NULL,


      name                TEXT NOT NULL,


      first_seen_chapter  INTEGER,


      first_seen_at       INTEGER,


      assertions          TEXT NOT NULL DEFAULT '[]',


      aliases             TEXT NOT NULL DEFAULT '[]',


      status              TEXT NOT NULL DEFAULT 'active',


      description         TEXT NOT NULL DEFAULT '',


      created_at          INTEGER NOT NULL DEFAULT (unixepoch()),


      updated_at          INTEGER NOT NULL DEFAULT (unixepoch())


    )


  ''');
  db.execute('''


    CREATE TABLE setting_entry (


      id                  TEXT NOT NULL PRIMARY KEY,


      manuscript_id       TEXT NOT NULL,


      category            TEXT NOT NULL DEFAULT '',


      name                TEXT NOT NULL,


      description         TEXT NOT NULL DEFAULT '',


      participate         INTEGER NOT NULL DEFAULT 0,


      created_at          INTEGER NOT NULL DEFAULT (unixepoch()),


      updated_at          INTEGER NOT NULL DEFAULT (unixepoch()),


      UNIQUE (manuscript_id, name)


    )


  ''');
  db.execute('PRAGMA user_version = 34');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v35_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v34 → v35 升级：pinned 列建立，默认值 0', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV34LegacyDbFile())),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);

    // pinned 列存在且默认 0
    final dflt = await db
        .customSelect(
          "SELECT dflt_value FROM pragma_table_info('character_fact') "
          "WHERE name = 'pinned'",
        )
        .getSingle();
    expect(dflt.read<String>('dflt_value'), '0');

    // 可写：插入一行默认 pinned=0，再钉住为 1
    await db.customStatement(
      "INSERT INTO character_fact (id, manuscript_id, name) "
      "VALUES ('cf_1', 'm1', '林晚')",
    );
    final row = await db
        .customSelect("SELECT pinned FROM character_fact WHERE id = 'cf_1'")
        .getSingle();
    expect(row.read<int>('pinned'), 0);
    await db.customStatement(
      "UPDATE character_fact SET pinned = 1 WHERE id = 'cf_1'",
    );
    final updated = await db
        .customSelect("SELECT pinned FROM character_fact WHERE id = 'cf_1'")
        .getSingle();
    expect(updated.read<int>('pinned'), 1);
  });

  test('#2 幂等：v35 库重复打开不报错、不重复加列', () async {
    final path = createV34LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);

    final cols = await db2
        .customSelect(
          "SELECT count(*) AS c FROM pragma_table_info('character_fact') "
          "WHERE name = 'pinned'",
        )
        .getSingle();
    expect(cols.read<int>('c'), 1, reason: 'pinned 列应唯一');
  });
}
