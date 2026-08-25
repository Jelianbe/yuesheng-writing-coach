// ─────────────────────────────────────────────────────────────
// WritingPage — 写作页
// 4 层结构（百灵极简 + 月色竹青配色）：
//   1. AppBar (48dp)
//   2. Editor (Expanded, TextField, 米纸底)
//   3. PunctuationBar (36dp)
//   4. FloatingActionButton（AI 面板关闭时显示）
//   5. bottomSheet（AI 面板占位，AI 面板打开时显示）
//
// 自动保存：
//   - onChanged → updateContent + 立即 saveNow（批次 31：编辑后即时落库）
//   - dispose 时若有未保存改动 → 强制 saveNow
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderEditable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../providers/app_providers.dart';
import '../providers/manuscript_providers.dart';
import '../providers/writing_providers.dart';
import '../router/app_routes.dart';
import '../services/suggestion_adoption_service.dart';
import '../utils/chapter_title.dart';
import '../utils/paragraph_format.dart';
import 'chapter_tree_drawer.dart';
import 'editing/focus_aware_editing_controller.dart';
import 'editor_settings_sheet.dart';
import '../config/editor_background_presets.dart';
import 'outline_drawer.dart';
import 'paragraph_format_formatter.dart';
import 'punctuation_bar.dart';
import 'quick_phrase_sheet.dart';
import 'recycle_bin_sheet.dart';
import 'search_replace_sheet.dart';
import 'selection_ai_sheet.dart';
import 'smart_punctuation_formatter.dart';
import 'style_profile_sheet.dart';
import 'version_time_machine_sheet.dart';
import 'writing_coach_panel.dart';
import 'writing/goal_dialog.dart';
import 'writing_menu_sheet.dart';
import 'writing_stats_sheet.dart';

part 'writing_page_selection_ai.dart';
part 'writing_page_find_replace.dart';
part 'writing_page_chapter_nav.dart';
part 'writing_page_status_builders.dart';

/// 计算 [oldText] → [newText] 变化中被删除的连续片段（批次86-1 回收板）。
/// 仅当变化是"纯删除"（new 是 old 删去一段得到）时返回被删片段（trim 后），
/// 插入 / 替换 / 增删混合返回 null（保守，避免误存）。
String? extractRemovedText(String oldText, String newText) {
  if (newText.length >= oldText.length) return null; // 未变短，非删除
  var prefix = 0;
  final minLen = newText.length;
  while (prefix < minLen && oldText[prefix] == newText[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < minLen - prefix &&
      oldText[oldText.length - 1 - suffix] ==
          newText[newText.length - 1 - suffix]) {
    suffix++;
  }
  // new 的中间段必须为空（纯删除），否则是替换/混合，保守不存
  final newMiddle = newText.substring(prefix, newText.length - suffix);
  if (newMiddle.isNotEmpty) return null;
  final removed = oldText.substring(prefix, oldText.length - suffix).trim();
  if (removed.isEmpty) return null;
  return removed;
}

class WritingPage extends ConsumerStatefulWidget {
  final String chapterId;
  final String? chapterTitle; // 可选，加载完成前用于显示
  final String? manuscriptId; // 所属作品 ID，供教练面板创建隔离会话
  /// 批次96-11：跨章全文搜索跳转携带的光标定位（章节加载完成后定位到命中处）
  final int? initialCursorOffset;
  final VoidCallback? onBack;
  // 批次83：章节树快速跳转（默认走真路由 context.go；测试注入回调验证）
  final void Function(String chapterId, String chapterTitle)? onJumpToChapter;

  const WritingPage({
    super.key,
    required this.chapterId,
    this.chapterTitle,
    this.manuscriptId,
    this.initialCursorOffset,
    this.onBack,
    this.onJumpToChapter,
  });

  @override
  ConsumerState<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends ConsumerState<WritingPage> {
  late final FocusAwareEditingController _controller;
  late final FocusNode _focusNode;

  /// 批次 36：章节标题输入（AppBar 内可编辑，输入即保存）
  late final TextEditingController _titleController;
  bool _dirty = false;

  /// 批次60：保存失败 SnackBar 已提示标志（避免连续失败刷屏）
  bool _saveErrorShown = false;
  // 在 build 中捕获，用于 dispose 时调用 saveNow（dispose 时 ref 已失效）
  WritingStore? _store;
  // 网络状态订阅（离线 → 保存走本地草稿 + 横幅提示 + 恢复网络自动同步）
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  // 草稿恢复弹窗只弹一次
  bool _draftDialogShown = false;
  // B3 划词诊断：当前选中文本 + 选区 + 浮动菜单可见性 + 待注入面板的选段
  String _selectedText = '';
  // 批次83：选中时的选区（改写/续写/扩写落稿按此偏移替换/插入）
  TextSelection? _selection;
  bool _showSelectionMenu = false;

  /// 批次95-1：划词菜单相对正文 Stack 的左上角（null = 无法定位，保持隐藏）
  Offset? _selectionMenuPos;

  /// 批次95-1：正文编辑区 Stack 的 GlobalKey（划词菜单位置反查 RenderEditable）
  final GlobalKey _editorStackKey = GlobalKey();
  String? _pendingDiagnoseText;
  // 批次84-2：查找替换定位期间抑制划词菜单（程序化选区 ≠ 用户划词）
  bool _suppressSelectionMenu = false;

  /// 批次96-11：跨章全文搜索定位已执行标志（内容就绪后只定位一次）
  bool _searchCursorLocated = false;

  /// 批次82：写作目标达标已提示标志（跨过目标线只轻提示一次）
  bool _goalCelebrated = false;

  /// 批次86-1：回收板——编辑器上一次文本（供 onChanged 时 diff 删除片段）
  String? _lastEditorText;

  /// 批次86-1：被删片段长度达到该值才入回收板（短删改不值得找回）
  static const int _minRecycleBinLength = 8;

  /// 批次86-2：标点栏可见项 id 顺序（null = 默认全部，用户级持久化）
  List<String>? _punctBarIds;

  /// 批次88-5：标点栏自定义项（用户在排版设置增删，用户级持久化）
  List<PunctuationItem> _punctCustomItems = const [];

  /// 批次88-2：对话按钮拖动后的位置（null = 右下角默认；持久化 `fab_position`）
  Offset? _fabOffset;

  /// 批次88-2：拖动起点时 FAB 的位置（body 内局部坐标，配合全局位移计算）
  Offset _fabDragStart = Offset.zero;

  /// 批次88-2：拖动起点手势的全局位置（用于差值计算，避免 FAB 移动导致坐标系漂移）
  Offset _fabDragStartGlobal = Offset.zero;

  /// 批次88-2：对话按钮尺寸（Material FAB 默认）
  static const double _fabSize = 56;

  // 批次83：章节树抽屉——Scaffold key（⋮ 菜单点击后打开抽屉）+ 打开计数
  // （每次打开以新 ValueKey 重建抽屉 → 列表数据/标题保持最新）
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _treeOpenCount = 0;

  // 批次83：大纲抽屉（endDrawer）——打开计数（每次打开重建 + 失效缓存）
  int _outlineOpenCount = 0;

  /// 批次83：解析所属作品 ID（优先路由参数，其次已加载章节反查；
  /// 深链进入时 manuscriptId 可能为空，章节加载完成后必有 manuscriptId）
  String? get _resolvedManuscriptId {
    final fromWidget = widget.manuscriptId;
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    return ref
        .read(writingStoreProvider(widget.chapterId))
        .chapter
        ?.manuscriptId;
  }

  @override
  void initState() {
    super.initState();
    _controller = FocusAwareEditingController();
    _focusNode = FocusNode();
    _titleController = TextEditingController();
    // B3 划词诊断：监听选中文本变化（Flutter 3.44 TextField 无公共
    // onSelectionChanged，改用 controller listener）
    _controller.addListener(_onControllerSelectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(writingStoreProvider(widget.chapterId).notifier).loadChapter();
    });
    // 批次86-2：加载标点栏可见配置（用户级持久化）
    _loadPunctuationConfig();
    // 批次88-2：加载对话按钮位置（可见性开关已随排版设置移入 store，loadChapter 加载）
    _loadFabPosition();
    // 对齐 RN useNetInfo：监听网络状态变化 → 写入 store（离线草稿/恢复同步）
    // 测试环境无 connectivity 平台插件 → onError 容错静默降级（离线能力不可用时不影响编辑）
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        final offline = results.contains(ConnectivityResult.none);
        ref
            .read(writingStoreProvider(widget.chapterId).notifier)
            .setOffline(offline);
      },
      onError: (Object e) {
        debugPrint('[WritingPage] 网络状态监听不可用: $e');
      },
    );
    // 初始状态查询（流只在变化时触发，需主动取一次初值）
    Connectivity()
        .checkConnectivity()
        .then((results) {
          if (!mounted) return;
          final offline = results.contains(ConnectivityResult.none);
          ref
              .read(writingStoreProvider(widget.chapterId).notifier)
              .setOffline(offline);
        })
        .catchError((Object e) {
          debugPrint('[WritingPage] 初始网络检查不可用: $e');
        });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    // 批次91-1：有未保存改动或未决合并保存 → 离开时强制保存（fire-and-forget）
    // （_dirty 在 scheduleSave 路径下不再自动清除，加上 hasPendingSave 双保险，
    // 保证 300ms 窗口内返回页面时未落库内容不丢失）
    if ((_dirty || _store?.hasPendingSave == true) && _store != null) {
      // 立即取消未决的保存/历史定时器（防 dispose 后回调访问已销毁状态，
      // 以及测试 binding 报 pending timer）；保存走下一帧强制 saveNow
      _store?.cancelPendingTimers();
      // 延迟到下一帧执行：此时 widget 已完全卸载，ref.watch 依赖已清理，
      // state 变化不会触发已销毁 element 的 rebuild。
      final store = _store;
      final chapterId = widget.chapterId;
      debugPrint('[WritingPage] dispose 触发强制保存: chapterId=$chapterId');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // saveNow 内部 catch 所有异常并 debugPrint（含 chapterId + error）；
        // widget 已销毁无人监听 state.error，此处仅留 dispose 上下文标记，
        // 与 [WritingStore] saveNow 失败 日志通过 chapterId 关联排查。
        store?.saveNow();
      });
    }
    _controller.dispose();
    _focusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _onContentChanged(String content) {
    _dirty = true;
    // 批次86-1：回收板——用户删除/剪切 ≥8 字的连续片段 → 自动入回收板
    final prev = _lastEditorText;
    _lastEditorText = content;
    if (prev != null) {
      final removed = extractRemovedText(prev, content);
      if (removed != null && removed.length >= _minRecycleBinLength) {
        AppStateRepository(
          ref.read(appDatabaseProvider),
        ).addRecycleBinItem(removed);
      }
    }
    _store?.updateContent(content);
    // 批次82：跨过写作目标线 → 轻提示一次（降回线下后再跨越可再次提示）
    final ws = ref.read(writingStoreProvider(widget.chapterId));
    if (ws.goalWords > 0 && ws.wordCount >= ws.goalWords) {
      if (!_goalCelebrated) {
        _goalCelebrated = true;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('本章写作目标达成 🎉'),
              duration: Duration(seconds: 2),
            ),
          );
      }
    } else {
      _goalCelebrated = false;
    }
    // 批次91-1：编辑后调度合并保存（300ms debounce，纯纯写作多层保存机制）
    // 替代批次31 的立即 saveNow——连续输入在 300ms 窗口内只落库一次，
    // 保存失败提示改由 ref.listen 监听 saveError 变化触发（批次60 语义不变）
    _store?.scheduleSave();
    // 批次64（B62g）：记录编辑器活动时间戳，供心流判定（教师建议延迟触发）
    ref.read(editorActivityProvider.notifier).state =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// 批次86-1：程序化设置编辑器正文 → 同步回收板 diff 基线（防误判）
  void _syncEditorText(String text) {
    _controller.text = text;
    _lastEditorText = text;
  }

  /// 批次 36：标题变更 → 即时保存（对齐 RN handleTitleChange，无防抖）
  void _onTitleChanged(String title) {
    ref
        .read(writingStoreProvider(widget.chapterId).notifier)
        .updateChapterTitle(title.trim());
    // 批次96-4：标题即章节名——失效章节列表缓存，抽屉/列表同步显示新名
    final msId = _resolvedManuscriptId;
    if (msId != null) {
      ref.invalidate(chapterListProvider(msId));
    }
  }

  /// 千位分隔符格式化（如 3256 → "3,256"）
  String _formatNum(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  /// 字数格式化：>=10000 → "1.2万字"，否则 → "3,256字"（千位分隔符）
  String _formatWordCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万字';
    }
    return '${_formatNum(count)}字';
  }

  void _handleBack() {
    // 批次93-3：返回前发书架刷新信号（详情页/深链直接回书架时书架可感知）
    ref.read(bookshelfRefreshSignalProvider.notifier).state++;
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// 批次96-8：AppBar「一键排版」→ 按当前段落格式开关批量应用到全文
  /// （复用批次88-4 `_handleApplyParagraphFormat`：补/移除首行缩进、加/去段间空行）
  void _handleFormatChapter() {
    final state = ref.read(writingStoreProvider(widget.chapterId));
    _handleApplyParagraphFormat(state.indentParagraph, state.blankLineBetween);
  }

  /// 批次86-2：加载标点栏可见项配置 + 批次88-5 自定义项（用户级持久化）
  Future<void> _loadPunctuationConfig() async {
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    final ids = await repo.getPunctuationBarConfig();
    final customs = await repo.getPunctuationCustomItems();
    if (!mounted) return;
    setState(() {
      _punctBarIds = ids;
      _punctCustomItems = customs;
    });
  }

  /// 批次88-2：加载对话按钮位置（用户级持久化；可见性开关已随排版设置移入 store）
  Future<void> _loadFabPosition() async {
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    final pos = await repo.getFabPosition();
    if (!mounted) return;
    setState(() => _fabOffset = pos);
  }

  /// 批次88-2：恢复对话按钮到右下角默认位置（排版设置入口）
  Future<void> _resetFabPosition() async {
    setState(() => _fabOffset = null);
    await AppStateRepository(ref.read(appDatabaseProvider)).clearFabPosition();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('对话按钮已回到右下角'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  /// 批次88-4：把当前段落格式批量应用到全文（按开关状态补/移除缩进、加/去空行）
  Future<void> _handleApplyParagraphFormat(
    bool applyIndent,
    bool applyBlankLine,
  ) async {
    var text = _controller.text;
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
    if (text == _controller.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('全文已是当前段落格式'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }
    _syncEditorText(text);
    _dirty = true;
    final store = ref.read(writingStoreProvider(widget.chapterId).notifier);
    store.updateContent(text);
    await store.saveNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已应用到全文'), duration: Duration(seconds: 2)),
      );
  }

  /// 批次85-3：打开快捷短语弹层（常用语管理 + 光标插入）
  void _handleOpenQuickPhrases() {
    QuickPhraseSheet.show(context, onInsert: _handleInsertQuickPhrase);
  }

  /// 批次86-1：打开回收板弹层（删除/剪切的长文本找回）
  void _handleOpenRecycleBin() {
    RecycleBinSheet.show(context, onRestore: _handleInsertQuickPhrase);
  }

  /// 批次85-4：打开当前文风弹层（教学特色：风格画像五维展示）
  void _handleOpenStyleProfile() {
    StyleProfileSheet.show(context);
  }

  /// 批次85-5：打开写作统计弹层（近 14 天写作曲线）
  void _handleOpenWritingStats() {
    WritingStatsSheet.show(context);
  }

  /// 批次85-3：在光标处插入常用语（插入后光标移到短语后，即时保存 + 轻提示）
  void _handleInsertQuickPhrase(String phrase) {
    final text = _controller.text;
    final pos = _controller.selection.isValid
        ? _controller.selection.start
        : text.length;
    final newText = text.replaceRange(pos, pos, phrase);
    final cursor = pos + phrase.length;
    _suppressSelectionMenu = true;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _suppressSelectionMenu = false;
    _onContentChanged(newText);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已插入'), duration: Duration(seconds: 1)),
      );
  }

  /// 批次82：时光机恢复版本
  /// restoreVersion 先把当前内容存为新版本（可逆），await 完成后再同步
  /// 编辑器 + 落库 + 提示（避免 saveNow 读到恢复前的内容）
  Future<void> _handleRestoreVersion(String content) async {
    final store = ref.read(writingStoreProvider(widget.chapterId).notifier);
    await store.restoreVersion(content);
    _syncEditorText(content);
    _dirty = true;
    await store.saveNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已恢复到所选版本'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(writingStoreProvider(widget.chapterId));
    // 捕获 store 引用，供 dispose 中使用
    _store = ref.read(writingStoreProvider(widget.chapterId).notifier);

    // 监听状态变化以同步 controller
    ref.listen<WritingState>(writingStoreProvider(widget.chapterId), (
      previous,
      next,
    ) {
      if (_controller.text.isEmpty && next.localContent.isNotEmpty) {
        _syncEditorText(next.localContent);
      }
      // 批次60：保存失败 → SnackBar 温和提示（防刷屏标志，成功自动复位）
      // 批次91-1：保存改由 scheduleSave 异步触发，失败检测移到状态监听处
      if (previous?.saveError == null && next.saveError != null) {
        if (!_saveErrorShown) {
          _saveErrorShown = true;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('刚才的内容没能保存成功，请稍后重试')));
        }
      } else if (next.saveError == null) {
        _saveErrorShown = false;
      }
      // 批次 36：章节标题同步到标题输入框（仅非用户输入时；用户输入时
      // state.chapter.title 同步为输入值 == controller.text，天然跳过）
      final nextTitle = next.chapter?.title;
      if (nextTitle != null && _titleController.text != nextTitle) {
        _titleController.text = nextTitle;
      }
      // 批次96-9：行段聚焦开关状态同步到控制器（排版设置里切换 → 淡化渲染即时生效）
      if (previous?.focusMode != next.focusMode) {
        _controller.focusMode = next.focusMode;
      }
      // 批次96-11：跨章全文搜索定位——内容就绪后一次性定位到命中处
      // （initialCursorOffset 来自路由 extra，搜索 sheet 点击跨章结果时携带）
      if (widget.initialCursorOffset != null &&
          !_searchCursorLocated &&
          _controller.text.isNotEmpty) {
        _searchCursorLocated = true;
        _locateCursor(widget.initialCursorOffset!);
      }
      // 草稿恢复弹窗（仅一次）：打开章节检测到较新草稿 → 询问是否恢复
      // 对齐 RN chapter-editor.tsx#L128-L133 Alert
      if (!_draftDialogShown &&
          next.hasDraft &&
          !next.isLoading &&
          next.chapter != null) {
        _draftDialogShown = true;
        _showDraftRestoreDialog(next);
      }
    });

    final showFab =
        !state.isLoading &&
        state.error == null &&
        !state.isAiPanelOpen &&
        state.fabVisible;

    return Scaffold(
      key: _scaffoldKey,
      // 批次 X-037-P0-1 H4/C1：正文壳与当前预设配平，暗夜用 editorDarkSurface 令牌（WCAG AA 可达）
      backgroundColor: isDarkEditorPreset(state.editorBackground)
          ? AppColors.editorDarkSurface
          : AppColors.background,
      // 批次83：章节树抽屉（每次打开以新 key 重建 → 列表/标题保持最新）
      drawer: ChapterTreeDrawer(
        key: ValueKey('chapter-tree-$_treeOpenCount'),
        currentChapterId: widget.chapterId,
        manuscriptId: _resolvedManuscriptId,
        onJumpToChapter: _handleJumpToChapter,
        onCreateChapter: _handleCreateChapter,
      ),
      onDrawerChanged: (isOpened) {
        if (!isOpened) return;
        // 打开时重建抽屉 + 失效章节列表缓存（编辑器改标题后抽屉能读到最新）
        setState(() => _treeOpenCount++);
        final msId = _resolvedManuscriptId;
        if (msId != null) ref.invalidate(chapterListProvider(msId));
      },
      // 批次83：大纲边写边看（右侧抽屉；每次打开重建 + 失效缓存）
      endDrawer: OutlineDrawer(
        key: ValueKey('outline-$_outlineOpenCount'),
        manuscriptId: _resolvedManuscriptId,
        onClose: _handleCloseOutline,
      ),
      onEndDrawerChanged: (isOpened) {
        if (!isOpened) return;
        setState(() => _outlineOpenCount++);
        final msId = _resolvedManuscriptId;
        if (msId != null) ref.invalidate(outlineViewProvider(msId));
      },
      appBar: _buildAppBar(state),
      // 批次88-2：对话按钮从 Scaffold FAB 改为 body Stack 内可拖动浮层
      // （长按拖动换位 + 松手持久化；⋮ 菜单可隐藏/显示，隐藏后菜单找回）
      body: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          return Stack(
            children: [
              Positioned.fill(
                child: state.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : state.error != null
                    ? _buildErrorView(state)
                    // 批次82 P0-④：面板不再以 bottomSheet 半屏覆盖正文；
                    // 改为右侧可收起侧栏（Row 并排），正文永远可见可编辑
                    : _buildEditorWithPanel(state),
              ),
              if (showFab)
                Positioned(
                  left: _fabOffset?.dx ?? (area.width - _fabSize - 16),
                  top: _fabOffset?.dy ?? (area.height - _fabSize - 16),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (details) {
                      _fabDragStart =
                          _fabOffset ??
                          Offset(
                            area.width - _fabSize - 16,
                            area.height - _fabSize - 16,
                          );
                      _fabDragStartGlobal = details.globalPosition;
                    },
                    onLongPressMoveUpdate: (details) {
                      // 用全局位移差值：FAB 移动会带动 GestureDetector，
                      // 局部坐标会漂移，全局坐标稳定
                      setState(() {
                        _fabOffset = Offset(
                          (_fabDragStart.dx +
                                  details.globalPosition.dx -
                                  _fabDragStartGlobal.dx)
                              .clamp(0.0, area.width - _fabSize),
                          (_fabDragStart.dy +
                                  details.globalPosition.dy -
                                  _fabDragStartGlobal.dy)
                              .clamp(0.0, area.height - _fabSize),
                        );
                      });
                    },
                    onLongPressEnd: (_) {
                      final pos = _fabOffset;
                      if (pos != null) {
                        AppStateRepository(
                          ref.read(appDatabaseProvider),
                        ).setFabPosition(pos);
                      }
                    },
                    child: FloatingActionButton(
                      key: const Key('aiChatFab'),
                      backgroundColor: AppColors.primary,
                      // 点击 = 切换教练面板（与长按拖动互不冲突）
                      onPressed: () {
                        ref
                            .read(
                              writingStoreProvider(widget.chapterId).notifier,
                            )
                            .toggleAiPanel();
                      },
                      child: Icon(
                        state.isAiPanelOpen
                            ? Icons.close
                            : Icons.chat_bubble_outline,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 批次82 P0-④：正文 + 右侧可收起教练侧栏（并排，正文不被覆盖）
  /// 批次95-2：窄屏（<600dp）改为底部抽屉式覆盖（纯纯侧栏划开非常驻），
  /// 避免 280px 侧栏在手机窄屏挤压正文；宽屏维持 Row 并排
  Widget _buildEditorWithPanel(WritingState state) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    if (!isNarrow) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildEditor(state)),
          if (state.isAiPanelOpen)
            SizedBox(width: _panelWidth(), child: _buildAiPanel(context)),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: _buildEditor(state)),
        if (state.isAiPanelOpen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.sizeOf(context).height * 0.75,
            child: Material(
              color: AppColors.background,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildAiPanel(context),
            ),
          ),
      ],
    );
  }

  /// 侧栏宽度：屏宽 55%，下限 280（手机窄屏仍可容纳对话），上限 480（平板）
  double _panelWidth() {
    final w = MediaQuery.sizeOf(context).width;
    return (w * 0.55).clamp(280.0, 480.0).toDouble();
  }

  /// B7 撤销（对齐 RN useUndoRedo.undo）：回退到上一个提交点并同步 controller
  void _handleUndo() {
    final store = ref.read(writingStoreProvider(widget.chapterId).notifier);
    store.undo();
    _syncEditorText(store.currentContent);
    _dirty = true;
  }

  /// B7 重做（对齐 RN useUndoRedo.redo）
  void _handleRedo() {
    final store = ref.read(writingStoreProvider(widget.chapterId).notifier);
    store.redo();
    _syncEditorText(store.currentContent);
    _dirty = true;
  }

  PreferredSizeWidget _buildAppBar(WritingState state) {
    // 批次 X-037-P0-1 C1：暗夜色走 AppColors.editorDark* 令牌（消除 3 处硬编码 + muted 对比度 2.85→4.56 AA）
    final darkUi = isDarkEditorPreset(state.editorBackground);
    final barBg = darkUi ? AppColors.editorDarkSurface : AppColors.background;
    final fg = darkUi ? AppColors.editorDarkText : AppColors.textPrimary;
    final muted = darkUi ? AppColors.editorDarkMuted : AppColors.textSecondary;
    return AppBar(
      backgroundColor: barBg,
      elevation: 0,
      toolbarHeight: 48,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: fg),
        onPressed: _handleBack,
      ),
      // 批次95-4：写作页面包屑（卷名·章名，笔落面包屑；标题大区块仍在正文上方）
      title: _buildBreadcrumb(state, fg),
      // 批次88-1：标题移出 AppBar，改为正文上方独立大号标题行（_buildEditor）
      bottom: _buildGoalProgressBar(state, darkUi: darkUi),
      actions: [
        // 批次96-10：撤销/重做入口收敛——AppBar 不再放撤销/重做，
        // 标点栏最前两位常驻兜底（批次91-3，操作项不参与 visibleIds 配置，永不可隐藏）
        // 批次82：字数显示 + 写作目标（点击设置目标）
        _buildWordCountIndicator(state, mutedColor: muted),
        // 批次96-8：一键排版（原「记灵感」位置，参考百灵布局；按排版开关批量应用段落格式）
        IconButton(
          icon: Icon(Icons.format_align_left, size: 20, color: fg),
          tooltip: '一键排版',
          onPressed: _handleFormatChapter,
        ),
        IconButton(
          icon: Icon(Icons.more_vert, color: fg),
          onPressed: () async {
            // E3：移除「开发中」占位菜单项，菜单只保留真实功能（保存状态 + 打开教练面板）
            // 批次79 B：菜单「诊断本章」改名「打开教练面板」——原行为仅展开面板不诊断，
            // 真正整章诊断在面板内同名按钮，改名如实反映行为
            // 批次96-7：拖拽调整篇幅——打开前读取用户记忆的高度占比，松手后落库
            final menuRepo = AppStateRepository(ref.read(appDatabaseProvider));
            final menuHeight = await menuRepo.getEditorMenuHeight();
            if (!mounted) return;
            WritingMenuSheet.show(
              context,
              lastSavedAt: state.lastSavedAt,
              initialHeight: menuHeight,
              onHeightChanged: (h) => menuRepo.setEditorMenuHeight(h),
              onDiagnose: () {
                ref
                    .read(writingStoreProvider(widget.chapterId).notifier)
                    .toggleAiPanel();
              },
              // 批次83：章节树抽屉入口（卷-章列表 + 快速跳转 + 新建章）
              onOpenChapterTree: _handleOpenChapterTree,
              // 批次83：大纲边写边看入口（右侧抽屉）
              onOpenOutline: _handleOpenOutline,
              // 批次96-11：全文搜索入口（整本作品章节搜索 + 跳转定位）
              onOpenFullTextSearch: _handleOpenFullTextSearch,
              // 批次84-2：全文查找替换入口
              onOpenFindReplace: _handleOpenFindReplace,
              // 批次86-1：回收板入口（删除/剪切长文本找回）
              onOpenRecycleBin: _handleOpenRecycleBin,
              // 批次85-3：快捷短语入口（常用语管理 + 光标插入）
              onOpenQuickPhrases: _handleOpenQuickPhrases,
              // 批次85-4：当前文风展示入口（风格画像五维）
              onOpenStyleProfile: _handleOpenStyleProfile,
              // 批次85-5：写作统计入口（近 14 天写作曲线）
              onOpenWritingStats: _handleOpenWritingStats,
              // 批次96-9：三个开关（行段聚焦/智能标点/对话按钮）已移入排版设置，
              // 菜单不再携带开关参数
              // 批次82：排版设置入口（字号/行距/背景 + 三开关，用户级持久化）
              onOpenSettings: () {
                EditorSettingsSheet.show(
                  context,
                  chapterId: widget.chapterId,
                  // 批次88-2：对话按钮位置恢复入口
                  onResetFabPosition: _resetFabPosition,
                  // 批次88-4：段落格式批量应用（按开关状态）
                  onApplyParagraphFormat: _handleApplyParagraphFormat,
                );
              },
              // 批次82：版本时光机入口（每 200 字快照，查看/恢复）
              // 批次84-3：传入当前内容 → 详情差异对比基准
              onOpenVersions: () {
                VersionTimeMachineSheet.show(
                  context,
                  chapterId: widget.chapterId,
                  currentContent: _controller.text,
                  onRestore: _handleRestoreVersion,
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// 批次95-4：写作页面包屑（「卷名 · 章名」；未分卷/加载中/无卷时仅章名）
  Widget _buildBreadcrumb(WritingState state, Color fg) {
    final chapter = state.chapter;
    final chapterTitle = (chapter?.title ?? widget.chapterTitle ?? '').trim();
    final fallback = chapterTitle.isEmpty ? '未命名章节' : chapterTitle;
    final volumeId = chapter?.volumeId;
    final msId = _resolvedManuscriptId;
    if (volumeId == null || msId == null) {
      return Text(
        fallback,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      );
    }
    final volumes = ref.watch(volumeListProvider(msId));
    return volumes.when(
      data: (list) {
        String? volName;
        for (final v in list) {
          if (v.id == volumeId) {
            volName = v.title;
            break;
          }
        }
        final text = (volName?.trim().isNotEmpty == true)
            ? '$volName · $fallback'
            : fallback;
        return Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
          overflow: TextOverflow.ellipsis,
        );
      },
      loading: () => Text(
        fallback,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg),
        overflow: TextOverflow.ellipsis,
      ),
      error: (_, _) => Text(
        fallback,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 批次82 P0-④：划词浮动菜单项（icon + 文字，点击执行动作）
  Widget _buildSelectionMenuItem({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        // X-039-Batch1：12→md / 8→sm
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(WritingState state) {
    return Center(
      child: Padding(
        // X-039-Batch1：32→xxl
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                ref
                    .read(writingStoreProvider(widget.chapterId).notifier)
                    .loadChapter();
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(WritingState state) {
    // 批次82 P0-④：面板改为右侧侧栏，正文不被覆盖 → 标点栏不再随面板隐藏
    // 批次90：标题/正文完全独立（用户参考图要求：标题独立大区块 + 正文分开）
    final titleColor = editorTextColorFor(state.editorBackground);
    final dividerColor = (titleColor == AppColors.textPrimary)
        ? AppColors.divider
        : AppColors.textTertiary.withValues(alpha: 0.25);

    return Column(
      children: [
        _buildOfflineBanner(state),
        Expanded(
          // 编辑器整体容器：背景色铺满
          child: Container(
            key: const Key('editorContainer'),
            color: editorBackgroundColorFor(state.editorBackground),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ────────── 标题独立大块（批次90：大字号、独占空间、可聚焦光标）──────────
                Padding(
                  // X-039-Batch1：20→section / 28（非标准= section+sm / 16→lg）— 28 为标题专属垂直大间距，保留字面（无法映射），后续如需令牌化单独补 largeV=28
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.section, AppSpacing.section + AppSpacing.sm, AppSpacing.section, AppSpacing.lg),
                  child: TextField(
                    key: const Key('chapterTitleField'),
                    controller: _titleController,
                    // 输入即保存（对齐 RN handleTitleChange）
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.25,
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: '未命名章节',
                      hintStyle: TextStyle(
                        fontSize: 28,
                        height: 1.25,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    // 批次95-3：键盘「下一项」→ 聚焦正文（标配）
                    onSubmitted: (_) => _focusNode.requestFocus(),
                    maxLines: 1,
                    onChanged: _onTitleChanged,
                  ),
                ),
                // 标题/正文分隔线（竹青细描边）
                Padding(
                  // X-039-Batch1：20→section
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.section),
                  child: Divider(
                    height: 1,
                    thickness: 0.6,
                    color: dividerColor,
                  ),
                ),
                // ────────── 正文独立大块 ──────────
                Expanded(
                  child: Padding(
                    // X-039-Batch1：20→section / 16→lg
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.section, AppSpacing.lg, AppSpacing.section, AppSpacing.lg),
                    child: Stack(
                      key: _editorStackKey, // 批次95-1：划词菜单位置反查用
                      children: [
                        TextField(
                          key: const Key('chapterContentField'),
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: null,
                          // 批次85-6：智能标点（左配对符自动补右符 + 右符前输入自动跳过）
                          // 批次88-4：段落格式（回车自动补缩进 / 段间空行，随排版设置开关）
                          inputFormatters: [
                            if (state.smartPunctOn)
                              const SmartPunctuationFormatter(),
                            ParagraphFormatFormatter(
                              indentOn: state.indentParagraph,
                              blankLineOn: state.blankLineBetween,
                            ),
                          ],
                          style: TextStyle(
                            fontSize: state.fontSize,
                            height: state.lineSpacing,
                            color: titleColor,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: '请输入正文内容',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: state.fontSize,
                              height: state.lineSpacing,
                            ),
                            border: InputBorder.none,
                          ),
                          onChanged: _onContentChanged,
                        ),
                        // B3 划词诊断：浮动菜单（批次82 P0-④ 扩展为 诊断/改写/续写 三动作）
                        // 批次95-1：菜单跟随选区（RenderEditable 定位 + 屏幕外翻转）
                        if (_showSelectionMenu &&
                            _selectedText.isNotEmpty &&
                            _selectionMenuPos != null)
                          Positioned(
                            left: _selectionMenuPos!.dx,
                            top: _selectionMenuPos!.dy,
                            child: Material(
                              color: AppColors.surfaceWhite,
                              elevation: 2,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSelectionMenuItem(
                                    label: '诊断这段文字',
                                    icon: Icons.search,
                                    onTap: _handleDiagnoseSelection,
                                  ),
                                  const Divider(height: 1),
                                  _buildSelectionMenuItem(
                                    label: '改写这段',
                                    icon: Icons.brush_outlined,
                                    onTap: _handleRewriteSelection,
                                  ),
                                  const Divider(height: 1),
                                  _buildSelectionMenuItem(
                                    label: '续写这段',
                                    icon: Icons.play_arrow_outlined,
                                    onTap: _handleContinueSelection,
                                  ),
                                  const Divider(height: 1),
                                  _buildSelectionMenuItem(
                                    label: '扩写这段',
                                    icon: Icons.unfold_more_outlined,
                                    onTap: _handleExpandSelection,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildSaveStatusBar(state),
        PunctuationBar(
          visibleIds: _punctBarIds,
          // 批次88-5：自定义标点项
          customItems: _punctCustomItems,
          // 批次91-3：标点栏最前两位常驻撤销/重做（与 AppBar 按钮同源）
          onUndo: _handleUndo,
          onRedo: _handleRedo,
          // 批次 X-037-P0-1 C1/H4：标点栏暗夜联动走 AppColors 令牌（消除 3 处硬编码；actionColor 用 editorDarkMuted 4.56:1 达 AA）
          backgroundColor: isDarkEditorPreset(state.editorBackground)
              ? AppColors.editorDarkPanel
              : null,
          itemColor: isDarkEditorPreset(state.editorBackground)
              ? AppColors.editorDarkText
              : null,
          actionColor: isDarkEditorPreset(state.editorBackground)
              ? AppColors.editorDarkMuted
              : null,
          onTap: (char) {
            final text = _controller.text;
            final sel = _controller.selection;
            // 批次91-4：无效选区防御（ed-p2-3）——无效/空选区时在末尾插入，
            // 避免 replaceRange(-1, -1) 触发 RangeError
            final start = sel.isValid ? sel.start : text.length;
            final end = sel.isValid ? sel.end : start;
            final newText = text.replaceRange(start, end, char);
            _controller.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: start + char.length),
            );
            _onContentChanged(newText);
          },
        ),
      ],
    );
  }

  Widget _buildAiPanel(BuildContext context) {
    final state = ref.read(writingStoreProvider(widget.chapterId));
    // 批次6（6.9 C2）：挂 ValueKey(chapterId) 强制章节切换时重建 Panel State，
    // 防滚动位置/选区/草稿跨章节泄漏
    return WritingCoachPanel(
      key: ValueKey(widget.chapterId),
      chapterId: widget.chapterId,
      manuscriptId: widget.manuscriptId ?? '',
      chapterTitle: state.chapter?.title ?? widget.chapterTitle ?? '',
      // B3 划词诊断：注入选中文本（面板打开后自动触发选段诊断）
      pendingDiagnoseText: _pendingDiagnoseText,
      onClose: () {
        ref
            .read(writingStoreProvider(widget.chapterId).notifier)
            .toggleAiPanel();
      },
      onAdopt: (suggestion) {
        // 批次5（5.1）：采纳动作收敛单一 service（suggestion_adoption_service）
        adoptSuggestionToChapter(
          context,
          chapterId: widget.chapterId,
          suggestion: suggestion,
          onAdopted: () async {
            // 采纳/撤销后刷新 store + 同步编辑器
            await ref
                .read(writingStoreProvider(widget.chapterId).notifier)
                .loadChapter();
            if (!mounted) return;
            final newContent = ref
                .read(writingStoreProvider(widget.chapterId))
                .localContent;
            if (_controller.text != newContent) {
              _syncEditorText(newContent);
            }
            _dirty = false;
          },
        );
      },
    );
  }
}

/// 批次82：写作目标设置对话框
