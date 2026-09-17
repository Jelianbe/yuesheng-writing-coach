// ─────────────────────────────────────────────────────────────
// migration_v36_test — 条目互链 → v36 迁移路径测试
//
// v36 = 新建 setting_link 表（Codex 式跨实体引用，第一批）：
//   id / manuscript_id / source_kind / source_id / target_kind / target_id /
//   label / created_at + UNIQUE(manuscript_id, source_kind, source_id,
//   target_kind, target_id)
//
// 覆盖：
//   1. v35 存量库升级 → setting_link 表建立、可写、user_version = 36
//   2. 幂等：v36 库重复打开不报错、不重复建表
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';

var _dbSeq = 0;

String _tempPath(String tag) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'yuesheng_v36_${tag}_${_dbSeq++}.db';

/// v35 存量库：character_fact（含 pinned）+ setting_entry（不含 setting_link）。
String createV35LegacyDbFile() {
  final path = _tempPath('v35');
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
      pinned              INTEGER NOT NULL DEFAULT 0,
      created_at          INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at          INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute('PRAGMA user_version = 35');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v36_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v35 → v36 升级：setting_link 表建立、可写', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV35LegacyDbFile())),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 37);

    // 表存在且可写（含 UNIQUE 约束）
    await db.customStatement(
      "INSERT INTO setting_link (id, manuscript_id, source_kind, source_id, "
      "target_kind, target_id, label) VALUES "
      "('l1', 'm1', 'character', 'c1', 'world', 'w1', '所属世界')",
    );
    final row = await db
        .customSelect(
          "SELECT source_kind, target_kind, label FROM setting_link "
          "WHERE id = 'l1'",
        )
        .getSingle();
    expect(row.read<String>('source_kind'), 'character');
    expect(row.read<String>('target_kind'), 'world');
    expect(row.read<String>('label'), '所属世界');
  });

  test('#2 幂等：v36 库重复打开不报错、不重复建表', () async {
    final path = createV35LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 37);

    final tables = await db2
        .customSelect(
          "SELECT count(*) AS c FROM sqlite_master "
          "WHERE type = 'table' AND name = 'setting_link'",
        )
        .getSingle();
    expect(tables.read<int>('c'), 1, reason: 'setting_link 表应唯一');
  });
}
