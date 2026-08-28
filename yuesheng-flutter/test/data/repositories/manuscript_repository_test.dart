// ─────────────────────────────────────────────────────────────
// manuscript_repository_test — 批次94-5 标签落库仓储单元测试
//
// 覆盖：
//   1. parseTags：合法 JSON string[] / 非法 JSON / 非数组 / 混入非字符串
//   2. createManuscript 带 tags → 落库 → parseTags 读回
//   3. updateManuscript(tags:) → 更新落库
//   4. 未传 tags 的 update 不清空既有 tags
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';

void main() {
  late AppDatabase db;
  late ManuscriptRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ManuscriptRepository(db);
  });

  tearDown(() async => db.close());

  group('parseTags（批次94-5）', () {
    test('#1 合法 JSON string[] → 原样返回', () {
      final m = Manuscript(
        id: 'm1',
        title: 't',
        description: '',
        genre: '',
        tags: '["重生","系统"]',
        language: '中文',
        status: 'active',
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(ManuscriptRepository.parseTags(m), ['重生', '系统']);
    });

    test('#2 非法 JSON → 空列表（容错）', () {
      final m = Manuscript(
        id: 'm1',
        title: 't',
        description: '',
        genre: '',
        tags: 'not-json{',
        language: '中文',
        status: 'active',
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(ManuscriptRepository.parseTags(m), isEmpty);
    });

    test('#3 非数组 JSON → 空列表（容错）', () {
      final m = Manuscript(
        id: 'm1',
        title: 't',
        description: '',
        genre: '',
        tags: '{"a":1}',
        language: '中文',
        status: 'active',
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(ManuscriptRepository.parseTags(m), isEmpty);
    });

    test('#4 混入非字符串元素 → 仅保留字符串', () {
      final m = Manuscript(
        id: 'm1',
        title: 't',
        description: '',
        genre: '',
        tags: '["重生", 42, null]',
        language: '中文',
        status: 'active',
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(ManuscriptRepository.parseTags(m), ['重生']);
    });
  });

  group('tags 落库读写（批次94-5）', () {
    test('#5 createManuscript(tags:) → 读回一致', () async {
      final id = await repo.createManuscript(title: '测试稿', tags: ['重生', '系统']);
      final m = await repo.getManuscript(id);
      expect(ManuscriptRepository.parseTags(m!), ['重生', '系统']);
    });

    test('#6 updateManuscript(tags:) → 更新落库', () async {
      final id = await repo.createManuscript(title: '测试稿');
      await repo.updateManuscript(id, tags: ['悬疑', '修仙']);
      final m = await repo.getManuscript(id);
      expect(ManuscriptRepository.parseTags(m!), ['悬疑', '修仙']);
    });

    test('#7 未传 tags 的 update 不清空既有 tags', () async {
      final id = await repo.createManuscript(title: '测试稿', tags: ['甜宠']);
      await repo.updateManuscript(id, title: '改名');
      final m = await repo.getManuscript(id);
      expect(ManuscriptRepository.parseTags(m!), ['甜宠']);
    });

    test('#8 未传 tags 的 create 落库为空数组', () async {
      final id = await repo.createManuscript(title: '测试稿');
      final m = await repo.getManuscript(id);
      expect(ManuscriptRepository.parseTags(m!), isEmpty);
    });
  });

  // =========================================================================
  // ABN-02 故障复现：Windows 真机 release 点击「新建作品」静默失败
  //
  // 假设 1：内存 DB = 全新 onCreate 库，NOT NULL/DEFAULT 全按最新形态生成；
  //        真实 release 机库：getApplicationDocumentsDirectory() 下 on-disk 文件，
  //        由 v12/v22/v23 存量库经 onUpgrade 迁移链升级到 v26，且跨会话关闭/重开。
  // 假设 2：onUpgrade v23→v24→v25→v26 迁移链里 ALTER TABLE manuscripts ADD COLUMN tags
  //        未附带 DEFAULT（SQLite 限制），升级成功但在升级后的存量库上 INSERT 不传 tags
  //        → CHECK 或 NOT NULL 失败（memory DB 走 onCreate 无此问题）。
  // =========================================================================
  group('ABN-02 复现：on-disk / 存量迁移后 createManuscript', () {
    /// 构造独立 on-disk 路径：模拟真实 release 机的持久化文件（非 memory）
    String _tmpDbPath(String suffix) {
      _dbSeq++;
      return '${Directory.systemTemp.path}${Platform.pathSeparator}abn02_${suffix}_$_dbSeq.db';
    }

    test('#A1 on-disk fresh DB (onCreate v26) → createManuscript 成功', () async {
      final path = _tmpDbPath('fresh');
      final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
      addTearDown(() async {
        await db1.close();
        try { File(path).deleteSync(); } catch (_) {}
      });
      final freshRepo = ManuscriptRepository(db1);
      final id = await freshRepo.createManuscript(
        title: 'on-disk 测试作品',
        description: '简介',
        genre: '科幻',
        tags: ['ABN', '02'],
      );
      final m = await freshRepo.getManuscript(id);
      expect(m, isNotNull);
      expect(m!.title, 'on-disk 测试作品');
      expect(ManuscriptRepository.parseTags(m), ['ABN', '02']);
      final list = await freshRepo.listManuscripts();
      expect(list.length, 1);
    });

    test('#A2 on-disk DB 关闭后重开 → createManuscript 成功 (跨会话写入)', () async {
      final path = _tmpDbPath('reopen');
      addTearDown(() { try { File(path).deleteSync(); } catch (_) {} });
      // Round 1: open → write m1 → close
      final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
      final id1 = await ManuscriptRepository(db1).createManuscript(title: '会话-1 稿');
      expect(await ManuscriptRepository(db1).getManuscript(id1), isNotNull);
      await db1.close();
      // Round 2: reopen → write m2 → list should be 2
      final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
      final repo2 = ManuscriptRepository(db2);
      final id2 = await repo2.createManuscript(title: '会话-2 稿');
      expect(await repo2.getManuscript(id2), isNotNull);
      final list = await repo2.listManuscripts();
      expect(list.length, 2, reason: '跨会话重开后应该有 2 条');
      await db2.close();
    });

    test('#B1 v23 存量库升级到 v26 → createManuscript 成功（最接近真实机：v23 seed 直接复用 migration_v24_test 官方形态）', () async {
      // ABN-02 说明：v23 官方真形态（createV23LegacyDbFile 同款）= 已包含 volumes 表 +
      // chapters.volume_id + chapters.previous_content。migration 测试从 v23→v25→v26
      // 升级链本就应该正确。本用例作用：验证升级后 createManuscript INSERT 正常，
      // 不是测试 migration 本体。真机 ABN-02 的真因极可能在 Provider/文件权限，不在 schema。
      final path = _tmpDbPath('v23_upgrade');
      addTearDown(() { try { File(path).deleteSync(); } catch (_) {} });
      // ── 以下 seed 严格复刻 migration_v24_test.dart createV23LegacyDbFile() ──
      final seed = sqlite3.sqlite3.open(path);
      seed.execute('PRAGMA user_version = 23');
      seed.execute('''
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
      seed.execute('''
        CREATE TABLE volumes (
          id            TEXT PRIMARY KEY,
          manuscript_id TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
          title         TEXT NOT NULL DEFAULT '',
          sort_order    INTEGER NOT NULL DEFAULT 0,
          created_at    INTEGER NOT NULL DEFAULT 0,
          updated_at    INTEGER NOT NULL DEFAULT 0
        )
      ''');
      seed.execute('''
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
      // sessions (onUpgrade v22→v23 其它表也需要，最小集合：migration 链各表不炸即可)
      seed.execute('''
        CREATE TABLE sessions (id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '', preview TEXT NOT NULL DEFAULT '', manuscript_id TEXT DEFAULT NULL REFERENCES manuscripts(id) ON DELETE SET NULL, chapter_id TEXT DEFAULT NULL, diagnosis_summary TEXT NOT NULL DEFAULT '{}', created_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0)
      ''');
      seed.execute(
        "INSERT INTO manuscripts(id,title,description,genre,language,status,sort_order,created_at,updated_at) "
        "VALUES ('old-m1','存量作品','v23 已有','','中文','active',0,1700000000,1700000000)",
      );
      seed.execute(
        "INSERT INTO volumes(id,manuscript_id,title,sort_order,created_at,updated_at) "
        "VALUES ('v1','old-m1','第一卷',0,1700000000,1700000000)",
      );
      seed.execute(
        "INSERT INTO chapters(id,manuscript_id,volume_id,title,content,previous_content,word_count,sort_order,status,last_diagnosed_at,created_at,updated_at) "
        "VALUES ('c1','old-m1','v1','第一章','存量正文',NULL,9,0,'draft',NULL,1700000000,1700000000)",
      );
      seed.dispose();

      // 2. drift 打开 → onUpgrade(23→24→25→26)
      final db = AppDatabase.forTesting(NativeDatabase(File(path)));
      addTearDown(db.close);
      final ver = await db.customSelect('PRAGMA user_version').getSingle();
      expect(ver.read<int>('user_version'), 26);

      // 3. 升级后 createManuscript
      final upgradedRepo = ManuscriptRepository(db);
      final before = await upgradedRepo.listManuscripts();
      expect(before.length, 1);

      final newId = await upgradedRepo.createManuscript(
        title: 'ABN-02 新稿（v23→v26 后）',
        description: '迁移链无错，插入正常',
        genre: '悬疑',
        tags: ['test', 'ABN02'],
      );
      final newM = await upgradedRepo.getManuscript(newId);
      expect(newM, isNotNull);
      expect(newM!.title, startsWith('ABN-02'));
      expect(ManuscriptRepository.parseTags(newM), ['test', 'ABN02']);

      final after = await upgradedRepo.listManuscripts();
      expect(after.length, 2);
    });
  });
}

int _dbSeq = 0;
