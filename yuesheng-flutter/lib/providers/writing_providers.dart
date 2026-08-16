// ─────────────────────────────────────────────────────────────
// writing_providers — 写作页状态管理
//
// 管理状态：
//   - chapter：当前加载的章节
//   - localContent：编辑器当前内容（编辑中可能与 DB 不一致）
//   - wordCount：由 localContent.length 派生
//   - fontSize / lineSpacing：编辑器排版设置
//   - isAiPanelOpen：AI 面板展开状态
//   - lastSavedAt：上次保存时间（null 表示从未保存）
//   - isLoading / isSaving / error：加载/保存/错误状态
//   - isOffline：当前离线（离线时保存走本地草稿，恢复网络自动同步）
//   - hasDraft：存在未同步的本地草稿（打开章节时若草稿较新 → 提示恢复）
//
// 状态转换：
//   - loadChapter()：从 DB 拉取章节，localContent = chapter.content（含草稿检测）
//   - updateContent(content)：更新 localContent + wordCount
//     （注意：不在此处做 debounce，由 WritingPage 负责调度 saveNow）
//   - saveNow()：写入 DB + 设置 lastSavedAt（离线时改为保存本地草稿）
//   - setOffline(offline)：更新离线状态；离线→在线且有草稿 → 自动同步
//   - restoreDraft() / discardDraft()：草稿恢复/放弃
//   - setFontSize / setLineSpacing：更新排版设置
//   - toggleAiPanel：切换 AI 面板
//   - clearError：清空错误
//
// 数据库通过构造函数注入（遵循 ManuscriptStore 模式）
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../services/error_handler.dart';
import 'app_providers.dart';

/// 编辑器背景预设 key（批次82：排版设置）
/// 'paper' 米纸（默认） | 'warm' 暖白 | 'green' 护眼绿 | 'dark' 暗夜
const String editorBgPaper = 'paper';
const String editorBgWarm = 'warm';
const String editorBgGreen = 'green';
const String editorBgDark = 'dark';

/// 写作页状态（不可变）
class WritingState {
  final Chapter? chapter;
  final String localContent;
  final int wordCount;
  final double fontSize;
  final double lineSpacing;
  /// 批次82：编辑器背景预设（editorBgPaper 等）
  final String editorBackground;
  /// 批次88-4：自动首行缩进（回车换行自动补两格全角空格；默认开）
  final bool indentParagraph;
  /// 批次88-4：段间空行（段落之间自动留空行；默认关）
  final bool blankLineBetween;
  /// 批次96-9：行段聚焦（淡化当前段以外内容；默认关；原 WritingPage 私有字段移入 store）
  final bool focusMode;
  /// 批次96-9：智能标点（输入「自动补全；默认开；原 WritingPage 私有字段移入 store）
  final bool smartPunctOn;
  /// 批次96-9：对话按钮(FAB)可见性（默认显示；原 WritingPage 私有字段移入 store）
  final bool fabVisible;
  /// 批次82：单章写作目标字数（0 = 未设置）
  final int goalWords;
  final bool isAiPanelOpen;
  final DateTime? lastSavedAt;
  final bool isLoading;
  final bool isSaving;
  /// 加载/整体错误（触发整页错误视图 + 重试）
  final String? error;
  /// 批次60：保存错误（仅状态条 + SnackBar 提示，不切换整页错误视图）
  final String? saveError;
  final bool isOffline;
  final bool hasDraft;
  final bool canUndo;
  final bool canRedo;

  const WritingState({
    this.chapter,
    this.localContent = '',
    this.wordCount = 0,
    this.fontSize = 16.0,
    this.lineSpacing = 1.6,
    this.editorBackground = editorBgPaper,
    this.indentParagraph = true,
    this.blankLineBetween = false,
    this.focusMode = false,
    this.smartPunctOn = true,
    this.fabVisible = true,
    this.goalWords = 0,
    this.isAiPanelOpen = false,
    this.lastSavedAt,
    this.isLoading = true,
    this.isSaving = false,
    this.error,
    this.saveError,
    this.isOffline = false,
    this.hasDraft = false,
    this.canUndo = false,
    this.canRedo = false,
  });

  /// copyWith：error/saveError 通过 clearError/clearSaveError 标志显式清空，
  /// 避免与「设置错误」语义冲突
  WritingState copyWith({
    Chapter? chapter,
    String? localContent,
    int? wordCount,
    double? fontSize,
    double? lineSpacing,
    String? editorBackground,
    bool? indentParagraph,
    bool? blankLineBetween,
    bool? focusMode,
    bool? smartPunctOn,
    bool? fabVisible,
    int? goalWords,
    bool? isAiPanelOpen,
    DateTime? lastSavedAt,
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    String? saveError,
    bool clearSaveError = false,
    bool clearLastSavedAt = false,
    bool? isOffline,
    bool? hasDraft,
    bool? canUndo,
    bool? canRedo,
  }) {
    return WritingState(
      chapter: chapter ?? this.chapter,
      localContent: localContent ?? this.localContent,
      wordCount: wordCount ?? this.wordCount,
      fontSize: fontSize ?? this.fontSize,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      editorBackground: editorBackground ?? this.editorBackground,
      indentParagraph: indentParagraph ?? this.indentParagraph,
      blankLineBetween: blankLineBetween ?? this.blankLineBetween,
      focusMode: focusMode ?? this.focusMode,
      smartPunctOn: smartPunctOn ?? this.smartPunctOn,
      fabVisible: fabVisible ?? this.fabVisible,
      goalWords: goalWords ?? this.goalWords,
      isAiPanelOpen: isAiPanelOpen ?? this.isAiPanelOpen,
      lastSavedAt: clearLastSavedAt ? null : (lastSavedAt ?? this.lastSavedAt),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      isOffline: isOffline ?? this.isOffline,
      hasDraft: hasDraft ?? this.hasDraft,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
    );
  }
}

/// 写作页状态管理器
///
/// chapterId 作为成员变量；数据库通过构造函数注入。
/// updateContent 不包含 debounce 逻辑——由 WritingPage 负责调度 saveNow。
class WritingStore extends StateNotifier<WritingState> {
  final AppDatabase _db;
  final String chapterId;

  /// 待恢复的草稿（loadChapter 检测到较新草稿时暂存，供 restoreDraft 使用）
  ChapterDraft? _pendingDraft;

  /// 当前编辑器内容（供 UI 在 restoreDraft 后同步 controller）
  String get currentContent => state.localContent;

  /// 批次60：当前保存错误（供 UI 判断；state 为 protected，外部经此读取）
  String? get currentSaveError => state.saveError;

  /// 批次82：下一版快照触发字数阈值（每跨 200 字落一次快照）
  /// 在 loadChapter 播种（避免存量长文首次输入即连拍），saveNow 成功后检查
  int _nextSnapshotWords = AppStateRepository.chapterVersionInterval;

  // ── 批次91-1：保存 debounce（纯纯写作 300ms 多层保存机制）──
  /// 合并写入窗口：连续输入在 300ms 内只落库一次
  static const Duration saveDebounce = Duration(milliseconds: 300);

  /// 未决保存定时器（scheduleSave 调度，saveNow 执行时取消）
  Timer? _saveTimer;

  /// 是否存在未决的合并保存（写作页 dispose 强制保存判定用）
  bool get hasPendingSave => _saveTimer != null;

  // ── B7 撤销/重做（复刻 RN hooks/useUndoRedo.ts）──
  /// 历史上限（RN UNDO_REDO.MAX_HISTORY）
  static const int maxHistory = 10;

  /// 历史提交 debounce（批次91-2：撤销栈与保存完全独立，1.5s 停输入才提交）
  /// 纯纯写作撤销栈独立于保存——保存是 300ms 合并写库，历史点是用户停输入才落
  static const Duration historyDebounce = Duration(milliseconds: 1500);
  final List<String> _past = [];
  final List<String> _future = [];
  String _lastCommitted = '';
  Timer? _historyTimer;

  WritingStore(this._db, this.chapterId) : super(const WritingState());

  @override
  void dispose() {
    // 批次91-1：取消未决的保存定时器（dispose 后 store 已不可用）
    _saveTimer?.cancel();
    _saveTimer = null;
    // B7：取消未决的历史提交定时器，避免 dispose 后回调访问已销毁状态
    _historyTimer?.cancel();
    _historyTimer = null;
    super.dispose();
  }

  /// 批次91-1：调度合并保存（300ms 窗口内多次输入只落库一次）
  /// 由 WritingPage._onContentChanged 调用，替代批次31 的立即 saveNow。
  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, () {
      _saveTimer = null;
      unawaited(saveNow());
    });
  }

  /// 批次91-1/91-2：取消未决的保存与历史定时器（页面销毁时调用，
  /// 防 dispose 后 timer 回调访问已销毁状态 / 测试 binding 报 pending timer）
  void cancelPendingTimers() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _historyTimer?.cancel();
    _historyTimer = null;
  }

  /// 从 DB 加载章节，localContent = chapter.content
  /// 含草稿检测：草稿 savedAt 晚于章节 updatedAt → 提示恢复；更旧 → 清除
  Future<void> loadChapter() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = ChapterRepository(_db);
      final chapter = await repo.getChapter(chapterId);
      if (chapter == null) {
        state = state.copyWith(isLoading: false, error: '章节不存在: $chapterId');
        return;
      }

      // 草稿检测（对齐 RN chapter-editor.tsx#L118-L138）
      final appStateRepo = AppStateRepository(_db);
      final draft = await appStateRepo.getChapterDraft(chapterId);
      var hasDraft = false;
      if (draft != null && draft.savedAt > chapter.updatedAt) {
        _pendingDraft = draft;
        hasDraft = true;
      } else if (draft != null) {
        // 草稿已过期（章节已保存更新）→ 清除陈旧草稿
        await appStateRepo.clearChapterDraft(chapterId);
      }

      state = state.copyWith(
        chapter: chapter,
        localContent: chapter.content,
        wordCount: chapter.content.length,
        isLoading: false,
        hasDraft: hasDraft,
        clearError: true,
      );
      // B7：加载新章节 → 重置历史栈（对齐 RN useEffect [initialValue]）
      _resetHistory(chapter.content);
      // 批次82：播种版本快照阈值（避免存量长文首次输入即连拍快照）
      _nextSnapshotWords =
          (chapter.content.length ~/ AppStateRepository.chapterVersionInterval +
              1) *
          AppStateRepository.chapterVersionInterval;
      // 批次82：加载排版设置（字号/行距/背景，用户级持久化）
      await loadEditorSettings();
      // 批次82：加载单章写作目标（章节级持久化）
      await loadGoalWords();
      debugPrint(
        '[WritingStore] loadChapter 成功: chapterId=$chapterId contentLength=${chapter.content.length} hasDraft=$hasDraft',
      );
    } catch (e) {
      debugPrint(
        '[WritingStore] loadChapter 失败: chapterId=$chapterId error=$e',
      );
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 更新编辑器内容（同步 wordCount）
  ///
  /// 注意：不在此处做 debounce，由 WritingPage 负责调度 saveNow。
  /// B7：调度历史提交（debounce 500ms 后把上一次已提交值压栈，对齐 RN setValue）
  void updateContent(String content) {
    state = state.copyWith(localContent: content, wordCount: content.length);
    _scheduleHistoryPush();
  }

  /// 更新章节标题（批次 36）：DB 即时保存 + state 同步
  /// 对齐 RN chapter-editor handleTitleChange（输入即保存，无防抖）
  Future<void> updateChapterTitle(String title) async {
    final current = state.chapter;
    try {
      final repo = ChapterRepository(_db);
      await repo.updateChapterTitle(chapterId, title);
      if (current != null) {
        state = state.copyWith(
          chapter: Chapter(
            id: current.id,
            manuscriptId: current.manuscriptId,
            title: title,
            content: current.content,
            wordCount: current.wordCount,
            sortOrder: current.sortOrder,
            status: current.status,
            lastDiagnosedAt: current.lastDiagnosedAt,
            previousContent: current.previousContent,
            createdAt: current.createdAt,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
        );
      }
      debugPrint(
        '[WritingStore] updateChapterTitle 成功: chapterId=$chapterId title=$title',
      );
    } catch (e) {
      debugPrint(
        '[WritingStore] updateChapterTitle 失败: chapterId=$chapterId error=$e',
      );
      state = state.copyWith(error: e.toString());
    }
  }

  /// B7：调度历史提交（对齐 RN setValue 内 debounce）
  void _scheduleHistoryPush() {
    _historyTimer?.cancel();
    _historyTimer = Timer(historyDebounce, () {
      _pushHistory();
    });
  }

  /// B7：把当前已提交值压入过去栈（对齐 RN pushHistory）
  void _pushHistory() {
    final current = _lastCommitted;
    final next = state.localContent;
    if (next == current) return;
    _past.add(current);
    if (_past.length > maxHistory) {
      _past.removeAt(0);
    }
    _future.clear();
    _lastCommitted = next;
    _updateHistoryFlags();
  }

  /// B7：立即提交历史（保存成功时调用，对齐 RN commit）
  void commitHistory() {
    _historyTimer?.cancel();
    _historyTimer = null;
    _pushHistory();
  }

  /// B7：撤销到上一个提交点（对齐 RN undo）
  void undo() {
    _historyTimer?.cancel();
    _historyTimer = null;
    if (_past.isEmpty) return;
    final prev = _past.removeLast();
    _future.add(_lastCommitted);
    _lastCommitted = prev;
    state = state.copyWith(localContent: prev, wordCount: prev.length);
    _updateHistoryFlags();
  }

  /// B7：重做（对齐 RN redo）
  void redo() {
    _historyTimer?.cancel();
    _historyTimer = null;
    if (_future.isEmpty) return;
    final next = _future.removeLast();
    _past.add(_lastCommitted);
    if (_past.length > maxHistory) {
      _past.removeAt(0);
    }
    _lastCommitted = next;
    state = state.copyWith(localContent: next, wordCount: next.length);
    _updateHistoryFlags();
  }

  /// B7：重置历史栈（对齐 RN reset）
  void _resetHistory(String initial) {
    _historyTimer?.cancel();
    _historyTimer = null;
    _past.clear();
    _future.clear();
    _lastCommitted = initial;
    _updateHistoryFlags();
  }

  /// B7：同步撤销/重做可用标志
  void _updateHistoryFlags() {
    state = state.copyWith(
      canUndo: _past.isNotEmpty,
      canRedo: _future.isNotEmpty,
    );
  }

  /// 立即写入 DB，并记录 lastSavedAt
  /// 离线时改为保存本地草稿（对齐 RN scheduleDraftSave）
  /// 批次91-2：保存不再提交撤销历史点（撤销栈独立，由 _scheduleHistoryPush
  /// 1.5s 停输入 debounce 提交）——避免「每次按键即历史点、10 条上限秒耗尽」
  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    state = state.copyWith(isSaving: true, clearError: true, clearSaveError: true);
    try {
      if (state.isOffline) {
        final appStateRepo = AppStateRepository(_db);
        final title = state.chapter?.title ?? '';
        await appStateRepo.saveChapterDraft(
          chapterId,
          title,
          state.localContent,
        );
        state = state.copyWith(
          isSaving: false,
          hasDraft: true,
          clearError: true,
        );
        // 批次82：跨 200 字边界 → 落版本快照（离线草稿同样留痕）
        await _maybeSnapshot();
        debugPrint(
          '[WritingStore] saveNow 离线草稿已存: chapterId=$chapterId contentLength=${state.localContent.length}',
        );
        return;
      }
      final repo = ChapterRepository(_db);
      await repo.saveChapterContent(chapterId, state.localContent);
      state = state.copyWith(
        isSaving: false,
        lastSavedAt: DateTime.now(),
        clearError: true,
      );
      // 批次82：跨 200 字边界 → 落版本快照（时光机留痕）
      await _maybeSnapshot();
      debugPrint(
        '[WritingStore] saveNow 成功: chapterId=$chapterId contentLength=${state.localContent.length}',
      );
    } catch (e) {
      debugPrint('[WritingStore] saveNow 失败: chapterId=$chapterId error=$e');
      // 批次60：保存失败计入 error_logs（category=database），供保存失败率观测
      ErrorHandler.instance.captureError(
        level: 'error',
        category: 'database',
        message: 'WritingStore.saveNow 失败',
        context: {'chapterId': chapterId, 'error': '$e'},
      );
      // 保存失败只标记 saveError（状态条 + SnackBar 提示），不切换整页错误视图
      state = state.copyWith(isSaving: false, saveError: '$e');
    }
  }

  /// 更新离线状态
  /// 离线 → 在线且有草稿 → 自动同步草稿到章节（对齐 RN useEffect [isOffline]）
  Future<void> setOffline(bool offline) async {
    final wasOffline = state.isOffline;
    if (wasOffline == offline) return;
    state = state.copyWith(isOffline: offline);
    if (wasOffline && !offline && state.hasDraft) {
      await syncDraftToChapter();
    }
  }

  /// 恢复草稿内容到编辑器（保留草稿，待下次保存/同步落库）
  void restoreDraft() {
    final draft = _pendingDraft;
    if (draft == null) return;
    state = state.copyWith(
      localContent: draft.content,
      wordCount: draft.content.length,
      hasDraft: true,
    );
    // B7：恢复草稿 → 重置历史栈（草稿为新编辑基线）
    _resetHistory(draft.content);
    debugPrint(
      '[WritingStore] 草稿已恢复: chapterId=$chapterId contentLength=${draft.content.length}',
    );
  }

  /// 放弃草稿（清除本地草稿，保留章节原文）
  Future<void> discardDraft() async {
    _pendingDraft = null;
    await AppStateRepository(_db).clearChapterDraft(chapterId);
    state = state.copyWith(hasDraft: false, clearError: true);
    debugPrint('[WritingStore] 草稿已放弃: chapterId=$chapterId');
  }

  /// 同步草稿到章节（写入 DB + 清除草稿）
  /// 对齐 RN syncDraftToChapter
  Future<void> syncDraftToChapter() async {
    if (state.isOffline || !state.hasDraft) return;
    try {
      final repo = ChapterRepository(_db);
      await repo.saveChapterContent(chapterId, state.localContent);
      await AppStateRepository(_db).clearChapterDraft(chapterId);
      _pendingDraft = null;
      state = state.copyWith(
        hasDraft: false,
        lastSavedAt: DateTime.now(),
        clearError: true,
      );
      debugPrint(
        '[WritingStore] 草稿已同步到章节: chapterId=$chapterId contentLength=${state.localContent.length}',
      );
    } catch (e) {
      debugPrint('[WritingStore] 草稿同步失败: chapterId=$chapterId error=$e');
    }
  }

  /// 批次82：从 app_state 加载单章写作目标（章节级，0 = 未设置）
  Future<void> loadGoalWords() async {
    try {
      final raw = await AppStateRepository(_db).getValue(
        'chapter_goal:$chapterId',
      );
      final goal = int.tryParse(raw ?? '') ?? 0;
      state = state.copyWith(goalWords: goal < 0 ? 0 : goal);
    } catch (_) {
      // 读取失败沿用当前值
    }
  }

  /// 批次82：设置单章写作目标（章节级持久化；0 = 清除目标）
  Future<void> setGoalWords(int goal) async {
    final safe = goal < 0 ? 0 : goal;
    state = state.copyWith(goalWords: safe);
    await AppStateRepository(_db).setValue(
      'chapter_goal:$chapterId',
      safe.toString(),
    );
  }

  /// 批次82：跨 200 字边界 → 落一章版本快照（时光机留痕）
  /// 仅在 saveNow 成功后调用（快照内容 == 已落库内容）
  Future<void> _maybeSnapshot() async {
    final wc = state.wordCount;
    if (wc < _nextSnapshotWords) return;
    _nextSnapshotWords =
        (wc ~/ AppStateRepository.chapterVersionInterval + 1) *
        AppStateRepository.chapterVersionInterval;
    await AppStateRepository(_db).addChapterVersion(chapterId, state.localContent);
    debugPrint(
      '[WritingStore] 版本快照已落: chapterId=$chapterId wordCount=$wc',
    );
  }

  /// 批次82：时光机恢复版本
  /// 恢复前先把当前内容存为新版本（恢复可逆，不丢当前稿）
  Future<void> restoreVersion(String content) async {
    await AppStateRepository(_db).addChapterVersion(chapterId, state.localContent);
    state = state.copyWith(localContent: content, wordCount: content.length);
    // B7：恢复版本 → 重置历史栈（版本内容为新编辑基线）
    _resetHistory(content);
    // 从恢复后的字数重新播种快照阈值
    _nextSnapshotWords =
        (content.length ~/ AppStateRepository.chapterVersionInterval + 1) *
        AppStateRepository.chapterVersionInterval;
    debugPrint(
      '[WritingStore] 版本已恢复: chapterId=$chapterId contentLength=${content.length}',
    );
  }

  /// 更新字号（内存态，即时预览；持久化见 persistEditorSettings）
  void setFontSize(double fontSize) {
    state = state.copyWith(fontSize: fontSize);
  }

  /// 更新行距（内存态，即时预览；持久化见 persistEditorSettings）
  void setLineSpacing(double lineSpacing) {
    state = state.copyWith(lineSpacing: lineSpacing);
  }

  /// 更新编辑器背景预设（批次82；内存态，即时预览）
  void setEditorBackground(String background) {
    state = state.copyWith(editorBackground: background);
  }

  /// 批次88-4：更新自动首行缩进（内存态，即时生效）
  void setIndentParagraph(bool on) {
    state = state.copyWith(indentParagraph: on);
  }

  /// 批次88-4：更新段间空行（内存态，即时生效）
  void setBlankLineBetween(bool on) {
    state = state.copyWith(blankLineBetween: on);
  }

  /// 批次96-9：更新行段聚焦开关（内存态，即时生效；持久化见 persistEditorSettings）
  void setFocusMode(bool on) {
    state = state.copyWith(focusMode: on);
  }

  /// 批次96-9：更新智能标点开关（内存态，即时生效）
  void setSmartPunctOn(bool on) {
    state = state.copyWith(smartPunctOn: on);
  }

  /// 批次96-9：更新对话按钮(FAB)可见性（内存态，即时生效）
  void setFabVisible(bool on) {
    state = state.copyWith(fabVisible: on);
  }

  /// 批次82：从 app_state 加载排版设置（用户级，跨章节生效）
  Future<void> loadEditorSettings() async {
    try {
      final repo = AppStateRepository(_db);
      final fontSize = double.tryParse(
            await repo.getValue('editor_font_size') ?? '',
          ) ??
          state.fontSize;
      final lineSpacing = double.tryParse(
            await repo.getValue('editor_line_spacing') ?? '',
          ) ??
          state.lineSpacing;
      final background =
          await repo.getValue('editor_background') ?? state.editorBackground;
      // 批次88-4：段落格式开关（默认缩进开 / 空行关）
      final indent = await repo.getValue('editor_indent_paragraph');
      final blankLine = await repo.getValue('editor_blank_line');
      // 批次96-9：三个开关从 WritingPage 私有字段移入 store（复用现有持久化 key）
      final focusRaw = await repo.getValue('editor_focus_mode');
      final smartPunct = await repo.getSmartPunctuationEnabled();
      final fabVisible = await repo.getFabVisible();
      // 合法性护栏：防脏数据越界
      state = state.copyWith(
        fontSize: fontSize >= 12 && fontSize <= 30 ? fontSize : state.fontSize,
        lineSpacing: lineSpacing >= 1.0 && lineSpacing <= 3.0
            ? lineSpacing
            : state.lineSpacing,
        editorBackground: background,
        indentParagraph: indent == null || indent == '1',
        blankLineBetween: blankLine == '1',
        focusMode: focusRaw == '1',
        smartPunctOn: smartPunct,
        fabVisible: fabVisible,
      );
    } catch (_) {
      // 读取失败沿用默认/当前值
    }
  }

  /// 批次82：持久化排版设置到 app_state（用户级，跨章节生效）
  Future<void> persistEditorSettings() async {
    final repo = AppStateRepository(_db);
    await repo.setValue('editor_font_size', state.fontSize.toString());
    await repo.setValue('editor_line_spacing', state.lineSpacing.toString());
    await repo.setValue('editor_background', state.editorBackground);
    // 批次88-4：段落格式开关
    await repo.setValue(
      'editor_indent_paragraph',
      state.indentParagraph ? '1' : '0',
    );
    await repo.setValue(
      'editor_blank_line',
      state.blankLineBetween ? '1' : '0',
    );
    // 批次96-9：三个开关持久化（复用现有 key，向后兼容存量用户数据）
    await repo.setValue('editor_focus_mode', state.focusMode ? '1' : '0');
    await repo.setSmartPunctuationEnabled(state.smartPunctOn);
    await repo.setFabVisible(state.fabVisible);
  }

  /// 切换 AI 面板展开状态
  void toggleAiPanel() {
    state = state.copyWith(isAiPanelOpen: !state.isAiPanelOpen);
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// family provider：每个 chapterId 一个独立的 WritingStore 实例
final writingStoreProvider =
    StateNotifierProvider.family<WritingStore, WritingState, String>((
      ref,
      chapterId,
    ) {
      final db = ref.watch(appDatabaseProvider);
      return WritingStore(db, chapterId);
    });
