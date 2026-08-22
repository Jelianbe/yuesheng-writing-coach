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
//   - createChapter()：DB 写入 + 乐观更新列表
//   - updateChapterTitle()：更新章节标题
//   - saveChapterContent()：保存章节内容
//   - adoptContentToChapter()：采纳内容（备份旧内容）
//
// 命名说明：manuscript_providers 里已存在 FutureProvider 版 chapterListProvider，
// 因此这里命名为 chapterStoreProvider（StateNotifier 版本，带可变状态）。
// ─────────────────────────────────────────────────────────────

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
      state = state.copyWith(
        chapters: chapters,
        isLoading: false,
        clearError: true,
      );
      debugPrint(
        '[ChapterListStore] loadChapters 成功: manuscriptId=$manuscriptId count=${chapters.length}',
      );
    } catch (e) {
      debugPrint(
        '[ChapterListStore] loadChapters 失败: manuscriptId=$manuscriptId error=$e',
      );
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 创建章节：DB 写入 + 追加到列表尾部
  /// 批次92-3：volumeId 可空——新建章节直接落入指定卷（null = 未分卷）
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
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final finalSortOrder = sortOrder ?? state.chapters.length;
      final newChapter = Chapter(
        id: id,
        manuscriptId: manuscriptId,
        title: title ?? '',
        content: content ?? '',
        wordCount: (content ?? '').length,
        sortOrder: finalSortOrder,
        status: 'draft',
        lastDiagnosedAt: null,
        previousContent: null,
        volumeId: volumeId,
        createdAt: now,
        updatedAt: now,
      );
      state = state.copyWith(
        chapters: [...state.chapters, newChapter],
        clearError: true,
      );
      debugPrint(
        '[ChapterListStore] createChapter 成功: id=$id title="${title ?? '未命名章节'}"',
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
  Future<void> updateChapterTitle(String chapterId, String title) async {
    try {
      final repo = ChapterRepository(_db);
      await repo.updateChapterTitle(chapterId, title);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      state = state.copyWith(
        chapters: state.chapters.map((c) {
          if (c.id == chapterId) {
            return Chapter(
              id: c.id,
              manuscriptId: c.manuscriptId,
              title: title,
              content: c.content,
              wordCount: c.wordCount,
              sortOrder: c.sortOrder,
              status: c.status,
              lastDiagnosedAt: c.lastDiagnosedAt,
              previousContent: c.previousContent,
              createdAt: c.createdAt,
              updatedAt: now,
            );
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
            return Chapter(
              id: c.id,
              manuscriptId: c.manuscriptId,
              title: c.title,
              content: content,
              wordCount: content.length,
              sortOrder: c.sortOrder,
              status: c.status,
              lastDiagnosedAt: c.lastDiagnosedAt,
              previousContent: c.previousContent,
              createdAt: c.createdAt,
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
            return Chapter(
              id: c.id,
              manuscriptId: c.manuscriptId,
              title: c.title,
              content: newContent,
              previousContent: c.content,
              wordCount: newContent.length,
              sortOrder: c.sortOrder,
              status: c.status,
              lastDiagnosedAt: c.lastDiagnosedAt,
              createdAt: c.createdAt,
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
            return Chapter(
              id: c.id,
              manuscriptId: c.manuscriptId,
              title: c.title,
              content: c.content,
              wordCount: c.wordCount,
              sortOrder: c.sortOrder,
              status: c.status,
              lastDiagnosedAt: now,
              previousContent: c.previousContent,
              createdAt: c.createdAt,
              updatedAt: now,
            );
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
final chapterStoreProvider =
    StateNotifierProvider.family<ChapterListStore, ChapterListState, String>((
      ref,
      manuscriptId,
    ) {
      final db = ref.watch(appDatabaseProvider);
      return ChapterListStore(db, manuscriptId);
    });

/// 单章节内容 Provider（按 chapterId 加载）
///
/// 批次 C 扩展：用于写作页的章节编辑
final chapterContentProvider = FutureProvider.family<Chapter?, String>((
  ref,
  chapterId,
) async {
  final db = ref.watch(appDatabaseProvider);
  final repo = ChapterRepository(db);
  return repo.getChapter(chapterId);
});
