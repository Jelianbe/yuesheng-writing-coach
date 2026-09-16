// ─────────────────────────────────────────────────────────────
// migration_v33_test — 设定资料库第四批 → v33 迁移路径测试
//
// v33 = character_fact / world_fact 加 description 列（条目正文，用户自由写作）：
//   description TEXT NOT NULL DEFAULT ''
//
// 覆盖：
//   1. v32 存量库升级 → 两表 description 列建立、存量行默认 ''、可写，user_version = 33
//   2. 幂等：v33 库重复打开不报错、不重复加列
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';

var _dbSeq = 0;

String _tempPath(String tag) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'yuesheng_v33_${tag}_${_dbSeq++}.db';

/// v32 存量库：character_fact（v26 完整 schema：含 aliases/status）+ world_fact（v31 建表）。
String createV32LegacyDbFile() {
  final path = _tempPath('v32');
  final db = sqlite3.sqlite3.open(path);
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
      created_at          INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at          INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute(
    "INSERT INTO character_fact (id, manuscript_id, name) "
    "VALUES ('c1', 'm1', '林晚')",
  );
  db.execute(
    "INSERT INTO world_fact (id, manuscript_id, name) "
    "VALUES ('w1', 'm1', '灵气体系')",
  );
  db.execute('PRAGMA user_version = 32');
  db.dispose();
  return path;
}

/// 列是否存在
Future<bool> _columnExists(AppDatabase db, String table, String column) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM pragma_table_info('$table') "
        "WHERE name = '$column'",
      )
      .get();
  return rows.length == 1;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v33_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v32 → v33 升级：两表 description 列建立，存量默认空串，可写', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV32LegacyDbFile())),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 33);

    expect(
      await _columnExists(db, 'character_fact', 'description'),
      isTrue,
      reason: 'v33 必须给 character_fact 加 description 列',
    );
    expect(
      await _columnExists(db, 'world_fact', 'description'),
      isTrue,
      reason: 'v33 必须给 world_fact 加 description 列',
    );

    // 存量行 description 默认空串（NOT NULL DEFAULT ''）
    final c = await db
        .customSelect("SELECT description FROM character_fact WHERE id = 'c1'")
        .getSingle();
    expect(c.read<String>('description'), '');
    final w = await db
        .customSelect("SELECT description FROM world_fact WHERE id = 'w1'")
        .getSingle();
    expect(w.read<String>('description'), '');

    // 新正文可写（用户写入路径）
    await db.customStatement(
      "UPDATE character_fact SET description = '外冷内热，出身灵修世家' "
      "WHERE id = 'c1'",
    );
    await db.customStatement(
      "UPDATE world_fact SET description = '灵气浓度由北方向南方递减' "
      "WHERE id = 'w1'",
    );
    final c2 = await db
        .customSelect("SELECT description FROM character_fact WHERE id = 'c1'")
        .getSingle();
    expect(c2.read<String>('description'), contains('外冷内热'));
    final w2 = await db
        .customSelect("SELECT description FROM world_fact WHERE id = 'w1'")
        .getSingle();
    expect(w2.read<String>('description'), contains('灵气浓度'));
  });

  test('#2 幂等：v33 库重复打开不报错、列不重复', () async {
    final path = createV32LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    // 二次打开：from = 33 → onUpgrade 不触发（守卫），不报错
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 33);

    for (final t in ['character_fact', 'world_fact']) {
      final cols = await db2
          .customSelect(
            "SELECT count(*) AS c FROM pragma_table_info('$t') "
            "WHERE name = 'description'",
          )
          .getSingle();
      expect(cols.read<int>('c'), 1, reason: '$t 的 description 列应唯一');
    }
  });
}
