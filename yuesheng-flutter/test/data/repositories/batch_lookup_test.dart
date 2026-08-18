// ─────────────────────────────────────────────────────────────
// batch_lookup_test — A-3 遗留 N+1 消除：批量 DAO 方法单元测试
//
// 覆盖 4 个新增批量只读方法，锁定其与单条对应方法语义一致：
//   1. ChapterRepository.getChaptersByIds        （对齐 getChapter：不过滤 archived）
//   2. ChapterRepository.listChaptersForManuscripts（对齐 listChapters：过滤 archived + sortOrder）
//   3. ManuscriptRepository.getManuscriptsByIds   （对齐 getManuscript：不过滤 status）
//   4. ReferenceRepository.getAttachedFilesByIds  （对齐 getAttachedFile：字段映射一致）
// 另锁空列表守卫（避免 drift isIn([]) 生成非法 `IN ()` SQL）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';

void main() {
  late AppDatabase db;
  late ChapterRepository chRepo;
  late ManuscriptRepository msRepo;
  late ReferenceRepository refRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chRepo = ChapterRepository(db);
    msRepo = ManuscriptRepository(db);
    refRepo = ReferenceRepository(db);
  });

  tearDown(() async => db.close());

  group('ChapterRepository.getChaptersByIds', () {
    test('空列表守卫 → 返回空（不发 SQL）', () async {
      expect(await chRepo.getChaptersByIds(const []), isEmpty);
    });

    test('命中 + 未命中 → 仅返回命中的章节', () async {
      final msId = await msRepo.createManuscript(title: '稿');
      final c1 = await chRepo.createChapter(msId, title: '一', content: 'A');
      final c2 = await chRepo.createChapter(msId, title: '二', content: 'B');

      final result = await chRepo.getChaptersByIds([c1, '不存在', c2]);
      expect(result.map((c) => c.id).toSet(), {c1, c2});
      expect(result.map((c) => c.title).toSet(), {'一', '二'});
    });

    test('对齐 getChapter：被软删（archived）的章节仍返回', () async {
      final msId = await msRepo.createManuscript(title: '稿');
      final c1 = await chRepo.createChapter(msId, title: '一', content: 'A');
      await chRepo.softDeleteChapter(c1);

      // 单条 getChapter 不过滤 archived
      final single = await chRepo.getChapter(c1);
      expect(single, isNotNull);
      expect(single!.status, 'archived');

      // 批量同样返回 archived 章节（语义对齐）
      final batch = await chRepo.getChaptersByIds([c1]);
      expect(batch, hasLength(1));
      expect(batch.first.id, c1);
      expect(batch.first.status, 'archived');
    });
  });

  group('ChapterRepository.listChaptersForManuscripts', () {
    test('空列表守卫 → 返回空', () async {
      expect(
        await chRepo.listChaptersForManuscripts(const []),
        isEmpty,
      );
    });

    test('跨多稿件批量取章节，按 sortOrder 排序', () async {
      final msA = await msRepo.createManuscript(title: 'A');
      final msB = await msRepo.createManuscript(title: 'B');
      // 显式 sortOrder，验证跨稿件 ORDER BY sortOrder 升序：a1(0) < a2(1) < b1(2)
      final a1 = await chRepo.createChapter(msA, title: 'A1', sortOrder: 0);
      final a2 = await chRepo.createChapter(msA, title: 'A2', sortOrder: 1);
      final b1 = await chRepo.createChapter(msB, title: 'B1', sortOrder: 2);

      final result = await chRepo.listChaptersForManuscripts([msA, msB]);
      // 全局按 sortOrder 升序：a1 < a2 < b1
      expect(result.map((c) => c.title).toList(), ['A1', 'A2', 'B1']);
      expect(result.map((c) => c.manuscriptId).toSet(), {msA, msB});
    });

    test('对齐 listChapters：过滤 archived 章节', () async {
      final msA = await msRepo.createManuscript(title: 'A');
      final a1 = await chRepo.createChapter(msA, title: 'A1');
      final a2 = await chRepo.createChapter(msA, title: 'A2');
      await chRepo.softDeleteChapter(a2);

      final result = await chRepo.listChaptersForManuscripts([msA]);
      expect(result, hasLength(1));
      expect(result.first.id, a1);
    });
  });

  group('ManuscriptRepository.getManuscriptsByIds', () {
    test('空列表守卫 → 返回空', () async {
      expect(await msRepo.getManuscriptsByIds(const []), isEmpty);
    });

    test('命中 + 未命中 → 仅返回命中的稿件', () async {
      final m1 = await msRepo.createManuscript(title: '一', genre: '小说');
      final m2 = await msRepo.createManuscript(title: '二', genre: '散文');

      final result = await msRepo.getManuscriptsByIds([m1, '不存在', m2]);
      expect(result.map((m) => m.id).toSet(), {m1, m2});
      expect(result.map((m) => m.genre).toSet(), {'小说', '散文'});
    });

    test('对齐 getManuscript：被软删（archived）的稿件仍返回', () async {
      final m1 = await msRepo.createManuscript(title: '一');
      await msRepo.deleteManuscript(m1); // status='archived'

      final single = await msRepo.getManuscript(m1);
      expect(single, isNotNull);
      expect(single!.status, 'archived');

      final batch = await msRepo.getManuscriptsByIds([m1]);
      expect(batch, hasLength(1));
      expect(batch.first.status, 'archived');
    });
  });

  group('ReferenceRepository.getAttachedFilesByIds', () {
    test('空列表守卫 → 返回空', () async {
      expect(await refRepo.getAttachedFilesByIds(const []), isEmpty);
    });

    test('命中 + 未命中 + 字段映射一致', () async {
      final msId = await msRepo.createManuscript(title: '稿');
      final f1 = await refRepo.createAttachedFile(
        bookId: msId,
        fileName: '大纲.txt',
        fileRole: 'outline',
        content: '第一卷开端',
      );
      final f2 = await refRepo.createAttachedFile(
        bookId: msId,
        fileName: '笔记.txt',
        content: '一些笔记',
      );

      final result = await refRepo.getAttachedFilesByIds([f1.id, '不存在', f2.id]);
      expect(result, hasLength(2));
      final byId = {for (final f in result) f.id: f};

      final r1 = byId[f1.id]!;
      expect(r1.fileName, '大纲.txt');
      expect(r1.fileRole, 'outline');
      expect(r1.mimeType, 'text/plain');
      expect(r1.content, '第一卷开端');
      expect(r1.byteSize, '第一卷开端'.length);
      expect(r1.bookId, msId);

      // 默认 fileRole=general
      expect(byId[f2.id]!.fileRole, 'general');
    });
  });
}
