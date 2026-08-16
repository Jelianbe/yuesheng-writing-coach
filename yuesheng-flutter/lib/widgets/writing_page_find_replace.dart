// ─────────────────────────────────────────────────────────────
// writing_page 的 part 文件：查找替换 + 全文搜索相关逻辑
// 覆盖批次84-2 查找替换 / 批次96-11 全文搜索（打开弹层、替换落稿、定位选区、跨章光标定位）。
// 以私有 extension on _WritingPageState 形式提供方法，直接访问宿主私有成员
// （_controller / _suppressSelectionMenu / _onContentChanged / _resolvedManuscriptId /
// _jumpToChapter / widget / context），行为与原内联实现完全一致，仅做物理拆分。
// ─────────────────────────────────────────────────────────────
// ignore_for_file: invalid_use_of_protected_member
part of 'writing_page.dart';

extension _WritingPageFindReplace on _WritingPageState {
  /// 批次84-2：⋮ 菜单「查找替换」→ 查找替换弹层
  void _handleOpenFindReplace() {
    SearchReplaceSheet.show(
      context,
      initialText: _controller.text,
      manuscriptId: _resolvedManuscriptId,
      currentChapterId: widget.chapterId,
      onApply: _handleApplyFindReplace,
      onLocate: _handleLocateMatch,
      onJumpToChapter: _jumpToChapter,
    );
  }

  /// 批次96-11：⋮ 菜单「全文搜索」→ 打开即全书搜索视图
  /// （整本作品章节搜索：命中片段 + 关键词高亮 + 当前章定位/跨章跳转定位）
  void _handleOpenFullTextSearch() {
    SearchReplaceSheet.show(
      context,
      initialText: _controller.text,
      manuscriptId: _resolvedManuscriptId,
      currentChapterId: widget.chapterId,
      onApply: _handleApplyFindReplace,
      onLocate: _handleLocateMatch,
      onJumpToChapter: _jumpToChapter,
      initialBookView: true,
    );
  }

  /// 批次84-2：替换落稿 → 写编辑器 + 保存（抑制划词菜单误弹）
  void _handleApplyFindReplace(String newText, int cursorOffset) {
    _suppressSelectionMenu = true;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
    _suppressSelectionMenu = false;
    _onContentChanged(newText);
  }

  /// 批次84-2：查找定位 → 设选区（程序化选区，不弹划词菜单）
  void _handleLocateMatch(int start, int end) {
    _suppressSelectionMenu = true;
    _controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    _suppressSelectionMenu = false;
  }

  /// 批次96-11：跨章全文搜索定位 → 光标折叠定位到命中处（TextField 自动滚动可见）
  void _locateCursor(int offset) {
    if (offset < 0 || offset > _controller.text.length) return;
    _suppressSelectionMenu = true;
    _controller.selection = TextSelection.collapsed(offset: offset);
    _suppressSelectionMenu = false;
  }
}
