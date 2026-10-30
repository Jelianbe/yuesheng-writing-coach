// ─────────────────────────────────────────────────────────────
// migration_v50_test — ADR-0012 `diagnosis_results.excluded_json`（轮次级排除记录落库）
//
// 覆盖（判据见 `.ai/adr/0012-持久化批-excluded落DiagnosisRow.md §5`）：
//   M1 v49 存量库升级：加列成功 / 存量行恒 NULL / syndromes 逐字不变 / 升到 kSchemaHead
//   M2 幂等：同一库连开两次不抛错、列仍在
//   M3 边界：无 diagnosis_results 表的库 → 表存在性守卫跳过，升级不抛错
//
// ⚠️ M1 的夹具是**手写 v49 DDL**（diagnosis_results 无 excluded_json 列），
//    用前先删同名临时文件：`flutter test` 跨轮次残留会撞 `table already exists`。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';

import '../../test_support/schema_head.dart';

var _dbSeq = 0;

String _tempPath(String tag) {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'yuesheng_v50_${tag}_${_dbSeq++}_${DateTime.now().microsecondsSinceEpoch}.db';
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  return path;
}

/// v49 存量库：diagnosis_results 为 v50 **之前**的列集（无 excluded_json），含 1 条存量行。
String createV49DbFile() {
  final path = _tempPath('v49');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE diagnosis_results (
      id TEXT NOT NULL PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      message_id TEXT NOT NULL,
      syndromes TEXT NOT NULL DEFAULT '[]',
      suggested_actions TEXT NOT NULL DEFAULT '[]',
      root_cause_analysis TEXT,
      next_focus TEXT,
      feedback_summary TEXT,
      confidence REAL NOT NULL DEFAULT 0.0,
      teaching_progress TEXT,
      target_ref_type TEXT,
      target_ref_id TEXT,
      timestamp INTEGER NOT NULL DEFAULT (unixepoch()),
      created_at INTEGER NOT NULL DEFAULT (unixepoch()),
      current_teaching_focus_id TEXT,
      focus_reason TEXT,
      status TEXT NOT NULL DEFAULT 'confirmed'
        CHECK (status IN ('confirmed','pending','replaced'))
    );
  ''');
  db.execute("INSERT INTO sessions (id) VALUES ('s1')");
  db.execute(
    "INSERT INTO diagnosis_results (id, session_id, message_id, syndromes) "
    "VALUES ('dr-legacy', 's1', 'm1', '[{\"syndrome_id\":\"P003\"}]')",
  );
  db.execute('PRAGMA user_version = 49');
  db.dispose();
  return path;
}

/// 没有 `diagnosis_results` 表的库（`user_version = 49`）：v50 块必须靠表存在性守卫
/// 跳过，直接 `ALTER` 会抛「no such table」。
String createNoTableDbFile() {
  final path = _tempPath('no_table');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL DEFAULT 0
    );
  ''');
  db.execute('PRAGMA user_version = 49');
  db.dispose();
  return path;
}

Future<AppDatabase> _openPath(String path, {bool autoClose = true}) async {
  final db = AppDatabase.forTesting(NativeDatabase(File(path)));
  // 触发 onUpgrade
  await db.customSelect('PRAGMA user_version').getSingle();
  if (autoClose) addTearDown(db.close);
  return db;
}

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db
      .customSelect("SELECT name FROM pragma_table_info('$table')")
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

void main() {
  group('v50 diagnosis_results.excluded_json（ADR-0012）', () {
    test('M1 v49 存量库升级：加列 / 存量行恒 NULL / syndromes 逐字不变 / 版本升到 head', () async {
      final db = await _openPath(createV49DbFile());

      expect(
        await _columns(db, 'diagnosis_results'),
        contains('excluded_json'),
      );

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), kSchemaHead);

      final rows = await db
          .customSelect(
            "SELECT syndromes, excluded_json FROM diagnosis_results WHERE id = 'dr-legacy'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('syndromes'), '[{"syndrome_id":"P003"}]');
      expect(
        rows.single.readNullable<String>('excluded_json'),
        isNull,
        reason:
            '存量行恒 NULL（不回头猜测历史轮次排除了什么）；'
            '若迁移里 UPDATE 回填 ⇒ 本断言红',
      );
    });

    test('M2 幂等：同一库连开两次不抛错，列仍在、存量行仍 NULL', () async {
      final path = createV49DbFile();
      final db1 = await _openPath(path, autoClose: false);
      await db1.close();

      final db2 = await _openPath(path);
      expect(
        await _columns(db2, 'diagnosis_results'),
        contains('excluded_json'),
      );
      final rows = await db2
          .customSelect(
            "SELECT excluded_json FROM diagnosis_results WHERE id = 'dr-legacy'",
          )
          .get();
      expect(rows.single.readNullable<String>('excluded_json'), isNull);
    });

    test('M3 边界：极老库无 diagnosis_results 表 → v50 块跳过，升级不抛错', () async {
      final db = await _openPath(createNoTableDbFile());
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), kSchemaHead);
      expect(await _columns(db, 'diagnosis_results'), isEmpty);
    });
  });
}
