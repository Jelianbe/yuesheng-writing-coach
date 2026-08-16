// ─────────────────────────────────────────────────────────────
// volume_repository_test — 批次89 卷分组仓储单元测试
//
// 覆盖：
//   1. 建卷自动命名（第一卷/第二卷…）
//   2. 指定标题建卷
//   3. listVolumes 按 sort_order 排序
//   4. 章节移入卷；删卷 → 章节回「未分卷」（ON DELETE SET NULL）
//   5. setChapterVolume(null) 移出卷
//   6. 卷按作品隔离
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';

void main() {
  late AppDatabase db;
  late VolumeRepository repo;
  late ChapterRepository chapterRepo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = VolumeRepository(db);
    chapterRepo = ChapterRepository(db);
    manuscriptId = await ManuscriptRepository(db).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  test('#1 建卷自动命名：第一卷、第二卷…', () async {
    final v1 = await repo.createVolume(manuscriptId);
    final v2 = await repo.createVolume(manuscriptId);

    final volumes = await repo.listVolumes(manuscriptId);
    expect(volumes.length, 2);
    expect(volumes.map((v) => v.id), [v1, v2]);
    expect(volumes[0].title, '第一卷');
    expect(volumes[1].title, '第二卷');
  });

  test('#2 指定标题建卷', () async {
    final v1 = await repo.createVolume(manuscriptId, title: '  风起篇  ');
    final volumes = await repo.listVolumes(manuscriptId);

    expect(volumes.length, 1);
    expect(volumes.first.id, v1);
    expect(volumes.first.title, '风起篇', reason: '标题应 trim 后保存');
  });

  test('#3 listVolumes 按 sort_order 排序', () async {
    await repo.createVolume(manuscriptId, title: '第一篇', sortOrder: 3);
    await repo.createVolume(manuscriptId, title: '第二篇', sortOrder: 1);
    await repo.createVolume(manuscriptId, title: '第三篇', sortOrder: 2);

    final volumes = await repo.listVolumes(manuscriptId);
    expect(volumes.map((v) => v.title).toList(), ['第二篇', '第三篇', '第一篇']);
    expect(volumes.map((v) => v.sortOrder).toList(), [1, 2, 3]);
  });

  test('#4 章节移入卷；删卷 → 卷内章节一并删除（批次96-4，不再散落）', () async {
    final volumeId = await repo.createVolume(manuscriptId, title: '第一卷');
    final chapterId =
        await chapterRepo.createChapter(manuscriptId, title: '第一章', content: '内容');

    // 初始未分卷
    expect((await chapterRepo.getChapter(chapterId))!.volumeId, isNull);

    // 移入卷
    await repo.setChapterVolume(chapterId, volumeId);
    expect((await chapterRepo.getChapter(chapterId))!.volumeId, volumeId);

    // 删卷 → 卷行消失；卷内章节软删进回收站（status='archived'），不再回未分卷
    await repo.deleteVolume(volumeId);
    expect(await repo.listVolumes(manuscriptId), isEmpty);
    final ch = await chapterRepo.getChapter(chapterId);
    expect(ch, isNotNull);
    expect(ch!.status, 'archived');
  });

  test('#5 setChapterVolume(null) 移出卷', () async {
    final volumeId = await repo.createVolume(manuscriptId, title: '第一卷');
    final chapterId = await chapterRepo.createChapter(manuscriptId, title: '第一章');

    await repo.setChapterVolume(chapterId, volumeId);
    expect((await chapterRepo.getChapter(chapterId))!.volumeId, volumeId);

    await repo.setChapterVolume(chapterId, null);
    expect((await chapterRepo.getChapter(chapterId))!.volumeId, isNull);
  });

  test('#6 卷按作品隔离', () async {
    final otherManuscriptId =
        await ManuscriptRepository(db).createManuscript(title: '另一稿');
    await repo.createVolume(manuscriptId, title: '本稿第一卷');
    await repo.createVolume(otherManuscriptId, title: '另一稿第一卷');

    final mine = await repo.listVolumes(manuscriptId);
    final other = await repo.listVolumes(otherManuscriptId);
    expect(mine.length, 1);
    expect(mine.first.title, '本稿第一卷');
    expect(other.length, 1);
    expect(other.first.title, '另一稿第一卷');
  });

  test('#7 nextVolumeTitle 纯函数', () {
    final repo = VolumeRepository(db);
    expect(repo.nextVolumeTitle([]), '第一卷');
    expect(
      repo.nextVolumeTitle([
        Volume(
          id: 'a',
          manuscriptId: manuscriptId,
          title: '第一卷',
          sortOrder: 0,
          createdAt: 0,
          updatedAt: 0,
        ),
      ]),
      '第二卷',
    );
  });
}
