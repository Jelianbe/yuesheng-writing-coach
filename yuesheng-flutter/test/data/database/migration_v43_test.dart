// ─────────────────────────────────────────────────────────────
// migration_v43_test — ADR-C132 批1 edit_diff_event 表迁移测试
//
// v43 = 新建写作修改事件表 edit_diff_event
//       （diff 位置级 diff / anchor_ack 指认 / completion 成稿，
//       北极星漏斗底端「反馈后修改」分析，埋点先行纪律）。
//
// 覆盖（对齐 v41/v42 测试范式）：
//   1. v42 存量库升级 → 表存在、索引存在、user_version == kSchemaHead
//   2. 三类事件类型可写（CHECK 约束放行）且字段往返
//   3. 非法事件类型被 CHECK 拒绝（约束生效）
//   4. 幂等：v43 库重复打开不报错、不重复建表
//
// ★ v43 是 DDL-only：零数据变换先例（ADR-C96 §6.4）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import '../../test_support/schema_head.dart';

var _dbSeq = 0;

String _tempPath(String tag) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'yuesheng_v43_${tag}_${_dbSeq++}.db';

/// v42 存量库：仅含 sessions/chapters 最小 schema + PRAGMA user_version = 42。
/// 迁移 v43 块是 CREATE TABLE，不依赖任何既有表，最小 schema 库即可覆盖。
String createV42LegacyDbFile() {
  final path = _tempPath('v42');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE sessions (
      id         TEXT PRIMARY KEY,
      title      TEXT NOT NULL DEFAULT '新建会话',
      preview    TEXT NOT NULL DEFAULT '',
      diagnosis_summary TEXT NOT NULL DEFAULT '{}',
      created_at INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute('''
    CREATE TABLE chapters (
      id            TEXT PRIMARY KEY,
      manuscript_id TEXT NOT NULL,
      title         TEXT NOT NULL DEFAULT '',
      content       TEXT NOT NULL DEFAULT '',
      word_count    INTEGER NOT NULL DEFAULT 0,
      sort_order    INTEGER NOT NULL DEFAULT 0,
      status        TEXT NOT NULL DEFAULT 'draft',
      created_at    INTEGER NOT NULL DEFAULT (unixepoch()),
      updated_at    INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  db.execute('PRAGMA user_version = 42');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v43_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v42 → v43 升级：表 + 索引存在、user_version=$kSchemaHead', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV42LegacyDbFile())),
    );
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    expect(await db.tableExists('edit_diff_event'), isTrue);
    final idx = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_edit_diff_event_chapter'",
        )
        .get();
    expect(idx, isNotEmpty, reason: 'v43：edit_diff_event 章节索引应存在');
  });

  test('#2 三类事件类型可写且字段往返', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = EditDiffEventRepository(db);

    await repo.recordDiff(
      EditDiffInput(
        sessionId: 's1',
        chapterId: 'c1',
        messageId: 'm1',
        anchorStart: 3,
        anchorEnd: 9,
        beforeText: '他走了过去。',
        afterText: '他慢慢走了过去。',
        diffSegments: 1,
      ),
    );
    await repo.recordAnchorAcknowledged(
      sessionId: 's1',
      chapterId: 'c1',
      messageId: 'm1',
      anchorStart: 3,
      anchorEnd: 6,
      anchorText: '走了过去',
    );
    await repo.recordCompletion(sessionId: 's1', chapterId: 'c1');

    final byChapter = await repo.listByChapter('c1');
    expect(byChapter, hasLength(3));
    // 同秒写入 createdAt 相同，升序不保证插入序 → 按事件类型分组断言。
    final byType = {for (final e in byChapter) e.eventType: e};
    expect(byType[EditDiffEventTypes.diff]!.beforeText, '他走了过去。');
    expect(byType[EditDiffEventTypes.diff]!.afterText, '他慢慢走了过去。');
    expect(byType[EditDiffEventTypes.anchorAck]!.afterText, '走了过去');
    expect(byType[EditDiffEventTypes.completion]!.chapterId, 'c1');
  });

  test('#3 CHECK 约束拒绝非法事件类型', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(
      () => db
          .into(db.editDiffEvents)
          .insert(
            EditDiffEventsCompanion.insert(
              id: 'e-bad',
              chapterId: 'c1',
              eventType: 'not_a_type',
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('#4 幂等：v43 库重复打开不报错、不重复建表', () async {
    final path = createV42LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.close();
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    expect(await db2.tableExists('edit_diff_event'), isTrue);
    await db2.close();
  });
}
