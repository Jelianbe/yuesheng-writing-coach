// ─────────────────────────────────────────────────────────────
// manuscript_providers_test — 书架/作品状态管理测试
//
// 本文件此前为零（274 行的 provider 无独立测试，P1-14 方法级盲区）。
//
// 覆盖路径：
//   1. loadManuscripts → 列表加载 + isLoading 归位
//   2. createManuscript → 乐观更新到列表头部，且内存记录与 DB 一致（CR-42）
//   3. updateManuscript → 只改指定字段，其余保留（CR-42 copyWith）
//   4. deleteManuscript → 从列表移除 + DB 软删
//   5. allManuscriptStatsProvider → 只订阅 manuscripts（CR-45 select）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/manuscript_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ManuscriptStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    store = container.read(manuscriptStoreProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('ManuscriptStore', () {
    test('#1 loadManuscripts → 列表加载，isLoading 归位', () async {
      await ManuscriptRepository(db).createManuscript(title: '作品A');

      await store.loadManuscripts();

      expect(store.state.isLoading, isFalse);
      expect(store.state.error, isNull);
      expect(store.state.manuscripts.length, 1);
      expect(store.state.manuscripts.first.title, '作品A');
    });

    test('#2 createManuscript → 乐观更新到头部，且内存记录与 DB 一致（CR-42）', () async {
      final id = await store.createManuscript(
        title: '新作',
        description: '简介',
        genre: '科幻',
        tags: ['标签1'],
      );
      expect(id, isNotNull);

      final ms = store.state.manuscripts.first;
      // 乐观更新：新作品在列表头部
      expect(ms.id, id);
      expect(ms.title, '新作');
      expect(ms.description, '简介');
      expect(ms.genre, '科幻');

      // CR-42 核心：内存态来自 DB 回读，不是本地按默认值重造。
      // 逐字段与 DB 记录比对——若改回内存重造，默认值一旦与 repository
      // 分歧，这里就会失配。
      final dbMs = await ManuscriptRepository(db).getManuscript(id!);
      expect(dbMs, isNotNull);
      expect(ms.language, dbMs!.language);
      expect(ms.status, dbMs.status);
      expect(ms.sortOrder, dbMs.sortOrder);
      expect(ms.createdAt, dbMs.createdAt);
      expect(ms.updatedAt, dbMs.updatedAt);
      expect(ms.tags, dbMs.tags);
    });

    test('#3 updateManuscript → 只改指定字段，其余保留（CR-42）', () async {
      final id = await store.createManuscript(
        title: '原标题',
        genre: '悬疑',
        description: '原简介',
      );
      final before = store.state.manuscripts.first;

      await store.updateManuscript(id!, title: '新标题');

      final after = store.state.manuscripts.firstWhere((m) => m.id == id);
      expect(after.title, '新标题');
      // 未指定的字段必须原样保留（原手写重建漏一个就会被重置成默认值）
      expect(after.genre, '悬疑');
      expect(after.description, '原简介');
      expect(after.language, before.language);
      expect(after.status, before.status);
      expect(after.sortOrder, before.sortOrder);
      expect(after.createdAt, before.createdAt);
      expect(after.updatedAt >= before.updatedAt, isTrue);
    });

    test('#4 updateManuscript → tags 落库且其他作品不受影响', () async {
      final idA = await store.createManuscript(title: 'A');
      final idB = await store.createManuscript(title: 'B');

      await store.updateManuscript(idA!, tags: ['x', 'y']);

      final a = store.state.manuscripts.firstWhere((m) => m.id == idA);
      final b = store.state.manuscripts.firstWhere((m) => m.id == idB);
      expect(a.tags, contains('x'));
      expect(b.tags, '[]');
    });

    test('#5 deleteManuscript → 从列表移除 + DB 软删', () async {
      final idA = await store.createManuscript(title: 'A');
      await store.createManuscript(title: 'B');
      expect(store.state.manuscripts.length, 2);

      await store.deleteManuscript(idA!);

      expect(store.state.manuscripts.length, 1);
      expect(store.state.manuscripts.first.title, 'B');
      // DB 侧为软删（archived），不是物理删除
      final dbMs = await ManuscriptRepository(db).getManuscript(idA);
      expect(dbMs?.status, 'archived');
    });
  });

  group('allManuscriptStatsProvider', () {
    test('#6 只订阅 manuscripts，isLoading 变化不触发重建（CR-45）', () async {
      // 建一条数据，避免 manuscripts 恒为同一个 const [] 导致看不出差异
      await ManuscriptRepository(db).createManuscript(title: '作品A');

      var selectNotifies = 0;
      var storeNotifies = 0;
      container.listen(
        manuscriptStoreProvider.select((s) => s.manuscripts),
        (_, __) => selectNotifies++,
      );
      container.listen(manuscriptStoreProvider, (_, __) => storeNotifies++);

      await store.loadManuscripts();

      // store 整体：isLoading=true 一次 + 数据落地一次 = 2 次
      expect(storeNotifies, 2, reason: 'store 会因 isLoading 变化而通知');
      // select(manuscripts)：isLoading=true 那次 manuscripts 引用未变 → 不通知
      expect(selectNotifies, 1, reason: '只订阅 manuscripts 时，纯 isLoading 变化不应触发');
    });

    test('#7 统计值：章节数与总字数', () async {
      final msId = await ManuscriptRepository(db).createManuscript(title: 'A');
      await ChapterRepository(
        db,
      ).createChapter(msId, title: '第一章', content: '12345');

      await store.loadManuscripts();
      final stats = await container.read(allManuscriptStatsProvider.future);

      expect(stats[msId], isNotNull);
      expect(stats[msId]!.chapterCount, 1);
      expect(stats[msId]!.totalWords, 5);
    });
  });
}
