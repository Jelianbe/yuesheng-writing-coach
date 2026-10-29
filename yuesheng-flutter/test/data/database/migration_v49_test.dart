// ─────────────────────────────────────────────────────────────
// migration_v49_test — ADR-0011 `messages.truncated`（断流标记落库）
//
// 覆盖（判据见 `.ai/adr/0011-断流标记落库与迁移守卫复位.md §5`）：
//   A2  存量库升级：加列成功 / 存量行 0 / content 逐字不变 / 升到 kSchemaHead
//   A2b 幂等：重复打开不抛错、值不变
//   A1  库层往返：markMessageTruncated 跨实例保留（关库 → 重开）
//   A3  不误标：未显式标记的行恒为 0（正常回复的默认态）
//   边界 无 messages 表的库 → 升级不抛错（表存在性守卫）
//
// ⚠️ A2 的夹具是**手写 v48 DDL**（messages 无 truncated 列），
//    用前先删同名临时文件：`flutter test` 跨轮次残留会撞 `table already exists`。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';

import '../../test_support/schema_head.dart';

var _dbSeq = 0;

String _tempPath(String tag) {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'yuesheng_v49_${tag}_${_dbSeq++}_${DateTime.now().microsecondsSinceEpoch}.db';
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  return path;
}

/// v48 存量库：messages 为 v49 **之前**的列集（无 truncated），含 1 条存量行。
String createV48DbFile() {
  final path = _tempPath('v48');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE messages (
      id TEXT NOT NULL PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      role TEXT NOT NULL CHECK (role IN ('user','assistant','system')),
      content TEXT NOT NULL,
      timestamp INTEGER NOT NULL DEFAULT (unixepoch()),
      message_type TEXT NOT NULL DEFAULT 'chat',
      references_json TEXT
    );
  ''');
  db.execute("INSERT INTO sessions (id) VALUES ('s1')");
  db.execute(
    "INSERT INTO messages (id, session_id, role, content, timestamp, message_type) "
    "VALUES ('m-legacy', 's1', 'assistant', '半截回复（存量行）', 100, 'chat')",
  );
  db.execute('PRAGMA user_version = 48');
  db.dispose();
  return path;
}

/// 没有 `messages` 表的库（`user_version = 48`）：v49 块必须靠表存在性守卫跳过，
/// 直接 `ALTER` 会抛「no such table」。列集版本无关 —— 本夹具只钉表守卫这一条边界。
String createNoMessagesDbFile() {
  final path = _tempPath('no_messages');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL DEFAULT 0
    );
  ''');
  db.execute('PRAGMA user_version = 48');
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
  group('v49 messages.truncated（ADR-0011）', () {
    test('A2 v48 存量库升级：加列 / 存量行 0 / content 逐字不变 / 版本升到 head', () async {
      final db = await _openPath(createV48DbFile());

      expect(await _columns(db, 'messages'), contains('truncated'));

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), kSchemaHead);

      final rows = await SessionRepository(db).listMessages('s1');
      expect(rows, hasLength(1));
      expect(rows.single.id, 'm-legacy');
      expect(rows.single.content, '半截回复（存量行）');
      expect(
        rows.single.truncated,
        0,
        reason: '存量行必须默认 0（DEFAULT 改成 1 或迁移里 UPDATE ⇒ 本断言红）',
      );
    });

    test('A2b 幂等：同一库连开两次不抛错，值与内容不变', () async {
      final path = createV48DbFile();
      final db1 = await _openPath(path, autoClose: false);
      final first = (await SessionRepository(
        db1,
      ).listMessages('s1')).single.truncated;
      await db1.close();

      final db2 = await _openPath(path);
      final again = await SessionRepository(db2).listMessages('s1');
      expect(again, hasLength(1));
      expect(again.single.truncated, first);
      expect(again.single.content, '半截回复（存量行）');
      expect(await _columns(db2, 'messages'), contains('truncated'));
    });

    test('A1 库层往返：markMessageTruncated 关库重开后仍在', () async {
      final path = _tempPath('roundtrip');
      final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
      await db1.customSelect('PRAGMA user_version').getSingle();
      final repo = SessionRepository(db1);
      final sid = await repo.createBlankSession();
      final id = await repo.addMessage(sid, 'assistant', '半截内容');
      await repo.markMessageTruncated(id);
      await db1.close();

      final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
      addTearDown(db2.close);
      await db2.customSelect('PRAGMA user_version').getSingle();
      final rows = await SessionRepository(db2).listMessages(sid);
      expect(rows, hasLength(1));
      expect(rows.single.truncated, 1, reason: '去 DB 写 ⇒ 红');
      expect(rows.single.content, '半截内容', reason: '标记不得改写正文');
    });

    test('A3 不误标：未调用 mark 的行恒为 0（正常回复的默认态）', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SessionRepository(db);
      final sid = await repo.createBlankSession();
      final id = await repo.addMessage(sid, 'assistant', '完整回复');

      final fresh = await repo.getMessage(id);
      expect(
        fresh!.truncated,
        0,
        reason:
            '本条只钉「默认值/写入显式性」（新建行不写即为 0）。'
            '「判定点改恒写 ⇒ 红」由 c121_microtask_diagnosis_loop_test '
            '的「有 isDone」用例承担 —— 那条才触碰 `!sawDone` 条件本身。',
      );

      await repo.markMessageTruncated(id);
      expect((await repo.getMessage(id))!.truncated, 1);
    });

    test('边界：极老库无 messages 表 → v49 块跳过，升级不抛错', () async {
      final db = await _openPath(createNoMessagesDbFile());
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), kSchemaHead);
      expect(await _columns(db, 'messages'), isEmpty);
    });
  });
}
