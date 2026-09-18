// ─────────────────────────────────────────────────────────────
// migration_v34_test — 设定资料库第二批 → v34 迁移路径测试
//
// v34 = 新建 setting_entry 表（「其他」开放容器）：
//   id / manuscript_id / category / name / description / participate
//   / created_at / updated_at，UNIQUE(manuscript_id, name)
//
// 覆盖：
//   1. v33 存量库升级 → setting_entry 表建立、默认值正确、user_version = kSchemaHead
//   2. 幂等：v34 库重复打开不报错、不重复建表
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
    'yuesheng_v34_${tag}_${_dbSeq++}.db';

/// v33 存量库：character_fact / world_fact（均含 description 列）。
String createV33LegacyDbFile() {
  final path = _tempPath('v33');
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


    CREATE TABLE world_fact (


      id                  TEXT PRIMARY KEY,


      manuscript_id       TEXT NOT NULL,


      name                TEXT NOT NULL,


      first_seen_chapter  INTEGER,


      first_seen_at       INTEGER,


      assertions          TEXT NOT NULL DEFAULT '[]',


      status              TEXT NOT NULL DEFAULT 'active',


      description         TEXT NOT NULL DEFAULT '',


      created_at          INTEGER NOT NULL DEFAULT (unixepoch()),


      updated_at          INTEGER NOT NULL DEFAULT (unixepoch())


    )


  ''');
  db.execute('PRAGMA user_version = 33');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v34_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v33 → v34 升级：setting_entry 表建立，默认值正确', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV33LegacyDbFile())),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);

    // 表存在
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'setting_entry'",
        )
        .get();
    expect(tables, hasLength(1), reason: 'v34 必须建 setting_entry 表');

    // 默认值：participate 默认 0（不参与诊断）
    final defaults = await db
        .customSelect(
          "SELECT dflt_value FROM pragma_table_info('setting_entry') "
          "WHERE name = 'participate'",
        )
        .getSingle();
    expect(defaults.read<String>('dflt_value'), '0');

    // 可写：插入一条默认 participate=0
    await db.customStatement(
      "INSERT INTO setting_entry (id, manuscript_id, category, name, "
      "description) VALUES ('se_1', 'm1', '武器', '血月刃', '以血养刃')",
    );
    final row = await db
        .customSelect(
          "SELECT participate, description FROM setting_entry WHERE id = 'se_1'",
        )
        .getSingle();
    expect(row.read<int>('participate'), 0);
    expect(row.read<String>('description'), '以血养刃');
  });

  test('#2 幂等：v34 库重复打开不报错、不重复建表', () async {
    final path = createV33LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);

    final tables = await db2
        .customSelect(
          "SELECT count(*) AS c FROM sqlite_master "
          "WHERE type = 'table' AND name = 'setting_entry'",
        )
        .getSingle();
    expect(tables.read<int>('c'), 1, reason: 'setting_entry 表应唯一');
  });
}
