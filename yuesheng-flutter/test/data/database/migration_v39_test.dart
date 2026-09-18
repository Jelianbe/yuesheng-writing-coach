// ─────────────────────────────────────────────────────────────
// migration_v39_test — fact 层章号**身份列** → v39 迁移路径测试
//
// v39 = `ADR-C96` 裁定 1/4：为三处「一列多源」的章号载体**另存身份**
//   event_fact    + chapter_sort_order
//   subplot_fact  + introduced_chapter_sort_order / resolved_chapter_sort_order
//   （第三处 `assertion.chapterSortOrder` 是 JSON 字段，**不需 schema 变更**）
//
// 覆盖（`ADR-C96 §5` 判据 5）：
//   1. v38 存量库升级 → 三列建立、可写、`user_version == kSchemaHead`
//   2. 幂等：v39 库重复打开不报错、不重复加列
//   3. **最小 schema 库**（这两张表根本不存在）→ 不抛错（判表存在，同 v32/v38 范式）
//   4. 结果痕迹：升级后写入的身份值能读回；**存量行的身份为 NULL**（不回填，裁定 1）
//
// ★ v39 必须是 **DDL-only**：本仓 38 个版本零数据变换先例（`ADR-C96 §6.4`）
//   ⇒ 本文件同时断言「存量行不被改写」（旧 `chapter` 原值逐字保留 = `R1′`）。
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
    'yuesheng_v39_${tag}_${_dbSeq++}.db';

/// v38 存量库：manuscripts + event_fact + subplot_fact（**均不含身份列**）。
///
/// DDL 取自 v39 之前的状态：三个章号列只有旧载体
/// （`event_fact.chapter` / `subplot_fact.introduced_chapter` / `.resolved_chapter`）。
String createV38LegacyDbFile() {
  final path = _tempPath('v38');
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
  db.execute("INSERT INTO manuscripts (id, title) VALUES ('m1', '存量测试稿')");
  db.execute('''
    CREATE TABLE event_fact (
      id              TEXT PRIMARY KEY,
      manuscript_id   TEXT NOT NULL,
      name            TEXT NOT NULL,
      chapter         INTEGER,
      event_type      TEXT NOT NULL,
      cause_event_id  TEXT,
      effect_event_id TEXT,
      participants    TEXT NOT NULL DEFAULT '[]',
      description     TEXT NOT NULL DEFAULT '',
      stale           INTEGER NOT NULL DEFAULT 0,
      chapter_hash    TEXT,
      created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at      INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute('''
    CREATE TABLE subplot_fact (
      id                 TEXT PRIMARY KEY,
      manuscript_id      TEXT NOT NULL,
      name               TEXT NOT NULL,
      introduced_chapter INTEGER,
      resolved_chapter   INTEGER,
      resolved_at        INTEGER,
      description        TEXT NOT NULL DEFAULT '',
      created_at         INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at         INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  // 存量行：旧载体有值、身份列**尚不存在**（升级后必须仍为 NULL）
  db.execute(
    "INSERT INTO event_fact (id, manuscript_id, name, chapter, event_type) "
    "VALUES ('ef1', 'm1', '阿禾决定去金陵', 3, '决定')",
  );
  db.execute(
    "INSERT INTO subplot_fact (id, manuscript_id, name, introduced_chapter) "
    "VALUES ('sf1', 'm1', '钥匙的秘密', 3)",
  );
  db.execute('PRAGMA user_version = 38');
  db.dispose();
  return path;
}

/// 最小 schema 库：只有 manuscripts（`event_fact` / `subplot_fact` 都不存在）。
String createMinimalV38DbFile() {
  final path = _tempPath('min');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE manuscripts (
      id         TEXT PRIMARY KEY,
      title      TEXT NOT NULL,
      created_at INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute('PRAGMA user_version = 38');
  db.dispose();
  return path;
}

Future<List<String>> _columns(AppDatabase db, String table) async {
  final rows = await db
      .customSelect("SELECT name FROM pragma_table_info('$table')")
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v39_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v38 → v39 升级：三列建立、可写、user_version=$kSchemaHead', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV38LegacyDbFile())),
    );
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);

    final evCols = await _columns(db, 'event_fact');
    expect(evCols, contains('chapter_sort_order'), reason: 'ADR-C96 裁定 1');
    final spCols = await _columns(db, 'subplot_fact');
    expect(spCols, contains('introduced_chapter_sort_order'));
    expect(spCols, contains('resolved_chapter_sort_order'));
  });

  test('#2 结果痕迹：身份可写可读，且**存量行的旧值逐字未动**（R1′）', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV38LegacyDbFile())),
    );
    addTearDown(db.close);

    // 存量行：旧载体保留 3，身份列**不回填**（v39 是 DDL-only，不开数据变换先例）
    final legacy = await db
        .customSelect("SELECT chapter, chapter_sort_order FROM event_fact")
        .getSingle();
    expect(legacy.read<int>('chapter'), 3, reason: 'R1′：已存值一个字节都不动');
    expect(
      legacy.read<int?>('chapter_sort_order'),
      isNull,
      reason: '存量行的身份**不可能可靠回溯** ⇒ 留 NULL，读取侧走兼容回退',
    );

    // 新行：写身份 → 读回（证明列真实可用，不只是「DDL 跑过了」）
    await db.customStatement(
      "INSERT INTO event_fact "
      "(id, manuscript_id, name, chapter, chapter_sort_order, event_type) "
      "VALUES ('ef2', 'm1', '重逢', 5, 4, '转折')",
    );
    final row = await db
        .customSelect(
          "SELECT chapter, chapter_sort_order FROM event_fact WHERE id = 'ef2'",
        )
        .getSingle();
    expect(row.read<int>('chapter'), 5, reason: 'AI 原值原样保留');
    expect(row.read<int>('chapter_sort_order'), 4, reason: '身份另存于新列');
  });

  test('#3 幂等：v39 库重复打开不报错、不重复加列', () async {
    final path = createV38LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.close();
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    expect(await _columns(db2, 'event_fact'), contains('chapter_sort_order'));
    await db2.close();
  });

  test('#4 最小 schema 库（两表不存在）→ 不抛错', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createMinimalV38DbFile())),
    );
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(
      version.read<int>('user_version'),
      kSchemaHead,
      reason: '表不存在也必须把版本推到位（否则每次打开都重跑升级）',
    );
    expect(await _columns(db, 'event_fact'), isEmpty, reason: '缺失表不得被凭空建出');
  });
}
