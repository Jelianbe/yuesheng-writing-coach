// ─────────────────────────────────────────────────────────────
// migration_v32_test — 教学线 P0-1 → v32 迁移路径测试
//
// v32 = training_results 加 3 列（自评三维证据）：
//   confidence_rating INTEGER / explanation_text TEXT / transfer_text TEXT
//
// 覆盖：
//   1. v31 存量库升级 → 3 列建立且可写（含存量行 NULL 兼容），user_version = 32
//   2. 幂等：v32 库重复打开不报错、不重复加列
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';

var _dbSeq = 0;

String _tempPath(String tag) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'yuesheng_v32_${tag}_${_dbSeq++}.db';

/// v31 存量库：sessions + training_results（v26 完整 schema）。
String createV31LegacyDbFile() {
  final path = _tempPath('v31');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE sessions (
      id         TEXT PRIMARY KEY,
      title      TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE training_results (
      id             TEXT PRIMARY KEY,
      session_id     TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      suggestion_id  TEXT DEFAULT NULL,
      syndrome_id    TEXT NOT NULL,
      task_type      TEXT NOT NULL CHECK(task_type IN ('rewrite','analyze','compare','generate')),
      user_content   TEXT NOT NULL,
      result         TEXT NOT NULL CHECK(result IN ('passed','partial','failed')),
      feedback_json  TEXT DEFAULT NULL,
      score          REAL DEFAULT NULL,
      created_at     INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute("INSERT INTO sessions (id, title) VALUES ('s1', '存量训练会话')");
  db.execute(
    "INSERT INTO training_results "
    "(id, session_id, syndrome_id, task_type, user_content, result) "
    "VALUES ('tr1', 's1', 'P003', 'rewrite', '存量作答', 'passed')",
  );
  db.execute('PRAGMA user_version = 31');
  db.dispose();
  return path;
}

/// 列是否存在
Future<bool> _columnExists(AppDatabase db, String column) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM pragma_table_info('training_results') "
        "WHERE name = '$column'",
      )
      .get();
  return rows.length == 1;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v32_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v31 → v32 升级：3 列建立且可写，user_version = 32', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV31LegacyDbFile())),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 33);

    expect(
      await _columnExists(db, 'confidence_rating'),
      isTrue,
      reason: 'v32 必须加 confidence_rating 列',
    );
    expect(
      await _columnExists(db, 'explanation_text'),
      isTrue,
      reason: 'v32 必须加 explanation_text 列',
    );
    expect(
      await _columnExists(db, 'transfer_text'),
      isTrue,
      reason: 'v32 必须加 transfer_text 列',
    );

    // 存量行三列 NULL（兼容旧数据）
    final old = await db
        .customSelect(
          "SELECT confidence_rating, explanation_text, transfer_text "
          "FROM training_results WHERE id = 'tr1'",
        )
        .getSingle();
    expect(old.read<int?>('confidence_rating'), isNull);
    expect(old.read<String?>('explanation_text'), isNull);
    expect(old.read<String?>('transfer_text'), isNull);

    // 新行可写自评字段
    await db.customStatement(
      "INSERT INTO training_results "
      "(id, session_id, syndrome_id, task_type, user_content, result, "
      " confidence_rating, explanation_text, transfer_text) "
      "VALUES ('tr2', 's1', 'P003', 'rewrite', '新作答', 'passed', "
      " 4, '因为主语要明确。', '换成对话形式我会先写动作。')",
    );
    final row = await db
        .customSelect(
          "SELECT confidence_rating, explanation_text, transfer_text "
          "FROM training_results WHERE id = 'tr2'",
        )
        .getSingle();
    expect(row.read<int>('confidence_rating'), 4);
    expect(row.read<String>('explanation_text'), contains('主语'));
    expect(row.read<String>('transfer_text'), contains('对话'));
  });

  test('#2 幂等：v32 库重复打开不报错、列不重复', () async {
    final path = createV31LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    // 二次打开：from = 32 → onUpgrade 不触发（守卫），不报错
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 33);

    // 列存在且唯一
    final cols = await db2
        .customSelect(
          "SELECT count(*) AS c FROM pragma_table_info('training_results') "
          "WHERE name = 'confidence_rating'",
        )
        .getSingle();
    expect(cols.read<int>('c'), 1);
  });
}
