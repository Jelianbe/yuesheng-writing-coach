// ─────────────────────────────────────────────────────────────
// chapter_providers_test — 章节状态管理单元测试
//
// 建立原因（CR-25）：providers 层 624 行此前无独立测试。
//
// 重点守护「乐观更新与 DB 一致」——这类不一致只在跨层对照时暴露，
// 也是 CR-22（漏 volumeId）与 CR-23（sortOrder 漂移）的共同形态。
//
// 覆盖：
//   1. CR-22 回归：改标题 / 存内容 / 采纳后，state 的 volumeId 不丢失
//   2. CR-23 回归：软删后新建章节，state 与 DB 的 sortOrder 一致且不撞值
//   3. 采纳 → 撤销的内容往返（state 侧）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';
import 'package:writingcoach/providers/chapter_providers.dart';

void main() {
  late AppDatabase db;
  late ChapterListStore store;
  late ChapterRepository chRepo;
  late VolumeRepository volRepo;
  late String mid;
  late String volumeId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mid = await ManuscriptRepository(db).createManuscript(title: '测试稿');
    chRepo = ChapterRepository(db);
    volRepo = VolumeRepository(db);
    volumeId = await volRepo.createVolume(mid, title: '卷A');
    store = ChapterListStore(db, mid);
  });

  tearDown(() async => db.close());

  Future<String> seedChapterInVolume() async {
    final id = await chRepo.createChapter(
      mid,
      title: 'C1',
      content: '旧内容',
      volumeId: volumeId,
    );
    await store.loadChapters();
    return id;
  }

  test('#1 CR-22 回归：改标题后 state 的 volumeId 不丢失', () async {
    final id = await seedChapterInVolume();
    await store.updateChapterTitle(id, '新标题');

    expect(store.state.chapters.first.title, '新标题');
    expect(
      store.state.chapters.first.volumeId,
      volumeId,
      reason: '改标题不得丢失卷归属（DB 里仍在）',
    );
    expect(
      store.state.chapters.first.volumeId,
      (await chRepo.getChapter(id))!.volumeId,
    );
  });

  test('#2 CR-22 回归：保存内容后 state 的 volumeId 不丢失', () async {
    final id = await seedChapterInVolume();
    await store.saveChapterContent(id, '全新内容');

    expect(store.state.chapters.first.content, '全新内容');
    expect(store.state.chapters.first.wordCount, 4);
    expect(store.state.chapters.first.volumeId, volumeId);
  });

  test('#3 CR-22 回归：采纳内容后 volumeId 不丢且 previousContent 正确', () async {
    final id = await seedChapterInVolume();
    await store.adoptContentToChapter(id, '采纳的新内容');

    final c = store.state.chapters.first;
    expect(c.content, '采纳的新内容');
    expect(c.previousContent, '旧内容');
    expect(c.volumeId, volumeId);
  });

  test('#4 CR-23 回归：软删中间章后新建，state 与 DB 的 sortOrder 一致', () async {
    await chRepo.createChapter(mid, title: 'A');
    final b = await chRepo.createChapter(mid, title: 'B');
    await chRepo.createChapter(mid, title: 'C');
    await chRepo.softDeleteChapter(b);
    await store.loadChapters();

    final newId = (await store.createChapter(title: 'D'))!;
    final inState = store.state.chapters
        .firstWhere((c) => c.id == newId)
        .sortOrder;
    final inDb = (await chRepo.getChapter(newId))!.sortOrder;

    expect(inState, inDb, reason: '乐观更新值必须与 DB 实际落库值一致');
    // 且不得与列表中任一现存章节撞 sort_order
    final others = store.state.chapters
        .where((c) => c.id != newId)
        .map((c) => c.sortOrder);
    expect(others, isNot(contains(inState)));
  });

  test('#5 撤销采纳：state 内容回到旧值', () async {
    final id = await seedChapterInVolume();
    await store.adoptContentToChapter(id, '新');
    // 撤销走 repository（store 未暴露该方法），此处校验 state 的前置状态正确
    final adopted = store.state.chapters.first;
    expect(adopted.content, '新');
    expect(adopted.previousContent, '旧内容');

    await chRepo.undoLastAdoption(id);
    await store.loadChapters();
    final restored = store.state.chapters.first;
    expect(restored.content, '旧内容');
    expect(restored.previousContent, isNull);
    expect(restored.volumeId, volumeId);
  });

  test('#6 D-W1 回归：软删 sort_order **最大**的章后新建，两层仍一致', () async {
    // ★ 为什么必须单独立这一条：上面 #4 软删的是**中间**章（b=1）——
    // 那种稿上「可见 max」与「库 MAX」恰好相等（都是 2）⇒ 旧实现照样绿，
    // **该夹具对 D-W1 零鉴别力**（真机走查的 `§4-28` 教训在这里重演）。
    // 本条的判别点是「被删掉的正是最大的那一章」：库行仍在（softDelete 只改
    // status、**不动 sort_order**）⇒ 两套推算**必然分叉**。
    await chRepo.createChapter(mid, title: 'A'); // sort_order 0
    await chRepo.createChapter(mid, title: 'B'); // sort_order 1
    final maxId = await chRepo.createChapter(
      mid,
      title: 'C',
    ); // sort_order 2 ← 最大
    await chRepo.softDeleteChapter(maxId);
    await store.loadChapters();

    final visibleMax = store.state.chapters
        .map((c) => c.sortOrder)
        .reduce((a, b) => a > b ? a : b);
    expect(visibleMax, 1, reason: '前置条件：可见列表的最大 sort_order 已被软删');

    final newId = (await store.createChapter(title: 'D'))!;
    final inState = store.state.chapters
        .firstWhere((c) => c.id == newId)
        .sortOrder;
    final inDb = (await chRepo.getChapter(newId))!.sortOrder;

    expect(inState, inDb, reason: 'D-W1：内存态必须等于库侧真实值');
    expect(inState, 3, reason: '库侧 MAX(sort_order) 含归档行 2 ⇒ 3');
    expect(
      inState,
      isNot(visibleMax + 1),
      reason: '★ 鉴别力：旧公式（可见 max + 1 = 2）**必错** —— 这才是 D-W1 的红线',
    );
  });
}
