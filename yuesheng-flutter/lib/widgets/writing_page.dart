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
//
// C92-6a（2026-09-12）：视图层提取为独立类（view/ 目录），本文件保留
// State 骨架与组装。真拆 3 条 R-019 债务：build / _buildEditor / _buildAppBar。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderEditable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../config/shared_constants.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chapter_providers.dart';
import '../providers/manuscript_providers.dart';
import '../providers/writing_providers.dart';
import '../router/app_routes.dart';
import '../services/suggestion_adoption_service.dart';
import '../utils/chapter_title.dart';
import '../utils/paragraph_format.dart';
import 'character/character_page.dart';
import 'chapter_tree_drawer.dart';
import 'editing/focus_aware_editing_controller.dart';
import 'editor_settings_sheet.dart';
import '../config/editor_background_presets.dart';
import 'outline_drawer.dart';
import 'punctuation_bar.dart';
import 'quick_phrase_sheet.dart';
import 'recycle_bin_sheet.dart';
import 'search_replace_sheet.dart';
import 'style_profile_sheet.dart';
import 'version_time_machine_sheet.dart';
import 'writing/view/writing_editor_view.dart';
import 'writing/view/writing_page_app_bar.dart';
import 'writing/view/writing_page_breadcrumb.dart';
import 'writing/view/writing_page_chrome.dart';
import 'writing/view/writing_status_views.dart';
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
    // 批次96-4：标题即章节名——直写 repo 后刷新 store，抽屉/列表同步显示新名
    final msId = _resolvedManuscriptId;
    if (msId != null) {
      ref.read(chapterStoreProvider(msId).notifier).loadChapters();
    }
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

  /// C78 批次3：打开角色页（ADR-C78 §3.0：MaterialPageRoute 独立路由页，
  /// 不用 Sheet / 不复用面板槽位——isAiPanelOpen / toggleAiPanel 语义
  /// 已被 writing_providers_test.dart:85,173-200 锁死，本入口零接触）
  void _handleOpenCharacters() {
    final manuscriptId = _resolvedManuscriptId;
    if (manuscriptId == null || manuscriptId.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('章节加载中，请稍后再试')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CharacterPage(manuscriptId: manuscriptId),
      ),
    );
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
    _bindStoreListener();

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
      drawer: _buildChapterTreeDrawer(),
      onDrawerChanged: _handleDrawerChanged,
      // 批次83：大纲边写边看（右侧抽屉；每次打开重建 + 失效缓存）
      endDrawer: _buildOutlineDrawer(),
      onEndDrawerChanged: _handleEndDrawerChanged,
      appBar: _buildAppBar(state),
      // 批次88-2：对话按钮从 Scaffold FAB 改为 body Stack 内可拖动浮层
      // （长按拖动换位 + 松手持久化；⋮ 菜单可隐藏/显示，隐藏后菜单找回）
      body: _buildBody(state, showFab),
    );
  }

  /// ref.listen 挂载（监听状态变化以同步 controller / 提示保存失败 / 定位光标）
  void _bindStoreListener() {
    ref.listen<WritingState>(writingStoreProvider(widget.chapterId), (
      previous,
      next,
    ) {
      _syncEditorFromState(next);
      _handleSaveErrorTransition(previous, next);
      _syncTitleFromState(next);
      _syncFocusMode(previous, next);
      _maybeLocateSearchCursor();
      _maybeShowDraftRestore(next);
    });
  }

  /// 章节内容就绪 → 同步 controller（仅当 controller 尚空）
  void _syncEditorFromState(WritingState next) {
    if (_controller.text.isEmpty && next.localContent.isNotEmpty) {
      _syncEditorText(next.localContent);
    }
  }

  /// 批次60/91-1：保存失败 → SnackBar 温和提示（防刷屏标志，成功自动复位）
  void _handleSaveErrorTransition(WritingState? previous, WritingState next) {
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
  }

  /// 批次 36：章节标题同步到标题输入框（仅非用户输入时；用户输入时
  /// state.chapter.title 同步为输入值 == controller.text，天然跳过）
  void _syncTitleFromState(WritingState next) {
    final nextTitle = next.chapter?.title;
    if (nextTitle != null && _titleController.text != nextTitle) {
      _titleController.text = nextTitle;
    }
  }

  /// 批次96-9：行段聚焦开关状态同步到控制器（排版设置里切换 → 淡化渲染即时生效）
  void _syncFocusMode(WritingState? previous, WritingState next) {
    if (previous?.focusMode != next.focusMode) {
      _controller.focusMode = next.focusMode;
    }
  }

  /// 批次96-11：跨章全文搜索定位——内容就绪后一次性定位到命中处
  /// （initialCursorOffset 来自路由 extra，搜索 sheet 点击跨章结果时携带）
  void _maybeLocateSearchCursor() {
    if (widget.initialCursorOffset != null &&
        !_searchCursorLocated &&
        _controller.text.isNotEmpty) {
      _searchCursorLocated = true;
      _locateCursor(widget.initialCursorOffset!);
    }
  }

  /// 草稿恢复弹窗（仅一次）：打开章节检测到较新草稿 → 询问是否恢复
  /// 对齐 RN chapter-editor.tsx#L128-L133 Alert
  void _maybeShowDraftRestore(WritingState next) {
    if (!_draftDialogShown &&
        next.hasDraft &&
        !next.isLoading &&
        next.chapter != null) {
      _draftDialogShown = true;
      _showDraftRestoreDialog(next);
    }
  }

  /// 批次83：章节树抽屉（每次打开以新 key 重建 → 列表/标题保持最新）
  Widget _buildChapterTreeDrawer() {
    return ChapterTreeDrawer(
      key: ValueKey('chapter-tree-$_treeOpenCount'),
      currentChapterId: widget.chapterId,
      manuscriptId: _resolvedManuscriptId,
      onJumpToChapter: _handleJumpToChapter,
      onCreateChapter: _handleCreateChapter,
    );
  }

  void _handleDrawerChanged(bool isOpened) {
    if (!isOpened) return;
    // 打开时重建抽屉 + 刷新章节 store（编辑器改标题后抽屉能读到最新）
    setState(() => _treeOpenCount++);
    final msId = _resolvedManuscriptId;
    if (msId != null) {
      ref.read(chapterStoreProvider(msId).notifier).loadChapters();
    }
  }

  /// 批次83：大纲边写边看（右侧抽屉；每次打开重建 + 失效缓存）
  Widget _buildOutlineDrawer() {
    return OutlineDrawer(
      key: ValueKey('outline-$_outlineOpenCount'),
      manuscriptId: _resolvedManuscriptId,
      onClose: _handleCloseOutline,
    );
  }

  void _handleEndDrawerChanged(bool isOpened) {
    if (!isOpened) return;
    setState(() => _outlineOpenCount++);
    final msId = _resolvedManuscriptId;
    if (msId != null) ref.invalidate(outlineViewProvider(msId));
  }

  /// 正文区（三态：加载中 / 失败 / 编辑器+面板），对话按钮浮层叠加其上
  Widget _buildBody(WritingState state, bool showFab) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        return Stack(
          children: [
            Positioned.fill(child: _buildMainContent(state)),
            if (showFab) _buildDraggableFab(area, state),
          ],
        );
      },
    );
  }

  Widget _buildMainContent(WritingState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (state.error != null) {
      return WritingErrorView(
        message: state.error!,
        onRetry: () {
          ref
              .read(writingStoreProvider(widget.chapterId).notifier)
              .loadChapter();
        },
      );
    }
    // 批次82 P0-④：面板不再以 bottomSheet 半屏覆盖正文；
    // 改为右侧可收起侧栏（Row 并排），正文永远可见可编辑
    return _buildEditorWithPanel(state);
  }

  /// 批次88-2：对话按钮浮层（长按拖动 + 点击开合面板）
  Widget _buildDraggableFab(Size area, WritingState state) {
    return WritingDraggableFab(
      left: _fabOffset?.dx ?? (area.width - _fabSize - 16),
      top: _fabOffset?.dy ?? (area.height - _fabSize - 16),
      isPanelOpen: state.isAiPanelOpen,
      onDragStart: (globalPosition) =>
          _handleFabDragStart(globalPosition, area),
      onDragUpdate: (globalPosition) =>
          _handleFabDragUpdate(globalPosition, area),
      onDragEnd: _handleFabDragEnd,
      onPressed: _toggleAiPanel,
    );
  }

  void _handleFabDragStart(Offset globalPosition, Size area) {
    _fabDragStart =
        _fabOffset ??
        Offset(area.width - _fabSize - 16, area.height - _fabSize - 16);
    _fabDragStartGlobal = globalPosition;
  }

  void _handleFabDragUpdate(Offset globalPosition, Size area) {
    // 用全局位移差值：FAB 移动会带动 GestureDetector，
    // 局部坐标会漂移，全局坐标稳定
    setState(() {
      _fabOffset = Offset(
        (_fabDragStart.dx + globalPosition.dx - _fabDragStartGlobal.dx).clamp(
          0.0,
          area.width - _fabSize,
        ),
        (_fabDragStart.dy + globalPosition.dy - _fabDragStartGlobal.dy).clamp(
          0.0,
          area.height - _fabSize,
        ),
      );
    });
  }

  void _handleFabDragEnd() {
    final pos = _fabOffset;
    if (pos != null) {
      AppStateRepository(ref.read(appDatabaseProvider)).setFabPosition(pos);
    }
  }

  void _toggleAiPanel() {
    ref.read(writingStoreProvider(widget.chapterId).notifier).toggleAiPanel();
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

  /// 底部标点栏点击：按当前选区插入字符（批次91-4：无效选区防御）
  void _handlePunctuationTap(String char) {
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
  }

  /// 编辑器主体（视图层独立类：离线横幅 / 标题 / 正文 / 划词菜单 / 保存状态条 / 标点栏）
  Widget _buildEditor(WritingState state) {
    return WritingEditorView(
      state: state,
      titleController: _titleController,
      contentController: _controller,
      focusNode: _focusNode,
      editorStackKey: _editorStackKey,
      punctBarIds: _punctBarIds,
      punctCustomItems: _punctCustomItems,
      showSelectionMenu: _showSelectionMenu,
      selectionMenuPos: _selectionMenuPos,
      onTitleChanged: _onTitleChanged,
      onContentChanged: _onContentChanged,
      onDiagnoseSelection: _handleDiagnoseSelection,
      onUndo: _handleUndo,
      onRedo: _handleRedo,
      onPunctuationTap: _handlePunctuationTap,
    );
  }

  /// AppBar（视图层独立类：返回 / 面包屑 / 字数指示 / 一键排版 / ⋮ 菜单）
  PreferredSizeWidget _buildAppBar(WritingState state) {
    // 批次 X-037-P0-1 C1：暗夜色走 AppColors.editorDark* 令牌
    final darkUi = isDarkEditorPreset(state.editorBackground);
    final fg = darkUi ? AppColors.editorDarkText : AppColors.textPrimary;
    final muted = darkUi ? AppColors.editorDarkMuted : AppColors.textSecondary;
    return WritingPageAppBar(
      darkUi: darkUi,
      foregroundColor: fg,
      goalWords: state.goalWords,
      breadcrumb: WritingPageBreadcrumb(
        title: state.chapter?.title ?? widget.chapterTitle,
        volumeId: state.chapter?.volumeId,
        manuscriptId: _resolvedManuscriptId,
        color: fg,
      ),
      progressBar: WritingGoalProgressBar(
        goalWords: state.goalWords,
        wordCount: state.wordCount,
        darkUi: darkUi,
      ),
      wordCount: WritingWordCountIndicator(
        goalWords: state.goalWords,
        wordCount: state.wordCount,
        mutedColor: muted,
        onTap: _showGoalDialog,
      ),
      onBack: _handleBack,
      onFormatChapter: _handleFormatChapter,
      onOpenMenu: () => _showWritingMenu(state),
    );
  }

  /// ⋮ 菜单：读取用户记忆的篇幅占比 → 打开 WritingMenuSheet（各入口回调分发）
  Future<void> _showWritingMenu(WritingState state) async {
    // E3：移除「开发中」占位菜单项，菜单只保留真实功能（保存状态 + 打开教练面板）
    // 批次79 B：「诊断本章」改名「打开教练面板」——原行为仅展开面板不诊断
    // 批次96-7：拖拽调整篇幅——打开前读取用户记忆的高度占比，松手后落库
    final menuRepo = AppStateRepository(ref.read(appDatabaseProvider));
    final menuHeight = await menuRepo.getEditorMenuHeight();
    if (!mounted) return;
    WritingMenuSheet.show(
      context,
      lastSavedAt: state.lastSavedAt,
      initialHeight: menuHeight,
      onHeightChanged: (h) => menuRepo.setEditorMenuHeight(h),
      onDiagnose: _toggleAiPanel,
      // 批次83：章节树抽屉入口（卷-章列表 + 快速跳转 + 新建章）
      onOpenChapterTree: _handleOpenChapterTree,
      // 批次83：大纲边写边看入口（右侧抽屉）
      onOpenOutline: _handleOpenOutline,
      // C78 批次3：角色页入口（独立路由页）
      onOpenCharacters: _handleOpenCharacters,
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
      // 批次96-9：三个开关（行段聚焦/智能标点/对话按钮）已移入排版设置
      onOpenSettings: _showEditorSettings,
      onOpenVersions: _showVersionTimeMachine,
    );
  }

  /// 批次82：排版设置入口（字号/行距/背景 + 三开关，用户级持久化）
  void _showEditorSettings() {
    EditorSettingsSheet.show(
      context,
      chapterId: widget.chapterId,
      // 批次88-2：对话按钮位置恢复入口
      onResetFabPosition: _resetFabPosition,
      // 批次88-4：段落格式批量应用（按开关状态）
      onApplyParagraphFormat: _handleApplyParagraphFormat,
    );
  }

  /// 批次82：版本时光机入口（每 200 字快照，查看/恢复）
  /// 批次84-3：传入当前内容 → 详情差异对比基准
  void _showVersionTimeMachine() {
    VersionTimeMachineSheet.show(
      context,
      chapterId: widget.chapterId,
      currentContent: _controller.text,
      onRestore: _handleRestoreVersion,
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
      onClose: _toggleAiPanel,
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
