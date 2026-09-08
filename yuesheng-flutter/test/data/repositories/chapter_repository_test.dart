// ─────────────────────────────────────────────────────────────
// chapter_repository_test — 章节仓储单元测试
//
// 建立原因（CR-15）：chapter_repository 386 行、22 个 Future 方法，此前
// 无任何独立测试，仅被 dao_repository_test / batch_lookup_test 等间接覆盖。
//
// 覆盖：
//   1. createChapter 落指定卷
//   2. CR-14 回归：createChaptersBatch 支持 volumeId
//   3. 三态生命周期：软删 → 回收站 → 恢复 → 彻底删除
//   4. 软删章节不出现在 listChapters，且按 sort_order 排序
//   5. adoptContentToChapter / undoLastAdoption 内容往返
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';

void main() {
  late AppDatabase db;
  late ChapterRepository chapterRepo;
  late VolumeRepository volumeRepo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chapterRepo = ChapterRepository(db);
    volumeRepo = VolumeRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  test('#1 createChapter 落指定卷', () async {
    final v = await volumeRepo.createVolume(manuscriptId, title: '卷A');
    final c = await chapterRepo.createChapter(
      manuscriptId,
      title: '第一章',
      volumeId: v,
    );

    final chapter = await chapterRepo.getChapter(c);
    expect(chapter?.volumeId, v);
    expect(chapter?.title, '第一章');
    expect(chapter?.status, 'draft');
  });

  test('#2 CR-14 回归：createChaptersBatch 支持 volumeId', () async {
    final v = await volumeRepo.createVolume(manuscriptId, title: '卷A');
    final count = await chapterRepo.createChaptersBatch(
      manuscriptId,
      [
        (title: 'A', content: 'aaa'),
        (title: 'B', content: 'bbbbb'),
      ],
      volumeId: v,
    );

    expect(count, 2);
    final chapters = await chapterRepo.listChapters(manuscriptId);
    expect(chapters.length, 2);
    // 批量创建的章节必须落在目标卷，而非恒为「未分卷」
    expect(chapters.map((c) => c.volumeId), [v, v]);
    expect(chapters.first.wordCount, 3);
    expect(chapters.last.wordCount, 5);
  });

  test('#3 三态生命周期：软删 → 回收站 → 恢复 → 彻底删除', () async {
    final c = await chapterRepo.createChapter(manuscriptId, title: '章');

    await chapterRepo.softDeleteChapter(c);
    expect(await chapterRepo.listChapters(manuscriptId), isEmpty);
    expect((await chapterRepo.listArchivedChapters(manuscriptId)).length, 1);

    await chapterRepo.restoreChapter(c);
    expect((await chapterRepo.listChapters(manuscriptId)).length, 1);
    expect(await chapterRepo.listArchivedChapters(manuscriptId), isEmpty);

    await chapterRepo.purgeChapter(c);
    expect(await chapterRepo.getChapter(c), isNull);
    expect(await chapterRepo.listChapters(manuscriptId), isEmpty);
  });

  test('#4 listChapters 按 sort_order 排序且排除软删', () async {
    final a = await chapterRepo.createChapter(manuscriptId, title: 'A');
    final b = await chapterRepo.createChapter(manuscriptId, title: 'B');
    final c = await chapterRepo.createChapter(manuscriptId, title: 'C');
    await chapterRepo.softDeleteChapter(b);

    final chapters = await chapterRepo.listChapters(manuscriptId);
    expect(chapters.map((e) => e.id), [a, c]);
    // sort_order 保持递增（软删不改变顺序值）
    expect(
      chapters.map((e) => e.sortOrder).toList(),
      chapters.map((e) => e.sortOrder).toList()..sort(),
    );
  });

  test('#5 adoptContentToChapter / undoLastAdoption 往返', () async {
    final c = await chapterRepo.createChapter(
      manuscriptId,
      title: '章',
      content: '原文',
    );

    await chapterRepo.adoptContentToChapter(c, '新文新文');
    var chapter = await chapterRepo.getChapter(c);
    expect(chapter?.content, '新文新文');
    expect(chapter?.previousContent, '原文');
    expect(chapter?.wordCount, 4);

    await chapterRepo.undoLastAdoption(c);
    chapter = await chapterRepo.getChapter(c);
    expect(chapter?.content, '原文');
    expect(chapter?.previousContent, isNull);
    expect(chapter?.wordCount, 2);
  });
}
