// ─────────────────────────────────────────────────────────────
// chapter_orphan_cleanup_test — 删章清理章节级 KV（存量缺陷 B25 回归）
//
// 背景：`chapter_draft` / `chapter_versions` / `chapter_goal` 三键以
//   `<前缀>:<chapterId>` 落在 `app_state` 表。此前物理删章**不清**这三键
//   ⇒ 孤儿行永久残留（B25，出处
//   `docs/verify-B-series-prompt-audit-2026-08-18.md:16`）。
//
// 覆盖：
//   1. 硬删（purgeChapter）清三键
//   2. 只清被删章节：相邻章节三键不受影响
//   3. 软删（回收站）**不**清；恢复后版本仍可读回（回归守卫）
//   4. 键名契约（漂移绊线）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/chapter_scoped_keys.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/services/error_handler.dart';

void main() {
  late AppDatabase db;
  late ChapterRepository chapterRepo;
  late AppStateRepository appStateRepo;
  late String manuscriptId;

  setUp(() async {
    ErrorHandler.instance.resetForTesting();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chapterRepo = ChapterRepository(db);
    appStateRepo = AppStateRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await db.close();
  });

  /// 写入一章的全部章节级 KV（三键各一）。
  /// `chapter_goal` 无独立仓库方法（写入方是 WritingStore），直写键。
  Future<void> seedChapterKeys(String chapterId) async {
    await appStateRepo.saveChapterDraft(chapterId, '标题', '草稿正文');
    await appStateRepo.addChapterVersion(chapterId, '版本正文');
    await appStateRepo.setValue(chapterGoalKey(chapterId), '1200');
  }

  test('#1 硬删（purgeChapter）清除章节级全部 KV', () async {
    final c = await chapterRepo.createChapter(manuscriptId, title: '第一章');
    await seedChapterKeys(c);
    expect(await appStateRepo.getValue(chapterDraftKey(c)), isNotNull);
    expect(await appStateRepo.getValue(chapterVersionsKey(c)), isNotNull);
    expect(await appStateRepo.getValue(chapterGoalKey(c)), isNotNull);

    await chapterRepo.purgeChapter(c);

    expect(await appStateRepo.getValue(chapterDraftKey(c)), isNull);
    expect(await appStateRepo.getValue(chapterVersionsKey(c)), isNull);
    expect(await appStateRepo.getValue(chapterGoalKey(c)), isNull);
  });

  test('#2 只清被删章节：相邻章节的 KV 原样保留', () async {
    final a = await chapterRepo.createChapter(manuscriptId, title: '第一章');
    final b = await chapterRepo.createChapter(manuscriptId, title: '第二章');
    await seedChapterKeys(a);
    await seedChapterKeys(b);

    await chapterRepo.purgeChapter(a);

    expect(await appStateRepo.getValue(chapterDraftKey(a)), isNull);
    expect(await appStateRepo.getValue(chapterVersionsKey(a)), isNull);
    expect(await appStateRepo.getValue(chapterGoalKey(a)), isNull);
    expect(
      await appStateRepo.getValue(chapterDraftKey(b)),
      isNotNull,
      reason: '不得因前缀/集合误伤相邻章节',
    );
    expect(await appStateRepo.getValue(chapterVersionsKey(b)), isNotNull);
    expect(await appStateRepo.getValue(chapterGoalKey(b)), isNotNull);
  });

  test('#3 软删（回收站）不清 KV；恢复后版本仍可读回', () async {
    final c = await chapterRepo.createChapter(manuscriptId, title: '第一章');
    await seedChapterKeys(c);

    await chapterRepo.softDeleteChapter(c);

    expect(
      await appStateRepo.getValue(chapterDraftKey(c)),
      isNotNull,
      reason: '软删进回收站不得清草稿，否则恢复章节会丢草稿',
    );
    expect(
      await appStateRepo.getValue(chapterVersionsKey(c)),
      isNotNull,
      reason: '软删不得清版本快照，否则恢复后时光机为空',
    );
    expect(await appStateRepo.getValue(chapterGoalKey(c)), isNotNull);

    await chapterRepo.restoreChapter(c);

    final versions = await appStateRepo.listChapterVersions(c);
    expect(versions, hasLength(1));
    expect(versions.first.content, '版本正文');
  });

  test('#4 键名契约（漂移绊线）', () {
    // 写成字面量数组：将来改键名必须显式改这里，逼改动者考虑存量数据迁移。
    expect(chapterScopedKeys('c1'), <String>[
      'chapter_draft:c1',
      'chapter_versions:c1',
      'chapter_goal:c1',
    ]);
    expect(chapterDraftKey('c1'), 'chapter_draft:c1');
    expect(chapterVersionsKey('c1'), 'chapter_versions:c1');
    expect(chapterGoalKey('c1'), 'chapter_goal:c1');
  });
}
