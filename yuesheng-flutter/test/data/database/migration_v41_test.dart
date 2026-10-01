// ─────────────────────────────────────────────────────────────
// migration_v41_test — ADR-C121 小白冷启动试点埋点表迁移测试
//
// v41 = 新建 `pilot_metric_event`（试点埋点，追加式事件日志）。
//
// 覆盖（对齐 v39 测试范式 + ADR-C121 §5 判据）：
//   1. v40 存量库升级 → 新表建立、可写、`user_version == kSchemaHead`
//   2. 幂等：v41 库重复打开不报错、不重复建表
//   3. 最小 schema 库（新表不存在）→ 不抛错，且新表被建出
//      （v41 是**新增表**，与 v39「缺列不改」不同——表缺失则建）
//   4. 结果痕迹：升级后写入的事件能读回；**存量行不被改写**（R1′，DDL-only）
//
// ★ v41 必须是 DDL-only：本仓零数据变换先例（ADR-C96 §6.4）。
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
    'yuesheng_v41_${tag}_${_dbSeq++}.db';

/// v40 存量库：messages（真实表，含一行存量）+ PRAGMA user_version = 40。
String createV40LegacyDbFile() {
  final path = _tempPath('v40');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE messages (
      id           TEXT PRIMARY KEY,
      session_id   TEXT NOT NULL,
      role         TEXT NOT NULL,
      content      TEXT NOT NULL,
      message_type TEXT NOT NULL DEFAULT 'chat',
      timestamp    INTEGER NOT NULL DEFAULT (unixepoch()),
      status       TEXT NOT NULL DEFAULT 'ok'
    )
  ''');
  db.execute(
    "INSERT INTO messages (id, session_id, role, content) "
    "VALUES ('m1', 's1', 'user', '存量用户消息，逐字保留')",
  );
  db.execute('PRAGMA user_version = 40');
  db.dispose();
  return path;
}

/// 最小 schema 库：只有 manuscripts（pilot_metric_event 不存在）。
String createMinimalV40DbFile() {
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
  db.execute('PRAGMA user_version = 40');
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
      (f) => f.path.contains('yuesheng_v41_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v40 → v41 升级：新表建立、可写、user_version=$kSchemaHead', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV40LegacyDbFile())),
    );
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);

    final cols = await _columns(db, 'pilot_metric_event');
    expect(
      cols,
      containsAll(['id', 'session_id', 'event_type', 'payload', 'created_at']),
      reason: 'ADR-C121 v41：试点埋点表列齐',
    );
  });

  test('#2 结果痕迹：事件可写可读，且**存量行逐字未动**（R1′）', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV40LegacyDbFile())),
    );
    addTearDown(db.close);

    // 存量用户消息逐字保留（v41 是 DDL-only，不开数据变换先例）
    final legacy = await db
        .customSelect("SELECT content FROM messages WHERE id = 'm1'")
        .getSingle();
    expect(
      legacy.read<String>('content'),
      '存量用户消息，逐字保留',
      reason: 'R1′：已存值一个字节都不动',
    );

    // 新表写入 → 读回（证明列真实可用，不只是「DDL 跑过了」）
    await db.customStatement(
      "INSERT INTO pilot_metric_event "
      "(id, session_id, event_type, payload) "
      "VALUES ('e1', 's1', 'micro_task_submitted', '{\"card\":\"narrate_morning\",\"chars\":64}')",
    );
    final row = await db
        .customSelect(
          "SELECT session_id, event_type, payload FROM pilot_metric_event "
          "WHERE id = 'e1'",
        )
        .getSingle();
    expect(row.read<String>('session_id'), 's1');
    expect(row.read<String>('event_type'), 'micro_task_submitted');
    expect(row.read<String>('payload'), contains('narrate_morning'));
  });

  test('#3 幂等：v41 库重复打开不报错、不重复建表', () async {
    final path = createV40LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.close();
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    expect(await _columns(db2, 'pilot_metric_event'), contains('event_type'));
    await db2.close();
  });

  test('#4 最小 schema 库（新表不存在）→ 不抛错且新表被建出', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createMinimalV40DbFile())),
    );
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(
      version.read<int>('user_version'),
      kSchemaHead,
      reason: '表不存在也必须把版本推到位（否则每次打开都重跑升级）',
    );
    expect(
      await _columns(db, 'pilot_metric_event'),
      contains('event_type'),
      reason: 'v41 是新增表：最小库升级后必须建出（与 v39「缺失不改」语义不同）',
    );
  });
}
