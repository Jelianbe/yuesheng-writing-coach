// ─────────────────────────────────────────────────────────────
// BookshelfPage — 书架页（宿主）
// 复刻 yuesheng-android/src/app/(tabs)/bookshelf.tsx
//
// 核心职责：
//   1. 展示 active 状态的作品列表
//   2. 新建作品（标题 + 简介 + 类型）
//   3. 点击卡片进入作品详情（批次 B 实现）
//
// R-019 真分解：本文件仅保留宿主 State。原 3 个 part/extension
// （bookshelf_create / bookshelf_actions / bookshelf_filter，共 13 个动作
// 方法）→ 3 个控制器 + BookshelfPageHost 接口；原 9 个内嵌私有 Widget
// → 8 个公有独立文件（详见 bookshelf_page_host.dart）。
//
// 视觉规范（月色竹青主题，对齐 C1 WritingPage 基线）：
//   - AppBar：浅色 #F7F8F6 + 深字 #2D3142 + 48dp 极简高度
//   - Scaffold 背景：冷青灰白 #F7F8F6
//   - 卡片：灰白底 #F2F4F2 + 圆角 12 + 左侧 4dp 竹青边框
//   - 作品图标色块：统一竹青 #2D5A52（不再轮换）
//   - 空状态：灰色图标 + 引导文案 + CTA 按钮
//   - 新建弹窗：居中 Modal + 圆角 16 + 竹青主按钮
//   - FAB 已移除（百灵极简：仅 AppBar + 按钮入口）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../providers/manuscript_providers.dart';
import 'bookshelf_actions_controller.dart';
import 'bookshelf_create_controller.dart';
import 'bookshelf_empty_state.dart';
import 'bookshelf_error_view.dart';
import 'bookshelf_filter_controller.dart';
import 'bookshelf_loading_view.dart';
import 'bookshelf_manuscript_list.dart';
import 'bookshelf_no_search_result.dart';
import 'bookshelf_page_host.dart';
import 'bookshelf_sort_mode.dart';

/// 书架页
class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage>
    implements BookshelfPageHost {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _genreController = TextEditingController();

  /// 批次93-2：搜索关键字（AppBar 搜索框，标题模糊匹配）
  String _query = '';
  bool _searchMode = false;

  /// 批次93-2：排序模式（默认最近更新）
  BookshelfSortMode _sortMode = BookshelfSortMode.recent;

  // ── R-019 真分解：动作控制器（经 BookshelfPageHost 注入）──
  late final BookshelfCreateController _create = BookshelfCreateController(
    this,
  );
  late final BookshelfActionsController _actions = BookshelfActionsController(
    this,
  );
  late final BookshelfFilterController _filter = BookshelfFilterController(
    this,
  );

  // ── BookshelfPageHost 实现 ──
  @override
  TextEditingController get titleController => _titleController;

  @override
  TextEditingController get descController => _descController;

  @override
  TextEditingController get genreController => _genreController;

  @override
  String get query => _query;

  @override
  BookshelfSortMode get sortMode => _sortMode;

  @override
  void setQuery(String value) => setState(() => _query = value);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(manuscriptStoreProvider.notifier).loadManuscripts();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  /// 批次93-3/93-6：书架统一刷新——失效章节统计缓存 + 重载作品列表
  /// （章节数/总字数来自 manuscriptStatsProvider，缓存不失效则卡片信息陈旧）
  @override
  void refreshBookshelf() {
    final store = ref.read(manuscriptStoreProvider);
    debugPrint(
      '[Bookshelf] _refreshBookshelf: books=${store.manuscripts.length}',
    );
    // B27：章节统计改为单一批量 provider，随 manuscriptStoreProvider 自动重算
    ref.invalidate(allManuscriptStatsProvider);
    ref.read(manuscriptStoreProvider.notifier).loadManuscripts();
  }

  @override
  Widget build(BuildContext context) {
    // 批次93-3：详情页/写作页返回前 +1 信号 → 刷新书架（go_router shell 结构下
    // RouteAware/routerDelegate 事件不可靠，用显式信号）
    ref.listen<int>(bookshelfRefreshSignalProvider, (previous, next) {
      if (previous != next) refreshBookshelf();
    });
    final state = ref.watch(manuscriptStoreProvider);
    final visible = _filter.applyFilterAndSort(state.manuscripts);
    // B27：一次性批量加载全部作品章节统计（N+1 → 单条 GROUP BY 查询）
    final statsMap = ref.watch(allManuscriptStatsProvider).value ?? {};
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _buildBody(state, visible, statsMap, searching),
      // FAB 已移除：百灵极简，仅 AppBar + 按钮入口
      bottomNavigationBar: null, // 由 _AppShell 管理
    );
  }

  /// AppBar：搜索态标题 / 搜索入口 / 排序菜单 / 新建入口
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: _searchMode ? _filter.buildSearchField() : const Text('书架'),
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      toolbarHeight: 48,
      elevation: 0,
      leading: _searchMode ? _buildSearchLeading() : null,
      actions: [
        // 批次93-2：搜索入口（AppBar 图标 → 变搜索框）
        if (!_searchMode) _buildSearchAction(),
        // 批次93-2：排序菜单（笔落 v2.1.10 手机端排序切换）
        _buildSortMenu(),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: _create.openCreateModal,
          tooltip: '新建作品',
        ),
      ],
    );
  }

  /// 搜索模式：返回图标退出搜索
  Widget _buildSearchLeading() {
    return IconButton(
      icon: const Icon(Icons.arrow_back, size: 22),
      onPressed: () {
        setState(() {
          _searchMode = false;
          _query = '';
        });
      },
    );
  }

  Widget _buildSearchAction() {
    return IconButton(
      icon: const Icon(Icons.search, size: 22),
      onPressed: () => setState(() => _searchMode = true),
      tooltip: '搜索',
    );
  }

  /// 排序菜单
  Widget _buildSortMenu() {
    return PopupMenuButton<BookshelfSortMode>(
      icon: const Icon(Icons.sort, size: 22),
      tooltip: '排序',
      initialValue: _sortMode,
      onSelected: _handleSortSelected,
      itemBuilder: (context) => [
        for (final mode in BookshelfSortMode.values) _buildSortMenuItem(mode),
      ],
    );
  }

  PopupMenuItem<BookshelfSortMode> _buildSortMenuItem(BookshelfSortMode mode) {
    return PopupMenuItem<BookshelfSortMode>(
      value: mode,
      child: Row(
        children: [
          if (mode == _sortMode) ...[
            const Icon(Icons.check, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
          ] else
            const SizedBox(width: 22),
          Text(mode.label),
        ],
      ),
    );
  }

  void _handleSortSelected(BookshelfSortMode mode) {
    if (mode == _sortMode) return;
    setState(() => _sortMode = mode);
    // 决策（第二轮调研 A.1）：排序与分卷独立——卷始终显示，
    // 切换排序时提示（不学纯纯「分卷仅在手动排序启用」的坑）
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已按「${mode.label}」排序（卷分组不受排序影响）'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// 主体：加载中 / 错误 / 下拉刷新（空态 / 无结果 / 作品列表）
  Widget _buildBody(
    ManuscriptState state,
    List<Manuscript> visible,
    Map<String, ManuscriptStats> statsMap,
    bool searching,
  ) {
    if (state.isLoading) return const BookshelfLoadingView();
    if (state.error != null) {
      // 批次93-3：错误态（重试按钮）
      return BookshelfErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(manuscriptStoreProvider.notifier).loadManuscripts(),
      );
    }
    return RefreshIndicator(
      // 批次93-6：下拉刷新（章节统计缓存一并失效）
      onRefresh: () async => refreshBookshelf(),
      color: AppColors.primary,
      child: state.manuscripts.isEmpty
          ? BookshelfEmptyState(onCreate: _create.openCreateModal)
          : visible.isEmpty
          ? BookshelfNoSearchResult(query: _query, searching: searching)
          : BookshelfManuscriptList(
              manuscripts: visible,
              statsMap: statsMap,
              onTap: _actions.handleManuscriptTap,
              onLongPress: _actions.handleManuscriptLongPress,
            ),
    );
  }
}
