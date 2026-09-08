// ─────────────────────────────────────────────────────────────
// chapter_store_convergence_test — ADR-C90（CR-24）单一真源收敛
//
// 锁定三条不变量：
//   1. 自动加载：首次 watch chapterStoreProvider 即自动 loadChapters，
//      无需详情页显式调用
//   2. 派生视图：chapterListProvider 同步派生自 store——写 store 方法后
//      列表自动更新，无需 invalidate（原 FutureProvider 双通道已移除）
//   3. 直写 repo 后 loadChapters 刷新 store——派生视图随之同步
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/chapter_providers.dart';
import 'package:writingcoach/providers/manuscript_providers.dart';

void main() {
  late AppDatabase db;
  late ChapterRepository chRepo;
  late String mid;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mid = await ManuscriptRepository(db).createManuscript(title: '收敛测试稿');
    chRepo = ChapterRepository(db);
  });

  tearDown(() async => db.close());

  ProviderContainer makeContainer() =>
      ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);

  /// 让出事件循环，令 provider 的 microtask（自动加载）先启动
  Future<void> flushMicrotasks() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// 轮询等待 store 完成加载（loadChapters 启动后 isLoading 转 false 才算完成）
  Future<void> waitLoaded(ProviderContainer c, String msId) async {
    final notifier = c.read(chapterStoreProvider(msId).notifier);
    for (var i = 0; i < 50; i++) {
      if (!notifier.state.isLoading) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('store 自动加载超时');
  }

  test('#1 自动加载：首次 watch 无需显式 loadChapters 即拿到数据', () async {
    await chRepo.createChapter(mid, title: '自动加载章');
    final c = makeContainer();
    addTearDown(c.dispose);

    final store = c.read(chapterStoreProvider(mid).notifier);
    // 注：read 同步返回时 microtask 尚未执行（初始态 isLoading=false），
    // 不能断言 isLoading=true；核心不变量是「未显式调用 loadChapters 即加载」。
    await flushMicrotasks();
    await waitLoaded(c, mid);

    expect(store.state.chapters.single.title, '自动加载章');
  });

  test('#2 派生视图：store 写后列表自动同步，无需 invalidate', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await flushMicrotasks();
    await waitLoaded(c, mid);
    // 先 watch 派生视图（建立监听）
    var list = c.read(chapterListProvider(mid));
    expect(list, isEmpty);

    await c.read(chapterStoreProvider(mid).notifier).createChapter(title: '新章');
    // 无需 invalidate——派生 Provider 随 store 状态自动更新
    list = c.read(chapterListProvider(mid));
    expect(list.single.title, '新章');
  });

  test('#3 直写 repo 后 loadChapters：派生视图随之同步', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await flushMicrotasks();
    await waitLoaded(c, mid);

    // 绕过 store 直写 DB（模拟树抽屉/回收站路径）
    await chRepo.createChapter(mid, title: '直写章');
    expect(c.read(chapterListProvider(mid)), isEmpty, reason: '直写后 store 尚未感知');

    // 刷新 store——派生视图自动同步
    await c.read(chapterStoreProvider(mid).notifier).loadChapters();
    expect(c.read(chapterListProvider(mid)).single.title, '直写章');
  });

  test('#4 派生视图与 store 同引用：删章后同步移除', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await flushMicrotasks();
    await waitLoaded(c, mid);

    final id = await chRepo.createChapter(mid, title: '待删');
    await c.read(chapterStoreProvider(mid).notifier).loadChapters();
    expect(c.read(chapterListProvider(mid)), hasLength(1));

    await c.read(chapterStoreProvider(mid).notifier).deleteChapter(id);
    expect(
      c.read(chapterListProvider(mid)),
      isEmpty,
      reason: 'store 删章后派生视图立即同步',
    );
  });
}
