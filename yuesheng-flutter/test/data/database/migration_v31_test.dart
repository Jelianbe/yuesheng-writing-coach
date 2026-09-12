// ─────────────────────────────────────────────────────────────
// migration_v31_test — 批次 E1（书籍级成长叙事）→ v31 迁移路径测试
//
// 模拟真实升级：用 sqlite3 手工构造存量库文件，user_version = 30（或最小
// schema 的 24），再用 AppDatabase.forTesting 打开 → 触发 onUpgrade(… → 31)。
//
// 为什么两种场景都要测（方案 §4 E1 DoD #1 与风险表）：
//   character_fact / event_fact 是 v16/v17 才建的表，而最小 schema 存量库的
//   user_version 已是 23/24 → `if (from < 16)` 为假、整块被跳过 → 表**永远
//   补不上**（FactStaleService._hasCharacterTable 记录过这起事故）。
//   本测试专防 world_fact 重演：判据 `from < 31` 对存量库与最小库**都可达**。
//
// 覆盖：
//   1. v30 存量库升级 → world_fact 建立且可写，user_version = 31
//   2. 最小 schema 库（v24）升级 → world_fact 建立（可达性验证）
//   3. 幂等：v31 库重复打开不报错、不重复建表
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';

var _dbSeq = 0;

String _tempPath(String tag) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'yuesheng_v31_${tag}_${_dbSeq++}.db';

/// v30 存量库。
///
/// `from = 30` 时只有 `if (from < 31)` 块会执行，而它只做
/// `CREATE TABLE world_fact`（外键指向 manuscripts）→ 故存量侧只需
/// manuscripts 表存在即可复刻该路径。
String createV30LegacyDbFile() {
  final path = _tempPath('v30');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE manuscripts (
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '',
      genre       TEXT NOT NULL DEFAULT '',
      language    TEXT NOT NULL DEFAULT '中文',
      status      TEXT NOT NULL DEFAULT 'active',
      sort_order  INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL DEFAULT 0,
      updated_at  INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute(
    "INSERT INTO manuscripts (id, title, created_at, updated_at) "
    "VALUES ('m1', '存量测试稿', 100, 100)",
  );
  db.execute('PRAGMA user_version = 30');
  db.dispose();
  return path;
}

/// 最小 schema 存量库（v24）：只有 manuscripts / volumes / chapters。
///
/// `from = 24` → from<25 … from<31 的**所有**块依次执行 —— 这正是本用例的
/// 价值：它验证 world_fact 在「前置迁移块全部跑过」的路径上仍然建立。
String createMinimalV24LegacyDbFile() {
  final path = _tempPath('v24');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE manuscripts (
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '',
      genre       TEXT NOT NULL DEFAULT '',
      language    TEXT NOT NULL DEFAULT '中文',
      status      TEXT NOT NULL DEFAULT 'active',
      sort_order  INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL DEFAULT 0,
      updated_at  INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE volumes (
      id            TEXT PRIMARY KEY,
      manuscript_id TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
      title         TEXT NOT NULL DEFAULT '',
      sort_order    INTEGER NOT NULL DEFAULT 0,
      created_at    INTEGER NOT NULL DEFAULT 0,
      updated_at    INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE chapters (
      id                TEXT PRIMARY KEY,
      manuscript_id     TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
      volume_id         TEXT DEFAULT NULL REFERENCES volumes(id) ON DELETE SET NULL,
      title             TEXT NOT NULL DEFAULT '',
      content           TEXT NOT NULL DEFAULT '',
      previous_content  TEXT DEFAULT NULL,
      word_count        INTEGER NOT NULL DEFAULT 0,
      sort_order        INTEGER NOT NULL DEFAULT 0,
      status            TEXT NOT NULL DEFAULT 'draft'
                        CHECK(status IN ('draft','revising','complete')),
      last_diagnosed_at INTEGER DEFAULT NULL,
      created_at        INTEGER NOT NULL DEFAULT 0,
      updated_at        INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute(
    "INSERT INTO manuscripts (id, title, created_at, updated_at) "
    "VALUES ('m1', '最小库测试稿', 100, 100)",
  );
  db.execute('PRAGMA user_version = 24');
  db.dispose();
  return path;
}

/// 表是否存在
Future<bool> _tableExists(AppDatabase db, String table) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
      )
      .get();
  return rows.length == 1;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v31_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v30 → v31 升级：world_fact 建立且可写，user_version = 31', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV30LegacyDbFile())),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 31);

    expect(
      await _tableExists(db, 'world_fact'),
      isTrue,
      reason: '存量库升级后 world_fact 必须存在（DoD #1）',
    );

    // 可写 + 默认值与 DDL 一致
    await db.customStatement(
      "INSERT INTO world_fact (id, manuscript_id, name) "
      "VALUES ('wf1', 'm1', '灵气体系')",
    );
    final row = await db
        .customSelect("SELECT * FROM world_fact WHERE id = 'wf1'")
        .getSingle();
    expect(row.read<String>('name'), '灵气体系');
    expect(row.read<String>('assertions'), '[]');
    expect(row.read<String>('status'), 'active');

    // 存量数据未受影响
    final ms = await db
        .customSelect("SELECT * FROM manuscripts WHERE id = 'm1'")
        .getSingle();
    expect(ms.read<String>('title'), '存量测试稿');
  });

  test('#2 最小 schema 库（v24）→ v31：world_fact 仍建立（可达性）', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createMinimalV24LegacyDbFile())),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 31);

    expect(
      await _tableExists(db, 'world_fact'),
      isTrue,
      reason: '反例即 v16/v17 的跳过事故：最小 schema 库升级后表必须补上',
    );

    await db.customStatement(
      "INSERT INTO world_fact (id, manuscript_id, name) "
      "VALUES ('wf2', 'm1', '禁剑令')",
    );
    final row = await db
        .customSelect("SELECT * FROM world_fact WHERE id = 'wf2'")
        .getSingle();
    expect(row.read<String>('name'), '禁剑令');
  });

  test('#3 幂等：v31 库重复打开不报错、不重复建表', () async {
    final path = createV30LegacyDbFile();

    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    // 第二次打开（已是 v31）：`if (from < 31)` 不触发，不得报 table already exists
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);

    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 31);
    expect(await _tableExists(db2, 'world_fact'), isTrue);

    final dup = await db2
        .customSelect(
          "SELECT COUNT(*) AS c FROM sqlite_master "
          "WHERE type='table' AND name='world_fact'",
        )
        .getSingle();
    expect(dup.read<int>('c'), 1, reason: 'world_fact 表被重复创建');
  });
}
