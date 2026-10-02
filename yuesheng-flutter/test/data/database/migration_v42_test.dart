// ─────────────────────────────────────────────────────────────
// migration_v42_test — C126 diagnosis_results 加 status 列迁移测试
//
// v42 = diagnosis_results 增加裁决态列 status
//       （confirmed=权威正式诊断 / pending=教学轮未确认 / replaced=被替换旧 pending）。
//
// 覆盖（对齐 v41 测试范式）：
//   1. v41 存量库升级 → status 列存在、可写、user_version == kSchemaHead
//   2. 存量行 status 默认 'confirmed'（历史正式诊断不被误判为 pending）
//   3. 幂等：v42 库重复打开不报错、不重复加列（PRAGMA 判存在）
//
// ★ v42 是 DDL-only：零数据变换先例（ADR-C96 §6.4）。
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
    'yuesheng_v42_${tag}_${_dbSeq++}.db';

/// v41 存量库：diagnosis_results（真实表，含一行历史诊断）+ PRAGMA user_version = 41。
String createV41LegacyDbFile() {
  final path = _tempPath('v41');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE diagnosis_results (
      id           TEXT PRIMARY KEY,
      session_id   TEXT NOT NULL,
      message_id   TEXT NOT NULL,
      syndromes    TEXT NOT NULL DEFAULT '[]',
      suggested_actions TEXT NOT NULL DEFAULT '[]',
      confidence   REAL NOT NULL DEFAULT 0,
      timestamp    INTEGER NOT NULL DEFAULT (unixepoch()),
      created_at   INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute(
    "INSERT INTO diagnosis_results (id, session_id, message_id, syndromes) "
    "VALUES ('d1', 's1', 'm1', '[{\"syndrome_id\":\"P005\",\"severity\":\"L2\"}]')",
  );
  db.execute('PRAGMA user_version = 41');
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
      (f) => f.path.contains('yuesheng_v42_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v41 → v42 升级：status 列存在、user_version=$kSchemaHead', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV41LegacyDbFile())),
    );
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);

    final cols = await _columns(db, 'diagnosis_results');
    expect(
      cols,
      contains('status'),
      reason: 'C126 v42：diagnosis_results 应有 status 列',
    );
  });

  test('#2 存量行 status 默认 confirmed（历史正式诊断不被误判 pending）', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV41LegacyDbFile())),
    );
    addTearDown(db.close);

    final row = await db
        .customSelect("SELECT status FROM diagnosis_results WHERE id = 'd1'")
        .getSingle();
    expect(
      row.read<String>('status'),
      'confirmed',
      reason: '存量行经 NOT NULL DEFAULT \'confirmed\' 补列后必须为 confirmed',
    );
  });

  test('#3 幂等：v42 库重复打开不报错、不重复加列', () async {
    final path = createV41LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.close();
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    expect(await _columns(db2, 'diagnosis_results'), contains('status'));
    await db2.close();
  });
}
