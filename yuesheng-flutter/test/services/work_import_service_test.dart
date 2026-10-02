// ─────────────────────────────────────────────────────────────
// WorkImportService 单元测试 — 作品导入链路
// 验证：事务内建稿件 + 逐章建章节 + 设主引用，失败整体回滚
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';
import 'package:writingcoach/services/file_parser.dart';
import 'package:writingcoach/services/work_import_service.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessRepo;
  late WorkImportService service;
  late ManuscriptRepository msRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessRepo = SessionRepository(db);
    msRepo = ManuscriptRepository(db);
    service = WorkImportService(
      db,
      msRepo,
      ChapterRepository(db),
      ReferenceRepository(db),
      VolumeRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  ParsedFile sampleParsed() => ParsedFile(
    title: '测试作品',
    genre: '未知',
    chapters: [
      ParsedChapter(title: '第一章', content: '正文一'),
      ParsedChapter(title: '第二章', content: '正文二'),
    ],
  );

  Future<List<Chapter>> listChapters(String manuscriptId) async {
    return (db.select(db.chapters)
          ..where((t) => t.manuscriptId.equals(manuscriptId))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
  }

  // ════════════════════════════════════════════════════════════
  // 1. importWork — 核心链路
  // ════════════════════════════════════════════════════════════
  group('importWork', () {
    test('建稿件 + 全部章节 + 主引用', () async {
      final sessionId = await sessRepo.createBlankSession();

      final result = await service.importWork(
        sessionId: sessionId,
        parsed: sampleParsed(),
      );

      expect(result.manuscriptId, isNotEmpty);
      expect(result.firstChapterId, isNotEmpty);
      expect(result.chapterCount, 2);
      expect(result.totalWords, '正文一'.length + '正文二'.length);

      // 稿件字段
      final ms = await db.select(db.manuscripts).getSingle();
      expect(ms.title, '测试作品');
      expect(ms.genre, '未知');
      expect(ms.description, '从文件导入的作品（2章）');

      // 章节：标题/内容/sort_order/word_count
      final chapters = await listChapters(result.manuscriptId);
      expect(chapters.length, 2);
      expect(chapters[0].title, '第一章');
      expect(chapters[0].content, '正文一');
      expect(chapters[0].sortOrder, 0); // C116-B2：导入三路统一 0 基（手动/批量本就 0 基）
      expect(chapters[0].wordCount, '正文一'.length);
      expect(chapters[1].title, '第二章');
      expect(chapters[1].sortOrder, 1);

      // 主引用：chapter 类型 + is_primary=1
      final refs = await db.select(db.sessionReferences).get();
      expect(refs.length, 1);
      expect(refs.single.refType, 'chapter');
      expect(refs.single.refId, result.firstChapterId);
      expect(refs.single.isPrimary, 1);
      expect(refs.single.sessionId, sessionId);
    });

    test('带 volumeTitle 的章节 → 自动建卷并挂卷', () async {
      final sessionId = await sessRepo.createBlankSession();
      final parsed = ParsedFile(
        title: '卷书',
        genre: '未知',
        chapters: const [
          ParsedChapter(title: '第一章', content: '正文一', volumeTitle: '第一卷 风起'),
          ParsedChapter(title: '第二章', content: '正文二', volumeTitle: '第一卷 风起'),
          ParsedChapter(title: '第三章', content: '正文三', volumeTitle: '第二卷 云涌'),
          ParsedChapter(title: '尾声', content: '正文四'),
        ],
      );

      final result = await service.importWork(
        sessionId: sessionId,
        parsed: parsed,
      );

      expect(result.chapterCount, 4);

      // 卷：两个不同卷标题 → 2 卷，标题/序号正确
      final volumes = await db.select(db.volumes).get();
      expect(volumes.length, 2);
      expect(volumes.map((v) => v.title).toSet(), {'第一卷 风起', '第二卷 云涌'});

      // 章节挂卷：第一/二章归卷1，第三章归卷2，尾声未分卷
      final chapters = await listChapters(result.manuscriptId);
      final volByTitle = {for (final v in volumes) v.title: v.id};
      expect(chapters[0].volumeId, volByTitle['第一卷 风起']);
      expect(chapters[1].volumeId, volByTitle['第一卷 风起']);
      expect(chapters[2].volumeId, volByTitle['第二卷 云涌']);
      expect(chapters[3].volumeId, isNull);
    });

    test('重复导入同一解析结果 → 各建一份稿件，互不冲突', () async {
      final parsed = sampleParsed();
      final sessionId = await sessRepo.createBlankSession();

      final first = await service.importWork(
        sessionId: sessionId,
        parsed: parsed,
      );
      final second = await service.importWork(
        sessionId: sessionId,
        parsed: parsed,
      );

      expect(second.manuscriptId, isNot(first.manuscriptId));
      expect(await db.select(db.manuscripts).get().then((r) => r.length), 2);
      // 两个主引用并存（幂等由 UNIQUE 约束保证，不同 ref_id 互不覆盖）
      expect(
        await db.select(db.sessionReferences).get().then((r) => r.length),
        2,
      );
    });

    test('空章节 → 抛 StateError 且无残留', () async {
      final sessionId = await sessRepo.createBlankSession();

      await expectLater(
        service.importWork(
          sessionId: sessionId,
          parsed: ParsedFile(title: '空', genre: '未知', chapters: []),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await db.select(db.manuscripts).get(), isEmpty);
    });

    test('会话不存在 → addReference 外键失败 → 整体回滚无残留', () async {
      // 不存在的 sessionId，主引用插入会触发外键约束失败，
      // 整个事务必须回滚：稿件与章节都不得留下。
      await expectLater(
        service.importWork(
          sessionId: 'no-such-session',
          parsed: sampleParsed(),
        ),
        throwsA(isA<Exception>()),
      );

      expect(await db.select(db.manuscripts).get(), isEmpty);
      expect(await db.select(db.chapters).get(), isEmpty);
      expect(await db.select(db.sessionReferences).get(), isEmpty);
    });

    test('中途建章失败 → 已建的稿件/卷/章整体回滚无残留', () async {
      // 与「会话不存在」(失败在事务最后一步 addReference) 互补：
      // 本用例失败点在循环中途——稿件+卷+第一章已落库后，第二章写入抛错，
      // 外层事务必须把「已成功的半成品」一并回滚，不得留卷/章残行。
      final sessionId = await sessRepo.createBlankSession();
      service = WorkImportService(
        db,
        msRepo,
        _FlakySecondChapterRepo(db),
        ReferenceRepository(db),
        VolumeRepository(db),
      );
      final parsed = ParsedFile(
        title: '半途而废',
        genre: '未知',
        chapters: const [
          ParsedChapter(title: '第一章', content: '正文一', volumeTitle: '第一卷 风起'),
          ParsedChapter(title: '第二章', content: '正文二', volumeTitle: '第一卷 风起'),
        ],
      );

      await expectLater(
        service.importWork(sessionId: sessionId, parsed: parsed),
        throwsA(isA<Exception>()),
      );

      // 回滚后四类写入表全部为空：无半成品稿件/卷/章/主引用
      expect(await db.select(db.manuscripts).get(), isEmpty);
      expect(await db.select(db.volumes).get(), isEmpty);
      expect(await db.select(db.chapters).get(), isEmpty);
      expect(await db.select(db.sessionReferences).get(), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 2. importFromText — 粘贴文本链路
  // ════════════════════════════════════════════════════════════
  group('importFromText', () {
    test('带章节标记 → 按章拆并入稿', () async {
      final sessionId = await sessRepo.createBlankSession();
      final text = '第一章 初见\n第一段内容\n第二章 重逢\n第二段内容';

      final result = await service.importFromText(
        sessionId: sessionId,
        text: text,
      );

      expect(result.chapterCount, 2);
      final chapters = await listChapters(result.manuscriptId);
      expect(chapters[0].title, '第一章 初见');
      expect(chapters[0].content, '第一段内容');
      expect(chapters[1].title, '第二章 重逢');
      expect(chapters[1].content, '第二段内容');
    });

    test('无章节标记 → 兜底「第一章」整篇入库', () async {
      final sessionId = await sessRepo.createBlankSession();

      final result = await service.importFromText(
        sessionId: sessionId,
        text: '没有任何章节标记的正文内容',
      );

      expect(result.chapterCount, 1);
      final chapters = await listChapters(result.manuscriptId);
      expect(chapters.single.title, '第一章');
      expect(chapters.single.content, '没有任何章节标记的正文内容');
    });
  });
}

/// 测试替身：第一次 createChapter 走真实落库（经 super），第二次直接抛错。
/// 用于在 importWork 事务中途（稿件+卷+第一章已写、第二章将写）注入失败，
/// 验证外层事务把已成功的半成品整体回滚。不改生产代码。
class _FlakySecondChapterRepo extends ChapterRepository {
  _FlakySecondChapterRepo(super.db);
  int _calls = 0;

  @override
  Future<String> createChapter(
    String manuscriptId, {
    String? title,
    String? content,
    int? sortOrder,
    String? volumeId,
  }) async {
    _calls++;
    if (_calls >= 2) throw Exception('注入：第二个章节写入失败');
    return super.createChapter(
      manuscriptId,
      title: title,
      content: content,
      sortOrder: sortOrder,
      volumeId: volumeId,
    );
  }
}
