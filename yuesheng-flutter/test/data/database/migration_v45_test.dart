// ─────────────────────────────────────────────────────────────
// migration_v45_test — C147 记录条目 target_section 列迁移测试
//
// v45 = ALTER record_entry ADD COLUMN target_section TEXT NOT NULL DEFAULT ''
//   （作者在确认卡里自选归入位置：'' 未定 / character 人设 / outline 大纲 /
//     world 世界观）。加法式、零数据搬迁：存量行默认 ''。
//
// 覆盖（对齐 v44 测试范式）：
//   1. v44 存量库升级 → target_section 列存在、user_version == kSchemaHead
//   2. 存量行（v44 建、无该列）升级后默认 ''（未定）
//   3. proposePending 带 targetSection 往返；updateExcerpt 可改摘录
//   4. 幂等：v45 库重复打开不报错
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/record_entry_repository.dart';
import '../../test_support/schema_head.dart';

var _dbSeq = 0;

String _tempPath(String tag) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'yuesheng_v45_${tag}_${_dbSeq++}.db';

/// v44 存量库：record_entry 表按 v44 原样（无 target_section 列）建 +
/// 最小 sessions 表 + user_version = 44。v45 迁移块是 ALTER ADD COLUMN。
String createV44LegacyDbFile() {
  final path = _tempPath('v44');
  final db = sqlite3.sqlite3.open(path);
  db.execute('PRAGMA foreign_keys = ON');
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
  // v44 原样（无 target_section）
  db.execute('''
    CREATE TABLE record_entry (
      id            TEXT NOT NULL PRIMARY KEY,
      manuscript_id TEXT NOT NULL,
      session_id    TEXT NOT NULL DEFAULT '',
      message_id    TEXT,
      excerpt       TEXT NOT NULL DEFAULT '',
      status        TEXT NOT NULL DEFAULT 'pending'
                    CHECK(status IN ('pending','kept','rejected')),
      decided_at    INTEGER,
      created_at    INTEGER NOT NULL DEFAULT (unixepoch())
    )
  ''');
  // 存量行（v44 时代建，无 target_section 概念）
  db.execute(
    "INSERT INTO record_entry (id, manuscript_id, excerpt, status) "
    "VALUES ('r-old', 'm1', '存量旧摘录。', 'pending')",
  );
  db.execute('PRAGMA user_version = 44');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v45_'),
    )) {
      f.deleteSync();
    }
  });

  test(
    '#1 v44 → v45 升级：target_section 列存在、user_version=$kSchemaHead',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase(File(createV44LegacyDbFile())),
      );
      addTearDown(db.close);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), kSchemaHead);
      final cols = await db
          .customSelect('PRAGMA table_info(record_entry)')
          .get();
      expect(
        cols.any((r) => r.read<String>('name') == 'target_section'),
        isTrue,
        reason: 'v45：record_entry 应新增 target_section 列',
      );
    },
  );

  test('#2 存量行升级后 target_section 默认 ""（未定）', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV44LegacyDbFile())),
    );
    addTearDown(db.close);
    final row = await db
        .customSelect(
          "SELECT target_section FROM record_entry WHERE id = 'r-old'",
        )
        .getSingle();
    expect(row.read<String>('target_section'), '');
  });

  test('#3 proposePending 带 targetSection 往返；updateExcerpt 可改摘录', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = RecordEntryRepository(db);

    final e = await repo.proposePending(
      manuscriptId: 'm1',
      excerpt: '阿禾抬头看了一眼天色。',
      targetSection: 'character',
    );
    expect(e.targetSection, 'character');

    await repo.updateExcerpt(e.id, '阿禾抬头看了一眼灰沉沉的天色。');
    final after = await repo.listPending('m1');
    expect(after.single.excerpt, '阿禾抬头看了一眼灰沉沉的天色。');
    expect(after.single.targetSection, 'character');
  });

  test('#4 幂等：v45 库重复打开不报错', () async {
    final path = createV44LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.close();
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    await db2.close();
  });
}
