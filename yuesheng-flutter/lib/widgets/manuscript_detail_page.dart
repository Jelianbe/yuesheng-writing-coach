// ─────────────────────────────────────────────────────────────
// ManuscriptDetailPage — 作品详情页
// 复刻 yuesheng-android/src/app/(tabs)/bookshelf/[id].tsx
//
// 核心职责：
//   1. 展示作品元信息（标题、简介、类型、字数统计）
//   2. 展示章节列表（按 sort_order 排序）
//   3. 新建章节（标题 + 可选内容）
//   4. 点击章节进入写作页（批次 C 实现，先占位）
//
// 视觉规范（月色竹青主题，对齐 C1 WritingPage 基线）：
//   - AppBar：浅色 #F7F8F6 + 深字 #2D3142 + 48dp 极简高度
//   - Scaffold 背景：冷青灰白 #F7F8F6
//   - 顶部作品信息卡：#F7F8F6 + 左侧 4dp 竹青色条 + 浅灰边框
//   - 信息胶囊：浅竹青 #E8F0EE + 竹青字 #2D5A52
//   - 章节卡片：白底 + 圆角 12 + 浅灰边框（无阴影，百灵扁平风）
//   - 章节序号色块：统一竹青 #2D5A52（不再 4 色轮换）
//   - 章节状态标签：矿物色（草稿 #E0E4E0/#5B7565 / 修改中 #FFF4E5/#B45309 / 完成 #E8F0EE/#2D5A52）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/volume_repository.dart';
import '../providers/chapter_providers.dart';
import '../providers/chat_store.dart';
import '../providers/manuscript_providers.dart';
import '../providers/app_providers.dart';
import '../router/app_routes.dart';
import '../services/export_service.dart';
import '../utils/chapter_title.dart';
import '../utils/volume_group.dart';
import 'file_section.dart';
import 'related_sessions_tab.dart';


part 'manuscript_detail_export.dart';
part 'manuscript_detail_volume.dart';
part 'manuscript_detail_chapter.dart';
part 'manuscript_detail_nav.dart';


/// 章节状态 → 中文标签 + 矿物色配色
class _ChapterStatusConfig {
  final String label;
  final Color bgColor;
  final Color textColor;
  const _ChapterStatusConfig(this.label, this.bgColor, this.textColor);
}

const Map<String, _ChapterStatusConfig> _statusConfig = {
  'draft': _ChapterStatusConfig('草稿', AppColors.border, AppColors.textDeep),
  'revising': _ChapterStatusConfig(
    '修改中',
    AppColors.warningBg,
    AppColors.warning,
  ),
  'complete': _ChapterStatusConfig('完成', AppColors.l1, AppColors.primary),
};

/// 作品详情页路由参数
class ManuscriptDetailArgs {
  final String manuscriptId;
  final String? title;
  const ManuscriptDetailArgs({required this.manuscriptId, this.title});
}

/// 作品详情页
class ManuscriptDetailPage extends ConsumerStatefulWidget {
  final ManuscriptDetailArgs args;
  const ManuscriptDetailPage({super.key, required this.args});

  @override
  ConsumerState<ManuscriptDetailPage> createState() =>
      _ManuscriptDetailPageState();
}

class _ManuscriptDetailPageState extends ConsumerState<ManuscriptDetailPage>
    with SingleTickerProviderStateMixin {
  Manuscript? _manuscript;

  /// P3-3：区分「加载中」和「作品不存在」
  bool _isLoaded = false;

  /// 批次92-4：卷折叠状态（卷 id → 是否折叠；吸顶滚动时保留，不随列表重建）
  final Set<String> _collapsedVolumes = {};

  /// 批次28：详情页 Tab（0=章节 1=文件 2=相关对话）
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 批次 28：Tab 切换时重建 AppBar actions（新建章节按钮）与 FAB 的显示条件
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadManuscriptAndChapters();
    });
    // 批次96-2：恢复本作品已折叠的卷（app_state 持久化）
    _loadCollapsedVolumes();
  }

  /// 批次96-2：从 app_state 恢复作品卷折叠状态
  Future<void> _loadCollapsedVolumes() async {
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    final saved = await repo.getCollapsedVolumes(widget.args.manuscriptId);
    if (!mounted) return;
    setState(() {
      _collapsedVolumes
        ..clear()
        ..addAll(saved);
    });
  }

  /// 批次96-2：折叠状态变更 → 同步持久化（含未分卷组 key）
  Future<void> _toggleVolumeCollapsed(String key) async {
    setState(() {
      if (!_collapsedVolumes.add(key)) _collapsedVolumes.remove(key);
    });
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    await repo.setCollapsedVolumes(
      widget.args.manuscriptId,
      Set.of(_collapsedVolumes),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadManuscriptAndChapters() async {
    // 加载作品信息
    final manuscripts = ref.read(manuscriptStoreProvider).manuscripts;
    if (manuscripts.isNotEmpty) {
      // P2-8 修复：找不到时不再回退到 manuscripts.first（误导用户）
      try {
        final ms = manuscripts.firstWhere(
          (m) => m.id == widget.args.manuscriptId,
        );
        setState(() => _manuscript = ms);
      } catch (_) {
        // 找不到匹配的作品，_manuscript 保持 null
      }
    }
    // P3-3：标记加载完成，区分加载中和作品不存在
    if (mounted) setState(() => _isLoaded = true);
    // 加载章节
    ref
        .read(chapterStoreProvider(widget.args.manuscriptId).notifier)
        .loadChapters();
  }

  // ── 修复辅助：SnackBar 轻提示 ──
  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
  }

  /// 整书导出

  /// 单章导出

  /// 单卷导出

  // ── 批次92-2：卷重命名（详情页卷头铅笔 + 长按菜单）──

  // ── 批次92-2：长按卷头 → 卷操作弹层（重命名 / 删除）──

  /// 批次92-2：删除卷二次确认（批次96-4：卷内章节一并软删进回收站，不再散落）

  /// 批次96-1：移动到卷弹层（目标：全部卷 + 未分卷）
  /// 对齐章节树抽屉 `_showMoveToVolumeSheet`，但移动后落到目标卷末尾
  /// （跨卷归属调整语义直观）。

  // ── 修复3：重命名章节（铅笔图标 + 长按菜单均走这里）──

  /// 批次96-2：列表级「新建章节」快捷入口（卷内末尾/列表末尾）
  /// 就近归属：卷内入口 → 归属该卷；列表末尾 → 未分卷（散落）
  /// 自动命名「第X章」（复用 nextChapterTitle）
  /// 批次96-4：创建后不再跳写作页——只创建，列表即时可见（SnackBar 提示）

  /// 批次 34：详情页长按章节 → 操作菜单（重命名 / 删除）→ 二次确认 → 执行

  /// 批次94-2：删除章节 → 软删进回收站（可恢复，诊断历史保留）

  /// 章节列表「导入」→ 追加章节页（批次 20，对齐 RN ChapterSection 导入按钮）

  /// 更多菜单（批次 20，对齐 RN MoreMenuSheet）

  /// 删除项目：二次确认 → 软删除 → 回书架
  /// （批次59：确认文案对齐真实软删语义——archived 数据保留，与书架删除作品一致）

  @override
  Widget build(BuildContext context) {
    final chapterState = ref.watch(
      chapterStoreProvider(widget.args.manuscriptId),
    );
    final chapters = chapterState.chapters;
    final ms = _manuscript;
    // 批次92-1：详情页接入卷分组（读取作品卷列表，无卷走扁平列表）
    final volumesAsync = ref.watch(volumeListProvider(widget.args.manuscriptId));
    final volumes = volumesAsync.value ?? const <Volume>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(ms?.title ?? widget.args.title ?? '作品详情'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () {
            // 批次93-3：返回书架前发刷新信号（书架 listen 后失效章节统计缓存）
            ref.read(bookshelfRefreshSignalProvider.notifier).state++;
            context.canPop() ? context.pop() : context.go('/bookshelf');
          },
          tooltip: '返回书架',
        ),
        actions: [
          // 批次96-3：右上角「+」= 新建卷（详情页唯一入口，列表级「新建章节」另在列表内）
          if (_tabController.index == 0)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _handleCreateVolume,
              tooltip: '新建卷',
            ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _openMoreMenu,
            tooltip: '更多',
          ),
        ],
      ),
      body: SafeArea(
        // P3-3：加载中显示 LoadingView，作品不存在显示错误视图，否则正常布局
        child: !_isLoaded
            ? const _LoadingView()
            : ms == null
            ? const _ManuscriptNotFoundView()
            : Column(
                children: [
                  // 作品元信息条（批次 37：简化对齐 RN ManuscriptHeader subtitle，
                  // 去掉大信息卡/简介/字数胶囊，只保留「体裁 · N 个章节」单行）
                  _ManuscriptMetaBar(
                    manuscript: ms,
                    chapterCount: chapters.length,
                  ),
                  // 批次 28：三 Tab（章节 / 文件 / 相关对话）
                  TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    tabs: const [
                      Tab(text: '章节'),
                      Tab(text: '文件'),
                      Tab(text: '相关对话'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // ── Tab0 章节 ──
                        chapterState.isLoading
                            ? const _LoadingView()
                            : chapters.isEmpty
                            ? ListView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                children: [
                                  _ChapterListHeader(
                                    onImport: _openAppendChapters,
                                    chapterCount: 0,
                                  ),
                                  SizedBox(
                                    height: 260,
                                    child: _EmptyChaptersState(
                                      // 批次96-3：空态 CTA 直接创建「第一章」，无弹窗
                                      onCreate: () =>
                                          _handleQuickCreateChapter(null),
                                    ),
                                  ),
                                ],
                              )
                            : _ChapterList(
                                chapters: chapters,
                                volumes: volumes,
                                onTap: _handleChapterTap,
                                onLongPress: _handleChapterLongPress,
                                onImport: _openAppendChapters,
                                chapterCount: chapters.length,
                                onRenameChapter: _handleRenameChapter,
                                onQuickCreateChapter:
                                    _handleQuickCreateChapter,
                                // 批次92-1/92-4/92-5：卷分组 + 折叠 + 吸顶 + 卷操作
                                collapsedVolumes: _collapsedVolumes,
                                onToggleVolume: _toggleVolumeCollapsed,
                                onVolumeLongPress: _showVolumeActions,
                                onRenameVolume: _handleRenameVolume,
                              ),
                        // ── Tab1 文件（批次 28：从章节列表尾部独立成 Tab）──
                        FileSection(
                          manuscriptId: ms.id,
                          manuscriptTitle: ms.title,
                        ),
                        // ── Tab2 相关对话（批次 28：按活跃度排序；批次 30：点击跳转打开会话）──
                        RelatedSessionsTab(
                          manuscriptId: ms.id,
                          onOpenSession: _handleOpenRelatedSession,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 作品元信息条（批次 37 简化 + 修复2：章节数已移到列表头右侧）
///
/// 只保留体裁（纯文字无章节数），大幅压缩顶部占位。
class _ManuscriptMetaBar extends StatelessWidget {
  final Manuscript manuscript;
  final int chapterCount;
  const _ManuscriptMetaBar({
    required this.manuscript,
    required this.chapterCount,
  });

  @override
  Widget build(BuildContext context) {
    final genre = manuscript.genre.trim();
    if (genre.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          const Icon(
            Icons.menu_book_outlined,
            size: 14,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              genre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
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

/// 作品不存在视图（P3-3：作品被删除或 ID 无效时显示）
class _ManuscriptNotFoundView extends StatelessWidget {
  const _ManuscriptNotFoundView();

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
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              '作品不存在或已删除',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '可能已被删除，请返回书架查看',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go('/bookshelf'),
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
              child: const Text('返回书架'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 章节空状态
class _EmptyChaptersState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyChaptersState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.description_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              '还没有章节',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击「新建章节」开始你的第一篇',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
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
              child: const Text('新建章节'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 章节列表（批次92-1/92-4/92-5：CustomScrollView + 卷分组 + 卷头吸顶）
///
/// - 无卷（volumes 为空）→ 扁平章节列表（批次83 原行为，兼容既有测试）
/// - 有卷 → 按 buildChapterSections 渲染（批次96-4）：
///   散落章节直接平铺（无组头），卷组按全局序自然穿插；
///   卷头为 SliverPersistentHeader(pinned) 吸顶（纯纯 v27.12.7 + 笔落 v2.1.3），
///   整行可点折叠（accordion 教训：48px 高触摸目标），折叠态由父 State 持有
///   （吸顶滚动时保留，不随列表重建）
class _ChapterList extends StatelessWidget {
  final List<Chapter> chapters;
  final List<Volume> volumes;
  final void Function(Chapter) onTap;

  /// 批次 34：长按章节 → 操作菜单（重命名/删除）
  final void Function(Chapter) onLongPress;

  /// 「导入」按钮
  final VoidCallback onImport;

  /// 章节数（显示在列表头右侧，修复2）
  final int chapterCount;

  /// 修复3：重命名单章（铅笔图标点击）
  final void Function(Chapter) onRenameChapter;

  /// 批次96-2：列表级「新建章节」快捷入口（卷内末尾/列表末尾，就近归属）
  final void Function(String? volumeId) onQuickCreateChapter;

  // ── 批次92：卷分组相关 ──
  /// 已折叠的卷 id
  final Set<String> collapsedVolumes;
  final void Function(String key) onToggleVolume;
  final void Function(Volume) onVolumeLongPress;
  final void Function(Volume) onRenameVolume;

  const _ChapterList({
    required this.chapters,
    required this.volumes,
    required this.onTap,
    required this.onLongPress,
    required this.onImport,
    required this.chapterCount,
    required this.onRenameChapter,
    required this.onQuickCreateChapter,
    required this.collapsedVolumes,
    required this.onToggleVolume,
    required this.onVolumeLongPress,
    required this.onRenameVolume,
  });

  Widget _buildChapterCard(Chapter chapter, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _ChapterCard(
        chapter: chapter,
        index: index,
        onTap: () => onTap(chapter),
        onLongPress: () => onLongPress(chapter),
        // 批次79 C：可见删除入口复用长按删除流程
        onDelete: () => onLongPress(chapter),
        // 修复3：铅笔图标 → 直接重命名
        onRename: () => onRenameChapter(chapter),
      ),
    );
  }

  Widget _chapterSliver(List<Chapter> list) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildChapterCard(list[index], index),
        childCount: list.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = _ChapterListHeader(
      onImport: onImport,
      chapterCount: chapterCount,
    );

    // 无卷 → 扁平章节列表（批次83 原行为）
    if (volumes.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            sliver: _chapterSliver(chapters),
          ),
          // 批次96-2：列表末尾「新建章节」入口（无卷 → 未分卷）
          SliverToBoxAdapter(
            child: _NewChapterRow(
              targetVolumeId: null,
              onTap: () => onQuickCreateChapter(null),
            ),
          ),
        ],
      );
    }

    // 有卷 → 按全局序渲染段（批次96-4：散落章节平铺无组头，卷组自然穿插）
    final sections = buildChapterSections(volumes, chapters);
    final slivers = <Widget>[SliverToBoxAdapter(child: header)];
    for (final sec in sections) {
      final loose = sec.looseChapter;
      if (loose != null) {
        // 散落章节：无卷头，直接平铺（不参与折叠）
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            sliver: SliverToBoxAdapter(child: _buildChapterCard(loose, 0)),
          ),
        );
        continue;
      }
      final group = VolumeGroup(volume: sec.volume, chapters: sec.chapters);
      final key = sec.volume!.id;
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _VolumeHeaderDelegate(
            group: group,
            collapsed: collapsedVolumes.contains(key),
            onToggle: () => onToggleVolume(key),
            onLongPress: () => onVolumeLongPress(sec.volume!),
            onRename: () => onRenameVolume(sec.volume!),
          ),
        ),
      );
      if (collapsedVolumes.contains(key)) continue;
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          sliver: sec.chapters.isEmpty
              ? const SliverToBoxAdapter(child: _DetailEmptyVolumeHint())
              : _chapterSliver(sec.chapters),
        ),
      );
      // 批次96-2：卷内末尾「新建章节」入口（就近归属该卷）
      slivers.add(
        SliverToBoxAdapter(
          child: _NewChapterRow(
            targetVolumeId: sec.volume!.id,
            onTap: () => onQuickCreateChapter(sec.volume!.id),
          ),
        ),
      );
    }
    // 批次96-4：列表末尾「新建章节」入口（归属散落，与无卷扁平列表一致）
    slivers.add(
      SliverToBoxAdapter(
        child: _NewChapterRow(
          targetVolumeId: null,
          onTap: () => onQuickCreateChapter(null),
        ),
      ),
    );
    return CustomScrollView(slivers: slivers);
  }
}

/// 批次96-2：列表级「新建章节」行（百灵「⊕ 新建章节」模型）
/// targetVolumeId = 归属卷；null = 未分卷（列表末尾）
class _NewChapterRow extends StatelessWidget {
  final String? targetVolumeId;
  final VoidCallback onTap;
  const _NewChapterRow({required this.targetVolumeId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        key: ValueKey(
          targetVolumeId == null
              ? 'new-chapter-row-unassigned'
              : 'new-chapter-row-$targetVolumeId',
        ),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 18,
                color: AppColors.textTertiary,
              ),
              SizedBox(width: 8),
              Text(
                '新建章节',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 吸顶卷头 delegate（批次92-5：SliverPersistentHeader pinned）
class _VolumeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final VolumeGroup group;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;

  _VolumeHeaderDelegate({
    required this.group,
    required this.collapsed,
    required this.onToggle,
    this.onLongPress,
    this.onRename,
  });

  /// 批次92-4：48px 高触摸目标（accordion 教训）
  static const double _height = 48;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _DetailVolumeHeader(
      volume: group.volume,
      count: group.chapters.length,
      totalWords: group.chapters.fold(0, (sum, c) => sum + c.wordCount),
      collapsed: collapsed,
      onToggle: onToggle,
      onLongPress: onLongPress,
      onRename: onRename,
    );
  }

  @override
  bool shouldRebuild(_VolumeHeaderDelegate old) {
    return old.group.volume?.id != group.volume?.id ||
        old.group.chapters.length != group.chapters.length ||
        old.collapsed != collapsed ||
        old.onToggle != onToggle ||
        old.onLongPress != onLongPress ||
        old.onRename != onRename;
  }
}

/// 详情页卷头（批次92-4 视觉加厚）：
/// 左侧色条 + 浅背景 + 卷名 + 卷总字数 + 章节数 + 铅笔重命名 + 折叠箭头
/// 整行可点击折叠（非小箭头），48px 高；吸顶背景不透明（内容不透出）
class _DetailVolumeHeader extends StatelessWidget {
  final Volume? volume;
  final int count;
  final int totalWords;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;

  const _DetailVolumeHeader({
    required this.volume,
    required this.count,
    required this.totalWords,
    required this.collapsed,
    required this.onToggle,
    this.onLongPress,
    this.onRename,
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
  Widget build(BuildContext context) {
    final isUnassigned = volume == null;
    final title = volume == null
        ? '未分卷'
        : (volume!.title.trim().isEmpty ? '未命名卷' : volume!.title.trim());
    return Material(
      color: AppColors.background,
      child: InkWell(
        onTap: onToggle,
        onLongPress: onLongPress,
        child: Container(
          height: _VolumeHeaderDelegate._height,
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border(
              bottom: BorderSide(color: AppColors.divider, width: 1),
            ),
          ),
          child: Row(
            children: [
              // 左侧 3dp 色条（卷 → 竹青；未分卷 → 弱化灰）
              Container(
                width: 3,
                color: isUnassigned
                    ? AppColors.placeholder
                    : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 18,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Icon(
                isUnassigned
                    ? Icons.notes_outlined
                    : Icons.collections_bookmark_outlined,
                size: 16,
                color: isUnassigned ? AppColors.textTertiary : AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textInk,
                  ),
                ),
              ),
              if (totalWords > 0) ...[
                Text(
                  _formatWords(totalWords),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '$count 章',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              if (onRename != null) ...[
                const SizedBox(width: 4),
                // 批次92-2：卷头铅笔图标 → 直接重命名
                InkWell(
                  onTap: onRename,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情页空卷占位（卷内无章节时显示在卷头下方）
class _DetailEmptyVolumeHint extends StatelessWidget {
  const _DetailEmptyVolumeHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Text(
        '暂无章节',
        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
      ),
    );
  }
}

/// 章节列表头：「章节列表 X 章」+ 新建卷 + 导入（修复2：章节数移到右侧区域）
class _ChapterListHeader extends StatelessWidget {
  final VoidCallback onImport;
  final int chapterCount;
  const _ChapterListHeader({
    required this.onImport,
    required this.chapterCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          const Text(
            '章节列表',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$chapterCount 章',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onImport,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Text(
                '导入',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 更多菜单 bottom sheet（批次 20，对齐 RN MoreMenuSheet）
class _MoreMenuSheet extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onExport;
  final VoidCallback onRecycleBin;
  final VoidCallback onDelete;

  const _MoreMenuSheet({
    required this.onOpenSettings,
    required this.onExport,
    required this.onRecycleBin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          12,
          AppSpacing.lg,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部把手
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 批次77：移除「导出项目」「分享」开发中死菜单项（对齐写作页 E3 清理，
            // 菜单只保留真实功能：项目设置 / 删除项目）
            _MenuActionItem(
              icon: Icons.settings_outlined,
              label: '项目设置',
              iconColor: AppColors.textPrimary,
              labelColor: AppColors.textPrimary,
              onTap: onOpenSettings,
            ),
            const Divider(height: 1, color: AppColors.divider),
            // 批次94-1：导出整书（批次77 曾移除的「导出项目」死菜单，现为真实功能）
            _MenuActionItem(
              icon: Icons.ios_share_outlined,
              label: '导出整书',
              iconColor: AppColors.primary,
              labelColor: AppColors.textPrimary,
              onTap: onExport,
            ),
            const Divider(height: 1, color: AppColors.divider),
            // 批次94-2：章节回收站（软删章节恢复/永久删除）
            _MenuActionItem(
              icon: Icons.delete_sweep_outlined,
              label: '回收站',
              iconColor: AppColors.textPrimary,
              labelColor: AppColors.textPrimary,
              onTap: onRecycleBin,
            ),
            const Divider(height: 1, color: AppColors.divider),
            _MenuActionItem(
              icon: Icons.delete_outline,
              label: '删除项目',
              iconColor: AppColors.danger,
              labelColor: AppColors.danger,
              onTap: onDelete,
            ),
            const SizedBox(height: 8),
            // 取消按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 菜单项（正常可点击）
class _MenuActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color labelColor;
  final VoidCallback onTap;

  const _MenuActionItem({
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

/// 章节卡片（修复1：移除序号色块，改为纯文字；修复3：行尾增加编辑图标用于重命名）
class _ChapterCard extends StatelessWidget {
  final Chapter chapter;
  final int index;
  final VoidCallback onTap;

  /// 长按 → 操作菜单（删除 / 重命名）
  final VoidCallback onLongPress;

  /// 行尾可见删除入口（对齐 file_section 批次75，复用长按删除流程）
  final VoidCallback onDelete;

  /// 修复3：行尾铅笔图标 → 直接重命名
  final VoidCallback onRename;
  const _ChapterCard({
    required this.chapter,
    required this.index,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onRename,
  });

  String _formatWords(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万字';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}千字';
    }
    return '$count字';
  }

  @override
  Widget build(BuildContext context) {
    final statusCfg = _statusConfig[chapter.status] ?? _statusConfig['draft']!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              // 章节信息（修复1：移除左侧序号色块，纯文字展示）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chapter.title.isEmpty ? '未命名章节' : chapter.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // 状态标签
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusCfg.bgColor,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            statusCfg.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: statusCfg.textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.sticky_note_2_outlined,
                          size: 12,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatWords(chapter.wordCount),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        if (chapter.lastDiagnosedAt != null) ...[
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.check_circle_outline,
                            size: 12,
                            color: AppColors.textDeep,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '已诊断',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDeep,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // 修复3：行尾铅笔图标（直接重命名章节名）
              IconButton(
                onPressed: onRename,
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                tooltip: '重命名章节',
                visualDensity: VisualDensity.compact,
              ),
              // 批次79 C：行尾可见删除入口
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.danger,
                ),
                tooltip: '删除章节',
                visualDensity: VisualDensity.compact,
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
