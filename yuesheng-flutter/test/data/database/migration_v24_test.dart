// ─────────────────────────────────────────────────────────────
// migration_v24_test — 批次94-2 v23 → v24 迁移路径测试（v25 标签列一并迁移到 25）
//
// 模拟真实升级：用 sqlite3 手工构造 v23 存量库文件（含 volumes 表 +
// chapters.volume_id，status CHECK 无 'archived'，manuscripts 无 tags），
// user_version = 23，再用 AppDatabase.forTesting 打开 → 触发 onUpgrade(23 → 24 → 25)。
//
// 覆盖：
//   1. 升级后 user_version = 25
//   2. 存量章节数据完整保留（含 volume_id 卷归属）
//   3. status CHECK 已扩展：可写入 status='archived'（回收站软删）
//   4. manuscripts.tags 列已补（v25 标签落库）
//   5. 幂等：v25 库二次打开不重复迁移、不报错
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';

var _dbSeq = 0;

/// 构造 v23 存量库文件（复刻批次89 迁移完成后的真实 schema）
String createV23LegacyDbFile() {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}yuesheng_v23_migration_${_dbSeq++}.db';
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
  db.execute('''
    INSERT INTO manuscripts (id, title, created_at, updated_at)
    VALUES ('m1', '存量测试稿', 100, 100)
  ''');
  db.execute('''
    INSERT INTO volumes (id, manuscript_id, title, sort_order, created_at, updated_at)
    VALUES ('v1', 'm1', '第一卷', 0, 100, 100)
  ''');
  db.execute('''
    INSERT INTO chapters (id, manuscript_id, volume_id, title, content, word_count, sort_order, status, created_at, updated_at)
    VALUES ('c1', 'm1', 'v1', '第一章', '存量正文', 4, 0, 'draft', 100, 100)
  ''');
  db.execute('PRAGMA user_version = 23');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v23_migration_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v23 → v25 升级：status CHECK 扩 archived + 存量保留（含卷归属）', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV23LegacyDbFile())),
    );
    addTearDown(db.close);

    // 1. user_version 升到 26
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 26);

    // 2. 存量章节保留（含 volume_id）
    final chapter = await ChapterRepository(db).getChapter('c1');
    expect(chapter, isNotNull);
    expect(chapter!.title, '第一章');
    expect(chapter.content, '存量正文');
    expect(chapter.volumeId, 'v1', reason: '存量卷归属保留');

    // 3. status CHECK 已扩展：可写入 'archived'（回收站软删）
    await ChapterRepository(db).softDeleteChapter('c1');
    expect((await ChapterRepository(db).getChapter('c1'))!.status, 'archived');
    final archived = await ChapterRepository(db).listArchivedChapters('m1');
    expect(archived.map((c) => c.id), contains('c1'));

    // 4. manuscripts.tags 列已补（v25 标签落库）
    final tagsCols = await db
        .customSelect(
          "SELECT name FROM pragma_table_info('manuscripts') WHERE name='tags'",
        )
        .get();
    expect(tagsCols.length, 1, reason: 'manuscripts 表缺少 tags 列');
  });

  test('#2 幂等：v26 库二次打开不重复迁移', () async {
    final path = createV23LegacyDbFile();

    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    // 第二次打开同一库（已是 v26），重建迁移不再触发，不应报「表已存在」类错误
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final chapter = await ChapterRepository(db2).getChapter('c1');
    expect(chapter!.status, 'draft');
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 26);
  });
}
