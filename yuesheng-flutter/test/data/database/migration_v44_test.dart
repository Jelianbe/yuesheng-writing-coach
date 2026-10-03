// ─────────────────────────────────────────────────────────────
// migration_v44_test — ADR-C143 书籍资料库 v44 迁移测试
//
// v44 = 新建两张事件表：
//   record_entry   记录条目（提议式留痕，pending→kept/rejected）
//   material_entry 资料条目（存原文，summary 仅 on-demand）
//
// 覆盖（对齐 v41/v43 测试范式）：
//   1. v43 存量库升级 → 两表 + 索引存在、user_version == kSchemaHead
//   2. 两表可写、字段往返（经 Repository）
//   3. CHECK 约束拒绝非法 status；material UNIQUE(manuscript_id,url) 去重
//   4. 幂等：v44 库重复打开不报错
//
// ★ v44 是 DDL-only：零数据变换（ADR-C96 §6.4 零搬迁先例）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/material_entry_repository.dart';
import 'package:writingcoach/data/repositories/record_entry_repository.dart';
import '../../test_support/schema_head.dart';

var _dbSeq = 0;

String _tempPath(String tag) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'yuesheng_v44_${tag}_${_dbSeq++}.db';

/// v43 存量库：仅含 sessions/chapters 最小 schema + PRAGMA user_version = 43。
/// v44 迁移块是 CREATE TABLE，不依赖任何既有表，最小 schema 库即可覆盖。
String createV43LegacyDbFile() {
  final path = _tempPath('v43');
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
  db.execute('PRAGMA user_version = 43');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v44_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v43 → v44 升级：两表 + 索引存在、user_version=$kSchemaHead', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV43LegacyDbFile())),
    );
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    expect(await db.tableExists('record_entry'), isTrue);
    expect(await db.tableExists('material_entry'), isTrue);
    for (final idx in const [
      'idx_record_entry_manuscript',
      'idx_material_entry_manuscript',
    ]) {
      final row = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name = ?",
            variables: [Variable.withString(idx)],
          )
          .get();
      expect(row, isNotEmpty, reason: 'v44：索引 $idx 应存在');
    }
  });

  test('#2 两表经 Repository 可写、字段往返', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final recRepo = RecordEntryRepository(db);
    final matRepo = MaterialEntryRepository(db);

    // 记录条目：pending 提议 → excerpt 原样
    final rec = await recRepo.proposePending(
      manuscriptId: 'm1',
      sessionId: 's1',
      messageId: 'msg1',
      excerpt: '阿禾推开那扇吱呀作响的木门。',
    );
    expect(rec.status, RecordEntryStatus.pending);
    expect(rec.excerpt, '阿禾推开那扇吱呀作响的木门。');
    expect(rec.messageId, 'msg1');

    // 资料条目：存原文，summary 默认 null
    final mat = await matRepo.saveOriginal(
      manuscriptId: 'm1',
      url: 'https://example.com/a',
      sourceName: 'example.com',
      originalText: '原文段落一。\n原文段落二。',
      keySnippet: '原文段落一。',
      anchor: '#section-1',
    );
    expect(mat.status, MaterialEntryStatus.kept);
    expect(mat.summary, isNull, reason: '默认存路径不生成摘要');
    expect(mat.sourceCredibility, SourceCredibility.unknown);
    expect(mat.sourceName, 'example.com');
    expect(mat.anchor, '#section-1');
  });

  test('#3 CHECK 拒绝非法 status；material UNIQUE(manuscript_id,url) 去重', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(
      () => db
          .into(db.recordEntries)
          .insert(
            RecordEntriesCompanion.insert(
              id: 'r-bad',
              manuscriptId: 'm1',
              status: const Value('godzilla'),
            ),
          ),
      throwsA(isA<SqliteException>()),
    );

    final matRepo = MaterialEntryRepository(db);
    await matRepo.saveOriginal(manuscriptId: 'm1', url: 'https://x.com/1');
    // 同 (manuscript_id, url) 再存 → UNIQUE 冲突
    expect(
      () => matRepo.saveOriginal(manuscriptId: 'm1', url: 'https://x.com/1'),
      throwsA(isA<SqliteException>()),
    );
    // url 为 null 的粘贴原文不互相冲突（SQLite UNIQUE 视 NULL 互不相同）
    await matRepo.saveOriginal(manuscriptId: 'm1', originalText: '无链接原文A');
    await matRepo.saveOriginal(manuscriptId: 'm1', originalText: '无链接原文B');
    final all = await matRepo.listByManuscript('m1');
    expect(all.where((e) => e.url == null).length, 2);
  });

  test('#4 幂等：v44 库重复打开不报错、不重复建表', () async {
    final path = createV43LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.close();
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), kSchemaHead);
    expect(await db2.tableExists('record_entry'), isTrue);
    expect(await db2.tableExists('material_entry'), isTrue);
    await db2.close();
  });
}
