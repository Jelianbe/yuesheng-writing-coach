// ─────────────────────────────────────────────────────────────
// WritingPageChapterNavController — 章节导航控制器（C92-6b）
//
// 来源：原 `writing_page_chapter_nav.dart`（part + extension 伪拆分）
// + 宿主 `writing_page.dart` 的抽屉构造/回调（原 `_buildChapterTreeDrawer` /
// `_buildOutlineDrawer` / `_handleDrawerChanged` / `_handleEndDrawerChanged`）。
// 覆盖批次83/96-11 的章节树抽屉、大纲抽屉、跨章跳转与新建章节。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/chapter_repository.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/chapter_providers.dart';
import '../../../providers/manuscript_providers.dart';
import '../../../providers/writing_providers.dart';
import '../../../router/app_routes.dart';
import '../../../utils/chapter_title.dart';
import '../../chapter_tree_drawer.dart';
import '../../outline_drawer.dart';
import '../writing_page_host.dart';

class WritingPageChapterNavController {
  WritingPageChapterNavController(this._host);

  final WritingPageHost _host;

  /// 批次83：章节树抽屉（每次打开以新 key 重建 → 列表/标题保持最新）
  Widget buildChapterTreeDrawer() {
    return ChapterTreeDrawer(
      key: ValueKey('chapter-tree-${_host.treeOpenCount}'),
      currentChapterId: _host.chapterId,
      manuscriptId: _host.resolvedManuscriptId,
      onJumpToChapter: handleJumpToChapter,
      onCreateChapter: handleCreateChapter,
    );
  }

  void handleDrawerChanged(bool isOpened) {
    if (!isOpened) return;
    // 打开时重建抽屉 + 刷新章节 store（编辑器改标题后抽屉能读到最新）
    _host.hostSetState(() => _host.treeOpenCount++);
    final msId = _host.resolvedManuscriptId;
    if (msId != null) {
      _host.ref.read(chapterStoreProvider(msId).notifier).loadChapters();
    }
  }

  /// 批次83：大纲边写边看（右侧抽屉；每次打开重建 + 失效缓存）
  Widget buildOutlineDrawer() {
    return OutlineDrawer(
      key: ValueKey('outline-${_host.outlineOpenCount}'),
      manuscriptId: _host.resolvedManuscriptId,
      onClose: handleCloseOutline,
    );
  }

  void handleEndDrawerChanged(bool isOpened) {
    if (!isOpened) return;
    _host.hostSetState(() => _host.outlineOpenCount++);
    final msId = _host.resolvedManuscriptId;
    if (msId != null) _host.ref.invalidate(outlineViewProvider(msId));
  }

  /// 批次83：⋮ 菜单「章节列表」→ 打开章节树抽屉
  /// 等菜单 bottom sheet 退场后再开抽屉，避免弹层动画冲突
  void handleOpenChapterTree() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _host.scaffoldKey.currentState?.openDrawer();
    });
  }

  /// 批次83：⋮ 菜单「大纲」→ 打开大纲抽屉（endDrawer）
  void handleOpenOutline() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _host.scaffoldKey.currentState?.openEndDrawer();
    });
  }

  /// 批次83：大纲抽屉右上角关闭
  void handleCloseOutline() {
    Navigator.of(_host.context).pop(); // 关闭 endDrawer（LocalHistoryEntry）
  }

  /// 批次83：抽屉点击某章 → 关抽屉 + 快速跳转（当前章仅关抽屉）
  /// 批次96-11：全文搜索跳转带 cursorOffset（跨章定位命中处）
  void handleJumpToChapter(String targetId, String title, [int? cursorOffset]) {
    Navigator.of(_host.context).pop(); // 关闭抽屉（LocalHistoryEntry）
    if (targetId == _host.chapterId) {
      // 批次96-11：目标即当前章 → 直接在编辑器内定位命中处
      if (cursorOffset != null) {
        _host.locateCursor(cursorOffset);
      }
      return;
    }
    jumpToChapter(targetId, title, cursorOffset);
  }

  /// 批次83：真实路由跳转（context.go 到 /writing/:chapterId）
  /// 测试注入 onJumpToChapter 时改走回调（不依赖真路由）
  /// 批次96-11：cursorOffset 随 extra 传递（新页加载后定位命中处）
  void jumpToChapter(String targetId, String title, [int? cursorOffset]) {
    final msId = _host.resolvedManuscriptId;
    final injected = _host.onJumpToChapterCallback;
    if (injected != null) {
      injected(targetId, title);
      return;
    }
    _host.context.go(
      AppRoutes.writingChapter.replaceAll(':chapterId', targetId),
      extra: <String, dynamic>{
        'manuscriptId': msId ?? '',
        'chapterTitle': title,
        'cursorOffset': ?cursorOffset,
      },
    );
  }

  /// 批次83：抽屉「新建章节」→ 关抽屉 + 落库 + 跳转到新章
  Future<void> handleCreateChapter() async {
    final msId = _host.resolvedManuscriptId;
    if (msId == null) {
      if (!_host.mounted) return;
      ScaffoldMessenger.of(_host.context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('暂时无法新建章节，请稍后再试')));
      return;
    }
    Navigator.of(_host.context).pop(); // 关闭抽屉
    try {
      final db = _host.ref.read(appDatabaseProvider);
      final repo = ChapterRepository(db);
      // 批次88-1：新建章节自动命名「第一章/第二章/…」——按已有标题最大序号 +1
      final chapters = await repo.listChapters(msId);
      final title = nextChapterTitle(chapters);
      // 批次89-2：新建章节自动落入当前章所在卷（当前章未分卷则新章也不分卷）
      final volumeId = _host.ref
          .read(writingStoreProvider(_host.chapterId))
          .chapter
          ?.volumeId;
      final newId = await repo.createChapter(
        msId,
        title: title,
        volumeId: volumeId,
      );
      // ADR-C90：直写 repo 后刷新 store——下次打开抽屉读到新章节
      _host.ref.read(chapterStoreProvider(msId).notifier).loadChapters();
      if (!_host.mounted) return;
      jumpToChapter(newId, title);
    } catch (e) {
      debugPrint('[WritingPage] 新建章节失败: $e');
      if (!_host.context.mounted) return;
      ScaffoldMessenger.of(_host.context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('新建章节失败，请稍后再试')));
    }
  }
}
