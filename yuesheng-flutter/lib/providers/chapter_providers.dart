// ─────────────────────────────────────────────────────────────
// chapter_providers — 章节状态管理
// 复刻 yuesheng-android/src/store/book-store.ts 的 chapter 相关逻辑
//
// 管理状态：
//   - chapters：当前作品的章节列表
//   - isLoading：加载中
//   - error：最近一次错误
//
// 状态转换：
//   - loadChapters()：从 DB 拉取章节列表
//   - createChapter()：DB 写入 + **回读库侧真实行**后入列（禁止本地另算 sort_order）
//   - updateChapterTitle()：更新章节标题
//   - saveChapterContent()：保存章节内容
//   - adoptContentToChapter()：采纳内容（备份旧内容）
//
// 命名说明：manuscript_providers 里已存在 FutureProvider 版 chapterListProvider，
// 因此这里命名为 chapterStoreProvider（StateNotifier 版本，带可变状态）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import 'app_providers.dart';

/// 章节列表状态（不可变）
class ChapterListState {
  final List<Chapter> chapters;
  final bool isLoading;
  final String? error;

  const ChapterListState({
    this.chapters = const [],
    this.isLoading = false,
    this.error,
  });

  ChapterListState copyWith({
    List<Chapter>? chapters,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ChapterListState(
      chapters: chapters ?? this.chapters,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 章节列表管理器（StateNotifier 版本，manuscriptId 作为成员变量）
class ChapterListStore extends StateNotifier<ChapterListState> {
  final AppDatabase _db;
  final String manuscriptId;

  ChapterListStore(this._db, this.manuscriptId)
    : super(const ChapterListState());

  /// 从 DB 加载章节列表（按 sort_order 排序）
  Future<void> loadChapters() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = ChapterRepository(_db);
      final chapters = await repo.listChapters(manuscriptId);
      // ADR-C90：自动加载（microtask）可能跨越 container dispose——
      // await 后不再写已释放的 state，避免 Bad state 污染后续测试。
      if (!mounted) return;
      state = state.copyWith(
        chapters: chapters,
        isLoading: false,
        clearError: true,
      );
      debugPrint(
        '[ChapterListStore] loadChapters 成功: manuscriptId=$manuscriptId count=${chapters.length}',
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint(
        '[ChapterListStore] loadChapters 失败: manuscriptId=$manuscriptId error=$e',
      );
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 创建章节：DB 写入 + **回读库侧真实行**后追加到列表尾部
  /// 批次92-3：volumeId 可空——新建章节直接落入指定卷（null = 未分卷）
  ///
  /// ★ `D-W1`（2026-09-18）：**不再在本层另算 `sort_order`**。旧写法
  /// `sortOrder ?? _maxSortOrder() + 1` 遍历的是**可见列表**，而 repository 用的是
  /// `MAX(sort_order)`（**含回收站行** —— `softDeleteChapter` 只把 status 改 archived、
  /// **不动 sort_order**）⇒ 删掉 `sort_order` 最大的章再新建，两层**必然分叉**
  /// （真机实测：内存对象自称 **2** / 库行实为 **4**）⇒ 章标映射查不到该号
  /// ⇒ **新章在所有展示点渲染「章节未知」**，强停重启才自愈（store 从库重载）。
  /// 现在整行取库里的值 ⇒ **「两处推算」降为一处**，唯一真源 = DB。
  /// ★ 顺带消灭同族漂移：`wordCount` / `createdAt` / `volumeId` / `status` 也不再
  /// 用本地重建值 —— 此前逐字段重建 Chapter，与 `CR-22`（漏传 volumeId）是同一类隐患。
  Future<String?> createChapter({
    String? title,
    String? content,
    int? sortOrder,
    String? volumeId,
  }) async {
    try {
      final repo = ChapterRepository(_db);
      final id = await repo.createChapter(
        manuscriptId,
        title: title,
        content: content,
        sortOrder: sortOrder,
        volumeId: volumeId,
      );
      final row = await repo.getChapter(id);
      if (row == null) {
        // 「写成功却读不到」是不该发生的状态 ⇒ **不静默**：留痕 + 让上层看见失败。
        debugPrint('[ChapterListStore] createChapter 回读失败（库行不存在）: id=$id');
        state = state.copyWith(error: '章节创建后回读失败');
        return null;
      }
      // ★ 按 id 去重后追加 —— 这不是防御性编程，是**必须**的：
      // `chapterStoreProvider` 在**首次 read 时**会排一个 microtask
      // `loadChapters()`（`ADR-C90` 单一真源：watch 即自动加载）。本函数改为
      // 「回读库侧整行」后比旧实现**多一次 DB 往返**，该 microtask 因而可能在
      // **本行之前**完成 —— 那时 `state.chapters` 已含刚提交的这一行
      // ⇒ 直接 append 会**重复一条**（实测 `manuscript_detail_page_test #3`：
      // `Expected: <1>  Actual: <2>`）。
      // 旧写法（本地构造 + 无条件 append）看起来正常，只是因为它**更快**、
      // 抢在 `loadChapters` 之前 append、随后被 `loadChapters` 的结果**覆盖**
      // （**侥幸正确**：正确性依赖执行时序，而非不变量）。
      // 去重后，两种时序都收敛到同一结果 ⇒ 正确性回到不变量上。
      state = state.copyWith(
        chapters: [...state.chapters.where((c) => c.id != row.id), row],
        clearError: true,
      );
      debugPrint(
        '[ChapterListStore] createChapter 成功: id=$id '
        'title="${title ?? '未命名章节'}" sortOrder=${row.sortOrder}',
      );
      return id;
    } catch (e) {
      debugPrint(
        '[ChapterListStore] createChapter 失败: manuscriptId=$manuscriptId error=$e',
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// 更新章节标题
  ///
  /// CR-22：改用 `c.copyWith(...)` 而非逐字段重建 Chapter——此前四处重建
  /// 均漏传 `volumeId`（默认 null），导致编辑后章节在 UI 上「跑出卷外」
  /// 而 DB 里归属仍在。copyWith 未指定的字段保持原值，杜绝再漏字段。
  Future<void> updateChapterTitle(String chapterId, String title) async {
    try {
      final repo = ChapterRepository(_db);
      await repo.updateChapterTitle(chapterId, title);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      state = state.copyWith(
        chapters: state.chapters.map((c) {
          if (c.id == chapterId) {
            return c.copyWith(title: title, updatedAt: now);
          }
          return c;
        }).toList(),
        clearError: true,
      );
    } catch (e) {
      debugPrint(
        '[ChapterListStore] updateChapterTitle 失败: chapterId=$chapterId error=$e',
      );
      state = state.copyWith(error: e.toString());
    }
  }

  /// 保存章节内容（同步更新 wordCount）
  Future<void> saveChapterContent(String chapterId, String content) async {
    try {
      final repo = ChapterRepository(_db);
      await repo.saveChapterContent(chapterId, content);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      state = state.copyWith(
        chapters: state.chapters.map((c) {
          if (c.id == chapterId) {
            return c.copyWith(
              content: content,
              wordCount: content.length,
              updatedAt: now,
            );
          }
          return c;
        }).toList(),
        clearError: true,
      );
    } catch (e) {
      debugPrint(
        '[ChapterListStore] saveChapterContent 失败: chapterId=$chapterId error=$e',
      );
      state = state.copyWith(error: e.toString());
    }
  }

  /// 采纳内容到章节（旧内容备份到 previousContent）
  Future<void> adoptContentToChapter(
    String chapterId,
    String newContent,
  ) async {
    try {
      final repo = ChapterRepository(_db);
      await repo.adoptContentToChapter(chapterId, newContent);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      state = state.copyWith(
        chapters: state.chapters.map((c) {
          if (c.id == chapterId) {
            return c.copyWith(
              content: newContent,
              previousContent: Value(c.content),
              wordCount: newContent.length,
              updatedAt: now,
            );
          }
          return c;
        }).toList(),
        clearError: true,
      );
    } catch (e) {
      debugPrint(
        '[ChapterListStore] adoptContentToChapter 失败: chapterId=$chapterId error=$e',
      );
      state = state.copyWith(error: e.toString());
    }
  }

  /// 删除章节（批次 34）：DB 删除 + 列表移除
  /// 返回是否成功（调用方用于失败提示）
  Future<bool> deleteChapter(String chapterId) async {
    try {
      final repo = ChapterRepository(_db);
      await repo.deleteChapter(chapterId);
      state = state.copyWith(
        chapters: state.chapters.where((c) => c.id != chapterId).toList(),
        clearError: true,
      );
      debugPrint('[ChapterListStore] deleteChapter 成功: chapterId=$chapterId');
      return true;
    } catch (e) {
      debugPrint(
        '[ChapterListStore] deleteChapter 失败: chapterId=$chapterId error=$e',
      );
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 批次94-2：软删章节 → 回收站（status='archived'，从列表移除）
  /// 返回是否成功（调用方用于失败提示）
  Future<bool> softDeleteChapter(String chapterId) async {
    try {
      final repo = ChapterRepository(_db);
      await repo.softDeleteChapter(chapterId);
      state = state.copyWith(
        chapters: state.chapters.where((c) => c.id != chapterId).toList(),
        clearError: true,
      );
      debugPrint(
        '[ChapterListStore] softDeleteChapter 成功: chapterId=$chapterId',
      );
      return true;
    } catch (e) {
      debugPrint(
        '[ChapterListStore] softDeleteChapter 失败: chapterId=$chapterId error=$e',
      );
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 更新章节的最后诊断时间
  Future<void> updateChapterDiagnosedAt(String chapterId) async {
    try {
      final repo = ChapterRepository(_db);
      await repo.updateChapterDiagnosedAt(chapterId);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      state = state.copyWith(
        chapters: state.chapters.map((c) {
          if (c.id == chapterId) {
            return c.copyWith(lastDiagnosedAt: Value(now), updatedAt: now);
          }
          return c;
        }).toList(),
        clearError: true,
      );
    } catch (e) {
      debugPrint(
        '[ChapterListStore] updateChapterDiagnosedAt 失败: chapterId=$chapterId error=$e',
      );
      state = state.copyWith(error: e.toString());
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// family provider：每个 manuscriptId 一个独立的 ChapterListStore 实例
///
/// 注意：已将名称从 chapterListProvider 改为 chapterStoreProvider，
/// 避免与 manuscript_providers.dart 中的 FutureProvider 版重名冲突。
///
/// ADR-C90（CR-24 收敛）：单一真源——任何消费方首次 watch 即自动加载，
/// 不再依赖详情页显式 loadChapters()；chapterListProvider 已降级为
/// 本 provider 的派生视图（见 manuscript_providers.dart）。
final chapterStoreProvider =
    StateNotifierProvider.family<ChapterListStore, ChapterListState, String>((
      ref,
      manuscriptId,
    ) {
      final db = ref.watch(appDatabaseProvider);
      final store = ChapterListStore(db, manuscriptId);
      // ADR-C90：微任务加载——watch 方 build 时 store 尚空（isLoading=true），
      // 加载完成后自动通知重建。幂等：显式 loadChapters 调用不受影响。
      // mounted 防护：同步 test 结束后 container 可能已 dispose，
      // 此时 microtask 尚在队列——跳过，避免 dispose 后使用。
      Future.microtask(() {
        if (!store.mounted) return;
        store.loadChapters();
      });
      return store;
    });

/// 单章节内容 Provider（按 chapterId 加载）
///
/// 批次 C 扩展：用于写作页的章节编辑
/// CR-28：本 provider **有意**不带自动失效机制——DB 更新后不会自动重取。
/// 写作页自行持有并管理内容状态（WritingStore.localContent），是本 provider
/// 的主要消费方；若此处再自动重取，会与编辑中的内存态打架，导致光标跳动 /
/// 内容回退。故它只承担「首次加载」职责，刷新由调用方显式 invalidate。
/// 若未来新增消费方，请先确认它不需要跟随 DB 实时更新。
final chapterContentProvider = FutureProvider.family<Chapter?, String>((
  ref,
  chapterId,
) async {
  final db = ref.watch(appDatabaseProvider);
  final repo = ChapterRepository(db);
  return repo.getChapter(chapterId);
});
