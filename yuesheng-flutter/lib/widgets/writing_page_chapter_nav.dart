// ─────────────────────────────────────────────────────────────
// writing_page 的 part 文件：章节导航相关逻辑
// 覆盖批次83/96-11 的章节树抽屉、大纲抽屉、跨章跳转与新建章节。
// 以私有 extension on _WritingPageState 形式提供导航方法，
// 直接访问宿主私有成员（_scaffoldKey / _resolvedManuscriptId 等），
// 行为与原内联实现完全一致，仅做物理拆分。
// ─────────────────────────────────────────────────────────────
// ignore_for_file: invalid_use_of_protected_member
part of 'writing_page.dart';

extension _WritingPageChapterNav on _WritingPageState {
  /// 批次83：⋮ 菜单「章节列表」→ 打开章节树抽屉
  /// 等菜单 bottom sheet 退场后再开抽屉，避免弹层动画冲突
  void _handleOpenChapterTree() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openDrawer();
    });
  }

  /// 批次83：⋮ 菜单「大纲」→ 打开大纲抽屉（endDrawer）
  void _handleOpenOutline() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  /// 批次83：大纲抽屉右上角关闭
  void _handleCloseOutline() {
    Navigator.of(context).pop(); // 关闭 endDrawer（LocalHistoryEntry）
  }

  /// 批次83：抽屉点击某章 → 关抽屉 + 快速跳转（当前章仅关抽屉）
  /// 批次96-11：全文搜索跳转带 cursorOffset（跨章定位命中处）
  void _handleJumpToChapter(
    String targetId,
    String title, [
    int? cursorOffset,
  ]) {
    Navigator.of(context).pop(); // 关闭抽屉（LocalHistoryEntry）
    if (targetId == widget.chapterId) {
      // 批次96-11：目标即当前章 → 直接在编辑器内定位命中处
      if (cursorOffset != null) {
        _locateCursor(cursorOffset);
      }
      return;
    }
    _jumpToChapter(targetId, title, cursorOffset);
  }

  /// 批次83：真实路由跳转（context.go 到 /writing/:chapterId）
  /// 测试注入 onJumpToChapter 时改走回调（不依赖真路由）
  /// 批次96-11：cursorOffset 随 extra 传递（新页加载后定位命中处）
  void _jumpToChapter(String targetId, String title, [int? cursorOffset]) {
    final msId = _resolvedManuscriptId;
    if (widget.onJumpToChapter != null) {
      widget.onJumpToChapter!(targetId, title);
      return;
    }
    context.go(
      AppRoutes.writingChapter.replaceAll(':chapterId', targetId),
      extra: <String, dynamic>{
        'manuscriptId': msId ?? '',
        'chapterTitle': title,
        'cursorOffset': ?cursorOffset,
      },
    );
  }

  /// 批次83：抽屉「新建章节」→ 关抽屉 + 落库 + 跳转到新章
  Future<void> _handleCreateChapter() async {
    final msId = _resolvedManuscriptId;
    if (msId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('暂时无法新建章节，请稍后再试')));
      return;
    }
    Navigator.of(context).pop(); // 关闭抽屉
    try {
      final db = ref.read(appDatabaseProvider);
      final repo = ChapterRepository(db);
      // 批次88-1：新建章节自动命名「第一章/第二章/…」——按已有标题最大序号 +1
      final chapters = await repo.listChapters(msId);
      final title = nextChapterTitle(chapters);
      // 批次89-2：新建章节自动落入当前章所在卷（当前章未分卷则新章也不分卷）
      final volumeId = ref
          .read(writingStoreProvider(widget.chapterId))
          .chapter
          ?.volumeId;
      final newId = await repo.createChapter(
        msId,
        title: title,
        volumeId: volumeId,
      );
      // 列表缓存失效，下次打开抽屉读到新章节
      ref.invalidate(chapterListProvider(msId));
      if (!mounted) return;
      _jumpToChapter(newId, title);
    } catch (e) {
      debugPrint('[WritingPage] 新建章节失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('新建章节失败，请稍后再试')));
    }
  }
}
