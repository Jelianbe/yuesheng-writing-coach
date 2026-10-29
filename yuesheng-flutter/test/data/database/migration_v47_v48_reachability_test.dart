// ─────────────────────────────────────────────────────────────
// migration_v47_v48_reachability_test — ADR-0011 §2 的回归钉（判据 A4）
//
// 钉住的是**守卫与 schemaVersion 的一致性**：
//   v47（reflection_question 建表）与 v48（active_problem 加两列）此前排在
//   `if (from >= 46) return;` **之后** ⇒ `from ∈ {46,47,48}` 的库整段跳过，
//   drift 仍把 user_version 写成新值（静默跳过）。实测探针读数：
//     PROBE user_version=48  reflection_question=false  form_fact_count=false
//                           form_structure=false
//
// ADR-0011 把守卫复位到 49 后，本文件断言 v46 库升级真能拿到 v47/v48 的产物。
// **判据强度**：把守卫改回 46 ⇒ 两条断言同时红（不是恒真断言）。
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
      'yuesheng_v47v48_${tag}_${_dbSeq++}_${DateTime.now().microsecondsSinceEpoch}.db';
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  return path;
}

/// v46 存量库：active_problem 为**加 v48 两列之前**的形态，且无 reflection_question。
String createV46DbFile() {
  final path = _tempPath('v46');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE active_problem (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      syndrome_id TEXT NOT NULL,
      syndrome_name TEXT NOT NULL DEFAULT '',
      severity TEXT NOT NULL DEFAULT 'L2',
      status TEXT NOT NULL DEFAULT 'active',
      confirmation_status TEXT NOT NULL DEFAULT 'suspected',
      teaching_state TEXT,
      confirmed_at INTEGER,
      evidence_confidence REAL,
      created_at INTEGER NOT NULL DEFAULT 0,
      resolved_at INTEGER,
      updated_at INTEGER
    );
  ''');
  db.execute("INSERT INTO sessions (id) VALUES ('s1')");
  db.execute(
    "INSERT INTO active_problem (id, session_id, syndrome_id, created_at) "
    "VALUES ('ap1', 's1', 'P034', 1)",
  );
  db.execute('PRAGMA user_version = 46');
  db.dispose();
  return path;
}

Future<AppDatabase> _openPath(String path, {bool autoClose = true}) async {
  final db = AppDatabase.forTesting(NativeDatabase(File(path)));
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

Future<bool> _tableExists(AppDatabase db, String table) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '$table'",
      )
      .get();
  return rows.isNotEmpty;
}

void main() {
  group('A4 守卫复位：v46 库升级后 v47/v48 的产物必须存在', () {
    test('reflection_question 表 + active_problem 两列都拿到，且版本升到 head', () async {
      final db = await _openPath(createV46DbFile());

      expect(
        await _tableExists(db, 'reflection_question'),
        isTrue,
        reason: 'v47 建表被跳过 ⇒ 守卫又回到 46 以下（ADR-0011 §2）',
      );

      final apCols = await _columns(db, 'active_problem');
      expect(
        apCols,
        containsAll(<String>['form_fact_count', 'form_structure']),
        reason: 'v48 两列被跳过 ⇒ 守卫又回到 46 以下（ADR-0011 §2）',
      );

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), kSchemaHead);

      // 存量行原样保留（迁移只加表/加列，不碰数据）
      final ap = await db
          .customSelect(
            "SELECT syndrome_id FROM active_problem WHERE id = 'ap1'",
          )
          .getSingle();
      expect(ap.read<String>('syndrome_id'), 'P034');
    });

    test('幂等：连开两次，v47/v48 产物仍在且不抛 duplicate column/table', () async {
      final path = createV46DbFile();
      final db1 = await _openPath(path, autoClose: false);
      final cols1 = await _columns(db1, 'active_problem');
      await db1.close();

      final db2 = await _openPath(path);
      expect(await _tableExists(db2, 'reflection_question'), isTrue);
      expect(await _columns(db2, 'active_problem'), cols1);
    });
  });
}
