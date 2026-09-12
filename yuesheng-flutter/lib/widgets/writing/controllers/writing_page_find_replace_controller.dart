// ─────────────────────────────────────────────────────────────
// WritingPageFindReplaceController — 查找替换 / 全文搜索控制器（C92-6b）
//
// 来源：原 `writing_page_find_replace.dart`（part + extension 伪拆分）。
// 覆盖批次84-2 查找替换 / 批次96-11 全文搜索（打开弹层、替换落稿、定位选区）。
// 依赖：宿主 + 章节导航控制器（弹层「跳转到其它章」回调）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../search_replace_sheet.dart';
import '../writing_page_host.dart';
import 'writing_page_chapter_nav_controller.dart';

class WritingPageFindReplaceController {
  WritingPageFindReplaceController(this._host, this._chapterNav);

  final WritingPageHost _host;
  final WritingPageChapterNavController _chapterNav;

  /// 批次84-2：⋮ 菜单「查找替换」→ 查找替换弹层
  void openFindReplace() {
    SearchReplaceSheet.show(
      _host.context,
      initialText: _host.editorController.text,
      manuscriptId: _host.resolvedManuscriptId,
      currentChapterId: _host.chapterId,
      onApply: applyFindReplace,
      onLocate: locateMatch,
      onJumpToChapter: _chapterNav.jumpToChapter,
    );
  }

  /// 批次96-11：⋮ 菜单「全文搜索」→ 打开即全书搜索视图
  /// （整本作品章节搜索：命中片段 + 关键词高亮 + 当前章定位/跨章跳转定位）
  void openFullTextSearch() {
    SearchReplaceSheet.show(
      _host.context,
      initialText: _host.editorController.text,
      manuscriptId: _host.resolvedManuscriptId,
      currentChapterId: _host.chapterId,
      onApply: applyFindReplace,
      onLocate: locateMatch,
      onJumpToChapter: _chapterNav.jumpToChapter,
      initialBookView: true,
    );
  }

  /// 批次84-2：替换落稿 → 写编辑器 + 保存（抑制划词菜单误弹）
  void applyFindReplace(String newText, int cursorOffset) {
    _host.suppressSelectionMenu = true;
    _host.editorController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
    _host.suppressSelectionMenu = false;
    _host.onContentChanged(newText);
  }

  /// 批次84-2：查找定位 → 设选区（程序化选区，不弹划词菜单）
  void locateMatch(int start, int end) {
    _host.suppressSelectionMenu = true;
    _host.editorController.selection = TextSelection(
      baseOffset: start,
      extentOffset: end,
    );
    _host.suppressSelectionMenu = false;
  }
}
