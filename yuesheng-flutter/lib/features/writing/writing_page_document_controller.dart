// ─────────────────────────────────────────────────────────────
// WritingPageDocumentController — 文档编辑控制器（C92-6b）
//
// 来源：宿主 `writing_page.dart` 外迁（内容变更/保存调度、标题、段落格式、
// 快捷短语插入、版本恢复、撤销重做、标点插入、标点栏配置加载）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/edit_diff_event_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/chapter_providers.dart';
import '../../providers/writing_providers.dart';
import '../../utils/deleted_text_extractor.dart';
import '../../utils/paragraph_format.dart';
import 'independent_drafting_provider.dart';
import 'whole_chapter_mode_provider.dart';
import 'writing_page_host.dart';

class WritingPageDocumentController {
  WritingPageDocumentController(this._host);

  final WritingPageHost _host;

  /// 批次86-1：被删片段长度达到该值才入回收板（短删改不值得找回）
  static const int _minRecycleBinLength = 8;

  void onContentChanged(String content) {
    _host.dirty = true;
    // 批次86-1：回收板——用户删除/剪切 ≥8 字的连续片段 → 自动入回收板
    // 编辑器性能-1（2026-09-21）：调用方先做**净缩短护栏**——纯删除 ≥8 字必然
    // 净缩短 ≥8，净缩短 <8 时扫描结果必不合格（null 或 <8）⇒ 直接跳过 O(全文)
    // 扫描。退格/连续输入每击从 O(全文) 降为 O(1)；回收板入库语义零变化
    //（纯函数 extractRemovedText 契约不动，其单测仍锁定 <8 字片段的返回值）。
    final prev = _host.lastEditorText;
    _host.lastEditorText = content;
    if (prev != null && prev.length - content.length >= _minRecycleBinLength) {
      final removed = extractRemovedText(prev, content);
      if (removed != null && removed.length >= _minRecycleBinLength) {
        AppStateRepository(
          _host.ref.read(appDatabaseProvider),
        ).addRecycleBinItem(removed);
      }
    }
    _host.store?.updateContent(content);
    // 批次82：跨过写作目标线 → 轻提示一次（降回线下后再跨越可再次提示）
    final ws = _host.ref.read(writingStoreProvider(_host.chapterId));
    if (ws.goalWords > 0 && ws.wordCount >= ws.goalWords) {
      if (!_host.goalCelebrated) {
        _host.goalCelebrated = true;
        // ADR-C132 批3：成稿事件（写作目标首次达标 = 北极星漏斗底端）。
        // 埋点失败仅留痕绝不阻断（与 diff 埋点同纪律）。
        _recordCompletionEvent();
        ScaffoldMessenger.of(_host.context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('本章写作目标达成 🎉'),
              duration: Duration(seconds: 2),
            ),
          );
      }
    } else {
      _host.goalCelebrated = false;
    }
    // 批次91-1：编辑后调度合并保存（300ms debounce，纯纯写作多层保存机制）
    // 替代批次31 的立即 saveNow——连续输入在 300ms 窗口内只落库一次，
    // 保存失败提示改由 ref.listen 监听 saveError 变化触发（批次60 语义不变）
    _host.store?.scheduleSave();
    // 批次64（B62g）：记录编辑器活动时间戳，供心流判定（教师建议延迟触发）
    _host.ref.read(editorActivityProvider.notifier).state =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// ADR-C132 批3：成稿事件埋点（写作目标首次达标）。失败仅 debugPrint
  /// 留痕，绝不阻断写作流程（与 saveChapterContent 的 diff 埋点同纪律）。
  ///
  /// ADR-C134 批3（M4a）：独立起稿模式开关激活期间触发成稿时，给事件打
  /// independent_drafting 标记（复用 M2_recall 先例，零 schema 变更），
  /// 供里程碑证据卡观测。R-009：只记不判，不含成败判定。
  Future<void> _recordCompletionEvent() async {
    try {
      final db = _host.ref.read(appDatabaseProvider);
      final chapterRepo = ChapterRepository(db);
      final sessionId = await chapterRepo.firstSessionIdForChapter(
        _host.chapterId,
      );
      // 读独立写作开关（按章节隔离的会话内状态；教练面板开关写入同源 provider）。
      // ADR-C137 批1：M4a「这次我自己来」或 M4 第二格「这一章我自己写」任一
      // 激活 → completion 事件都打 independent_drafting 标记（完整章是更强的
      // 同语义声明，复用同一 source，不新增子类型——是否「完整」由字数判据消费）。
      final drafting = _host.ref.read(
        independentDraftingProvider(_host.chapterId),
      );
      final wholeChapter = _host.ref.read(
        wholeChapterDraftingProvider(_host.chapterId),
      );
      final independent = drafting || wholeChapter;
      await EditDiffEventRepository(db).recordCompletion(
        sessionId: sessionId,
        chapterId: _host.chapterId,
        source: independent ? CompletionSource.independentDrafting : null,
      );
    } catch (e) {
      debugPrint('[edit_diff] completion 埋点失败（不阻断）: $e');
    }
  }

  /// 批次86-1：程序化设置编辑器正文 → 同步回收板 diff 基线（防误判）
  void syncEditorText(String text) {
    _host.editorController.text = text;
    _host.lastEditorText = text;
  }

  /// 批次 36：标题变更 → 即时保存（对齐 RN handleTitleChange，无防抖）
  void onTitleChanged(String title) {
    _host.ref
        .read(writingStoreProvider(_host.chapterId).notifier)
        .updateChapterTitle(title.trim());
    // 批次96-4：标题即章节名——直写 repo 后刷新 store，抽屉/列表同步显示新名
    final msId = _host.resolvedManuscriptId;
    if (msId != null) {
      _host.ref.read(chapterStoreProvider(msId).notifier).loadChapters();
    }
  }

  /// 批次96-8：AppBar「一键排版」→ 按当前段落格式开关批量应用到全文
  /// （复用批次88-4 `_handleApplyParagraphFormat`：补/移除首行缩进、加/去段间空行）
  void handleFormatChapter() {
    final state = _host.ref.read(writingStoreProvider(_host.chapterId));
    applyParagraphFormat(state.indentParagraph, state.blankLineBetween);
  }

  /// 批次86-2：加载标点栏可见项配置 + 批次88-5 自定义项（用户级持久化）
  Future<void> loadPunctuationConfig() async {
    final repo = AppStateRepository(_host.ref.read(appDatabaseProvider));
    final ids = await repo.getPunctuationBarConfig();
    final customs = await repo.getPunctuationCustomItems();
    if (!_host.mounted) return;
    _host.setPunctuationConfig(ids: ids, items: customs);
  }

  /// 批次88-4：把当前段落格式批量应用到全文（按开关状态补/移除缩进、加/去空行）
  Future<void> applyParagraphFormat(
    bool applyIndent,
    bool applyBlankLine,
  ) async {
    var text = _host.editorController.text;
    // 先处理段间空行，再处理缩进（缩进只针对有内容的段落）
    if (applyBlankLine) {
      text = addBlankLineBetween(text);
    } else {
      text = removeBlankLineBetween(text);
    }
    if (applyIndent) {
      text = indentParagraphs(text);
    } else {
      text = removeParagraphIndent(text);
    }
    if (text == _host.editorController.text) {
      if (!_host.mounted) return;
      ScaffoldMessenger.of(_host.context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('全文已是当前段落格式'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }
    syncEditorText(text);
    _host.dirty = true;
    final store = _host.ref.read(
      writingStoreProvider(_host.chapterId).notifier,
    );
    store.updateContent(text);
    await store.saveNow();
    if (!_host.context.mounted) return;
    ScaffoldMessenger.of(_host.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已应用到全文'), duration: Duration(seconds: 2)),
      );
  }

  /// 批次85-3：在光标处插入常用语（插入后光标移到短语后，即时保存 + 轻提示）
  void insertQuickPhrase(String phrase) {
    final text = _host.editorController.text;
    final pos = _host.editorController.selection.isValid
        ? _host.editorController.selection.start
        : text.length;
    final newText = text.replaceRange(pos, pos, phrase);
    final cursor = pos + phrase.length;
    _host.suppressSelectionMenu = true;
    _host.editorController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _host.suppressSelectionMenu = false;
    onContentChanged(newText);
    if (!_host.mounted) return;
    ScaffoldMessenger.of(_host.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已插入'), duration: Duration(seconds: 1)),
      );
  }

  /// 批次82：时光机恢复版本
  /// restoreVersion 先把当前内容存为新版本（可逆），await 完成后再同步
  /// 编辑器 + 落库 + 提示（避免 saveNow 读到恢复前的内容）
  Future<void> restoreVersion(String content) async {
    final store = _host.ref.read(
      writingStoreProvider(_host.chapterId).notifier,
    );
    await store.restoreVersion(content);
    syncEditorText(content);
    _host.dirty = true;
    await store.saveNow();
    if (!_host.context.mounted) return;
    ScaffoldMessenger.of(_host.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已恢复到所选版本'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  /// B7 撤销（对齐 RN useUndoRedo.undo）：回退到上一个提交点并同步 controller
  void undo() {
    final store = _host.ref.read(
      writingStoreProvider(_host.chapterId).notifier,
    );
    store.undo();
    syncEditorText(store.currentContent);
    _host.dirty = true;
  }

  /// B7 重做（对齐 RN useUndoRedo.redo）
  void redo() {
    final store = _host.ref.read(
      writingStoreProvider(_host.chapterId).notifier,
    );
    store.redo();
    syncEditorText(store.currentContent);
    _host.dirty = true;
  }

  /// 底部标点栏点击：按当前选区插入字符（批次91-4：无效选区防御）
  void handlePunctuationTap(String char) {
    final text = _host.editorController.text;
    final sel = _host.editorController.selection;
    // 批次91-4：无效选区防御（ed-p2-3）——无效/空选区时在末尾插入，
    // 避免 replaceRange(-1, -1) 触发 RangeError
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : start;
    final newText = text.replaceRange(start, end, char);
    _host.editorController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + char.length),
    );
    onContentChanged(newText);
  }
}
