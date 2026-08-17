// ─────────────────────────────────────────────────────────────
// BookshelfPage — 书架页
// 复刻 yuesheng-android/src/app/(tabs)/bookshelf.tsx
//
// 核心职责：
//   1. 展示 active 状态的作品列表
//   2. 新建作品（标题 + 简介 + 类型）
//   3. 点击卡片进入作品详情（批次 B 实现）
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
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../providers/app_providers.dart';
import '../providers/manuscript_providers.dart';
import '../services/work_import_service.dart';
import 'book_import_sheet.dart';

part 'bookshelf_create.dart';
part 'bookshelf_actions.dart';
part 'bookshelf_filter.dart';

/// 批次93-2：书架排序模式（笔落 v2.1.10 手机端书籍列表排序切换）
enum _SortMode {
  recent('最近更新'),
  created('创建时间'),
  title('书名'),
  manual('手动');

  final String label;
  const _SortMode(this.label);
}

/// 批次93-1：体裁 → 首字封面底色（全部收敛到月色竹青既有令牌）
Color _genreColor(String genre) {
  switch (genre.trim()) {
    case '奇幻':
      return AppColors.primary;
    case '都市':
      return AppColors.textDeep;
    case '言情':
      return AppColors.warning;
    case '科幻':
      return AppColors.success;
    case '武侠':
      return AppColors.l2Text;
    case '悬疑':
      return AppColors.l3Text;
    case '历史':
      return AppColors.primaryDeep;
    default:
      return AppColors.textTertiary;
  }
}

/// 批次93-1：相对时间（刚刚/N分钟前/N小时前/N天前/N周前/MM/dd）
String _relativeTime(int ts) {
  final now = DateTime.now();
  final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
  if (diff.inDays < 1) return '${diff.inHours}小时前';
  if (diff.inDays < 7) return '${diff.inDays}天前';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
  return '${dt.month}/${dt.day}';
}

/// 书架页

class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _genreController = TextEditingController();

  /// 批次93-2：搜索关键字（AppBar 搜索框，标题模糊匹配）
  String _query = '';
  bool _searchMode = false;

  /// 批次93-2：排序模式（默认最近更新）
  _SortMode _sortMode = _SortMode.recent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(manuscriptStoreProvider.notifier).loadManuscripts();
    });
  }

  /// 批次93-3/93-6：书架统一刷新——失效章节统计缓存 + 重载作品列表
  /// （章节数/总字数来自 manuscriptStatsProvider，缓存不失效则卡片信息陈旧）
  void _refreshBookshelf() {
    final store = ref.read(manuscriptStoreProvider);
    debugPrint('[Bookshelf] _refreshBookshelf: books=${store.manuscripts.length}');
    // B27：章节统计改为单一批量 provider，随 manuscriptStoreProvider 自动重算
    ref.invalidate(allManuscriptStatsProvider);
    ref.read(manuscriptStoreProvider.notifier).loadManuscripts();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _genreController.dispose();
    super.dispose();
  }













  @override
  Widget build(BuildContext context) {
    // 批次93-3：详情页/写作页返回前 +1 信号 → 刷新书架（go_router shell 结构下
    // RouteAware/routerDelegate 事件不可靠，用显式信号）
    ref.listen<int>(bookshelfRefreshSignalProvider, (previous, next) {
      if (previous != next) _refreshBookshelf();
    });
    final state = ref.watch(manuscriptStoreProvider);
    final visible = _applyFilterAndSort(state.manuscripts);
    // B27：一次性批量加载全部作品章节统计（N+1 → 单条 GROUP BY 查询）
    final statsMap = ref.watch(allManuscriptStatsProvider).value ?? {};
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _searchMode ? _buildSearchField() : const Text('书架'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: _searchMode
            // 搜索模式：返回图标退出搜索
            ? IconButton(
                icon: const Icon(Icons.arrow_back, size: 22),
                onPressed: () {
                  setState(() {
                    _searchMode = false;
                    _query = '';
                  });
                },
              )
            : null,
        actions: [
          // 批次93-2：搜索入口（AppBar 图标 → 变搜索框）
          if (!_searchMode)
            IconButton(
              icon: const Icon(Icons.search, size: 22),
              onPressed: () => setState(() => _searchMode = true),
              tooltip: '搜索',
            ),
          // 批次93-2：排序菜单（笔落 v2.1.10 手机端排序切换）
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort, size: 22),
            tooltip: '排序',
            initialValue: _sortMode,
            onSelected: (mode) {
              if (mode == _sortMode) return;
              setState(() => _sortMode = mode);
              // 决策（第二轮调研 A.1）：排序与分卷独立——卷始终显示，
              // 切换排序时提示（不学纯纯「分卷仅在手动排序启用」的坑）
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('已按「${mode.label}」排序（卷分组不受排序影响）'),
                  duration: const Duration(seconds: 2),
                ));
            },
            itemBuilder: (context) => [
              for (final mode in _SortMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Row(
                    children: [
                      if (mode == _sortMode) ...[
                        const Icon(
                          Icons.check,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                      ] else
                        const SizedBox(width: 22),
                      Text(mode.label),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openCreateModal,
            tooltip: '新建作品',
          ),
        ],
      ),
      body: state.isLoading
          ? const _LoadingView()
          : state.error != null
          // 批次93-3：错误态（重试按钮）
          ? _ErrorView(
              message: state.error!,
              onRetry: () =>
                  ref.read(manuscriptStoreProvider.notifier).loadManuscripts(),
            )
          : RefreshIndicator(
              // 批次93-6：下拉刷新（章节统计缓存一并失效）
              onRefresh: () async => _refreshBookshelf(),
              color: AppColors.primary,
              child: state.manuscripts.isEmpty
                  ? _EmptyState(onCreate: _openCreateModal)
                  : visible.isEmpty
                  ? _NoSearchResult(query: _query, searching: searching)
                  : _ManuscriptList(
                      manuscripts: visible,
                      statsMap: statsMap,
                      onTap: _handleManuscriptTap,
                      onLongPress: _handleManuscriptLongPress,
                    ),
            ),
      // FAB 已移除：百灵极简，仅 AppBar + 按钮入口
      bottomNavigationBar: null, // 由 _AppShell 管理
    );
  }

}

/// 加载中视图
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}

/// 空状态视图（批次93-6：包在可滚动容器内，支持 RefreshIndicator 下拉刷新）
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.library_books,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '还没有作品',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '点击「新建」创建你的第一部作品',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onCreate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('新建作品'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 批次93-3：加载失败错误态（重试按钮）
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.danger,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 批次93-2：搜索无结果空态
class _NoSearchResult extends StatelessWidget {
  final String query;
  final bool searching;

  const _NoSearchResult({required this.query, required this.searching});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(
          Icons.search_off,
          size: 48,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            '没有找到相关作品',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            searching ? '换个书名试试吧' : '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 批次93-7：长按操作菜单项
class _LongPressAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color labelColor;
  final VoidCallback onTap;

  const _LongPressAction({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 作品列表（批次93-2：接收排序后的列表；章节统计由父级一次性批量加载后传入）
class _ManuscriptList extends StatelessWidget {
  final List<Manuscript> manuscripts;
  final Map<String, ManuscriptStats> statsMap;
  final void Function(Manuscript) onTap;
  final void Function(Manuscript) onLongPress;

  const _ManuscriptList({
    required this.manuscripts,
    required this.statsMap,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: manuscripts.length,
      itemBuilder: (context, index) {
        final ms = manuscripts[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ManuscriptCard(
            manuscript: ms,
            stats: statsMap[ms.id],
            onTap: () => onTap(ms),
            onLongPress: () => onLongPress(ms),
          ),
        );
      },
    );
  }
}

/// 作品卡片（批次93-1 信息加厚：首字封面 + 章节数 + 总字数 + 相对时间 + 简介预览）
class _ManuscriptCard extends ConsumerWidget {
  final Manuscript manuscript;
  final ManuscriptStats? stats;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ManuscriptCard({
    required this.manuscript,
    this.stats,
    required this.onTap,
    required this.onLongPress,
  });

  String _formatWords(int n) {
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(1)}万字';
    } else if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}千字';
    }
    return '$n字';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 批次93-1（B27）：章节统计由父级批量加载后传入，避免逐卡片 N+1 查询
    final chapterCount = stats?.chapterCount ?? 0;
    final totalWords = stats?.totalWords ?? 0;

    final title = manuscript.title.isEmpty ? '未命名作品' : manuscript.title;
    // 首字封面（取书名首汉字；空标题用「未」）
    final firstChar = manuscript.title.isEmpty ? '未' : manuscript.title[0];
    final genre = manuscript.genre.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧 4dp 竹青色条（月色竹青主色锚点）
                  Container(width: 4, color: AppColors.primary),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 首字封面（体裁色 + ClipRRect + 书名首汉字，48px）
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _genreColor(genre),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              firstChar,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (manuscript.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  // 简介预览两行
                                  Text(
                                    manuscript.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                // 信息行：章节数 · 总字数 + 相对时间
                                Row(
                                  children: [
                                    if (genre.isNotEmpty) ...[
                                      Text(
                                        genre,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textDeep,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      '$chapterCount 章 · ${_formatWords(totalWords)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _relativeTime(manuscript.updatedAt),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 新建作品弹窗
class _CreateManuscriptModal extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController descController;
  final TextEditingController genreController;
  final VoidCallback onCancel;
  final Future<void> Function() onCreate;

  /// 批次 35：文本导入入口（关闭表单 → 打开导入弹层）
  final VoidCallback onImportTap;

  const _CreateManuscriptModal({
    required this.titleController,
    required this.descController,
    required this.genreController,
    required this.onCancel,
    required this.onCreate,
    required this.onImportTap,
  });

  @override
  State<_CreateManuscriptModal> createState() => _CreateManuscriptModalState();
}

class _CreateManuscriptModalState extends State<_CreateManuscriptModal> {
  bool _isLoading = false;

  /// 批次93-5：体裁 Chip 预设（番茄作家助手模型）
  static const List<String> _genrePresets = [
    '奇幻',
    '都市',
    '言情',
    '科幻',
    '武侠',
    '悬疑',
    '历史',
    '其他',
  ];

  /// 当前选中的体裁 Chip（空 = 未选）
  String _genre = '';

  /// 是否展开自定义体裁输入（选中「其他」时）
  bool _customGenre = false;

  Future<void> _handleCreate() async {
    if (_isLoading) return; // P1-1 防连点
    setState(() => _isLoading = true);
    try {
      await widget.onCreate();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 批次93-5：体裁 Chip 选择 → 写入 genreController（onCreate 读取）
  void _selectGenre(String preset) {
    setState(() {
      _genre = preset;
      _customGenre = preset == '其他';
      if (!_customGenre) {
        widget.genreController.text = preset;
      } else {
        // 自定义：清空等待输入（未输入时回退「其他」）
        widget.genreController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '新建作品',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '标题',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textBody,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: widget.titleController,
                  autofocus: true,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    hintText: '输入作品标题',
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '简介（可选）',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textBody,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: widget.descController,
                  maxLines: 3,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    hintText: '一句话介绍你的作品',
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '类型（可选）',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textBody,
                  ),
                ),
                const SizedBox(height: 8),
                // 批次93-5：体裁改 ChoiceChip 预设（奇幻/都市/言情/…/其他 + 自定义展开）
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in _genrePresets)
                      ChoiceChip(
                        key: ValueKey('genre-chip-$preset'),
                        label: Text(preset),
                        selected: _genre == preset,
                        selectedColor: AppColors.primarySoft,
                        labelStyle: TextStyle(
                          fontSize: 13,
                          color: _genre == preset
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: _genre == preset
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          side: BorderSide(
                            color: _genre == preset
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        onSelected: _isLoading
                            ? null
                            : (_) => _selectGenre(preset),
                      ),
                  ],
                ),
                // 选中「其他」→ 展开自定义体裁输入
                if (_customGenre) ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('custom-genre-field'),
                    controller: widget.genreController,
                    enabled: !_isLoading,
                    onChanged: (v) {
                      // 输入非空时用输入值，留空回退「其他」
                      if (v.trim().isNotEmpty) _genre = v.trim();
                    },
                    decoration: InputDecoration(
                      hintText: '输入自定义类型',
                      hintStyle: const TextStyle(color: AppColors.textTertiary),
                      filled: true,
                      fillColor: AppColors.background,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _isLoading ? null : widget.onCancel,
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleCreate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: AppColors.onPrimary,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '创建',
                                style: TextStyle(
                                  color: AppColors.onPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                // 批次 35：文本导入入口（对齐 RN WorkImportModal 选文件分支）
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _isLoading ? null : widget.onImportTap,
                  icon: const Icon(
                    Icons.file_open_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    '从 TXT 文件导入书籍',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
