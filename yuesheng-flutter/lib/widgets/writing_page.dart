// ─────────────────────────────────────────────────────────────
// WritingPage — 写作页
// 4 层结构（百灵极简 + 月色竹青配色）：AppBar(48dp) / Editor（米纸底）/
// PunctuationBar(36dp) / FAB（AI 面板关闭时） / bottomSheet（面板打开时）。
//
// 自动保存：onChanged → updateContent + saveNow（批次31）；dispose 强制 saveNow。
//
// C92-6a：视图层提取为独立类（view/）。C92-6b：伪拆分清偿——删除 4 条 `part`
// 声明，逻辑真分解为 7 个独立控制器（controllers/，见 [WritingPageHost] 与
// `WritingPageControllers`），组装层移入 `view/writing_page_scaffold.dart`
// 与 `view/writing_page_menu_actions.dart`。本文件只保留宿主 State 字段与生命周期、
// Host 接口实现、`build` 入口，以及被测试单测引用的纯函数 `extractRemovedText`。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/writing_providers.dart';
import 'editing/focus_aware_editing_controller.dart';
import 'punctuation_bar.dart';
import 'writing/controllers/writing_page_controllers.dart';
import 'writing/view/writing_page_scaffold.dart';
import 'writing/writing_page_host.dart';

// 批次86-1 回收板纯函数（C92-6b 提取至 utils；此处 export 保持既有可见性，
// 含 `test/widgets/writing_page_test.dart` 的单测直接引用）
export '../utils/deleted_text_extractor.dart' show extractRemovedText;

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

class _WritingPageState extends ConsumerState<WritingPage>
    implements WritingPageHost {
  late final FocusAwareEditingController _controller;
  late final FocusNode _focusNode;

  /// 批次 36：章节标题输入（AppBar 内可编辑，输入即保存）
  late final TextEditingController _titleController;
  bool _dirty = false;

  /// 批次60：保存失败 SnackBar 已提示标志（避免连续失败刷屏）
  bool _saveErrorShown = false;
  // 在 build 中捕获，用于 dispose 时调用 saveNow（dispose 时 ref 已失效）
  WritingStore? _store;
  // 草稿恢复弹窗只弹一次
  bool _draftDialogShown = false;
  // B3 划词诊断：当前选中文本 + 浮动菜单可见性 + 待注入面板的选段
  String _selectedText = '';
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

  /// 批次86-2：标点栏可见项 id 顺序（null = 默认全部，用户级持久化）
  List<String>? _punctBarIds;

  /// 批次88-5：标点栏自定义项（用户在排版设置增删，用户级持久化）
  List<PunctuationItem> _punctCustomItems = const [];

  /// 批次88-2：对话按钮拖动后的位置（null = 右下角默认；持久化 `fab_position`）
  Offset? _fabOffset;

  // 批次83：章节树抽屉——Scaffold key（⋮ 菜单点击后打开抽屉）+ 打开计数
  // （每次打开以新 ValueKey 重建抽屉 → 列表数据/标题保持最新）
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _treeOpenCount = 0;

  // 批次83：大纲抽屉（endDrawer）——打开计数（每次打开重建 + 失效缓存）
  int _outlineOpenCount = 0;

  // ── 控制器聚合（C92-6b：原 part/extension 与宿主逻辑的真分解产物）────────
  late final WritingPageControllers _controllers = WritingPageControllers(this);

  /// 批次83：解析所属作品 ID（优先路由参数，其次已加载章节反查；
  /// 深链进入时 manuscriptId 可能为空，章节加载完成后必有 manuscriptId）
  @override
  String? get resolvedManuscriptId {
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
    _controller.addListener(_controllers.selectionAi.onSelectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(writingStoreProvider(widget.chapterId).notifier).loadChapter();
    });
    // 批次86-2：加载标点栏可见配置（用户级持久化）
    _controllers.document.loadPunctuationConfig();
    // 批次88-2：加载对话按钮位置（可见性开关已随排版设置移入 store，loadChapter 加载）
    _controllers.fab.loadFabPosition();
    // 对齐 RN useNetInfo：网络状态变化 → 写入 store（离线草稿/恢复同步）
    _controllers.storeSync.bindConnectivity();
  }

  @override
  void dispose() {
    _controllers.storeSync.disposeConnectivity();
    // 批次91-1：有未保存改动或未决合并保存 → 离开时强制保存（fire-and-forget）
    _controllers.storeSync.forceSaveOnDispose();
    _controller.dispose();
    _focusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(writingStoreProvider(widget.chapterId));
    // 捕获 store 引用，供 dispose 中使用
    _store = ref.read(writingStoreProvider(widget.chapterId).notifier);
    _controllers.storeSync.bindStoreListener();
    return WritingPageScaffold(
      host: this,
      controllers: _controllers,
      state: state,
    );
  }

  // ── WritingPageHost 实现 ────────────────────────────────────────────────
  // context / mounted / ref 由 State 基类直接满足。

  @override
  void hostSetState(VoidCallback fn) => setState(fn);

  @override
  String get chapterId => widget.chapterId;
  @override
  String? get widgetManuscriptId => widget.manuscriptId;
  @override
  String? get widgetChapterTitle => widget.chapterTitle;
  @override
  int? get initialCursorOffset => widget.initialCursorOffset;
  @override
  void Function(String chapterId, String chapterTitle)?
  get onJumpToChapterCallback => widget.onJumpToChapter;
  @override
  VoidCallback? get onBackCallback => widget.onBack;

  @override
  FocusAwareEditingController get editorController => _controller;
  @override
  TextEditingController get titleController => _titleController;
  @override
  FocusNode get focusNode => _focusNode;
  @override
  GlobalKey get editorStackKey => _editorStackKey;
  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;
  @override
  WritingStore? get store => _store;
  @override
  void setStore(WritingStore store) => _store = store;

  @override
  bool get dirty => _dirty;
  @override
  set dirty(bool value) => _dirty = value;
  @override
  bool get suppressSelectionMenu => _suppressSelectionMenu;
  @override
  set suppressSelectionMenu(bool value) => _suppressSelectionMenu = value;
  @override
  String get selectedText => _selectedText;
  @override
  set selectedText(String value) => _selectedText = value;
  @override
  bool get showSelectionMenu => _showSelectionMenu;
  @override
  set showSelectionMenu(bool value) => _showSelectionMenu = value;
  @override
  Offset? get selectionMenuPos => _selectionMenuPos;
  @override
  set selectionMenuPos(Offset? value) => _selectionMenuPos = value;
  @override
  String? get pendingDiagnoseText => _pendingDiagnoseText;
  @override
  set pendingDiagnoseText(String? value) => _pendingDiagnoseText = value;
  @override
  String? get lastEditorText => _lastEditorText;
  @override
  set lastEditorText(String? value) => _lastEditorText = value;
  @override
  bool get goalCelebrated => _goalCelebrated;
  @override
  set goalCelebrated(bool value) => _goalCelebrated = value;
  @override
  Offset? get fabOffset => _fabOffset;
  @override
  set fabOffset(Offset? value) => _fabOffset = value;
  @override
  int get treeOpenCount => _treeOpenCount;
  @override
  set treeOpenCount(int value) => _treeOpenCount = value;
  @override
  int get outlineOpenCount => _outlineOpenCount;
  @override
  set outlineOpenCount(int value) => _outlineOpenCount = value;
  @override
  bool get searchCursorLocated => _searchCursorLocated;
  @override
  set searchCursorLocated(bool value) => _searchCursorLocated = value;
  @override
  bool get draftDialogShown => _draftDialogShown;
  @override
  set draftDialogShown(bool value) => _draftDialogShown = value;
  @override
  bool get saveErrorShown => _saveErrorShown;
  @override
  set saveErrorShown(bool value) => _saveErrorShown = value;

  @override
  List<String>? get punctBarIds => _punctBarIds;
  @override
  List<PunctuationItem> get punctCustomItems => _punctCustomItems;

  @override
  void setPunctuationConfig({
    required List<String>? ids,
    required List<PunctuationItem> items,
  }) {
    setState(() {
      _punctBarIds = ids;
      _punctCustomItems = items;
    });
  }

  @override
  void locateCursor(int offset) {
    if (offset < 0 || offset > _controller.text.length) return;
    _suppressSelectionMenu = true;
    _controller.selection = TextSelection.collapsed(offset: offset);
    _suppressSelectionMenu = false;
  }

  @override
  void onContentChanged(String content) =>
      _controllers.document.onContentChanged(content);
}
