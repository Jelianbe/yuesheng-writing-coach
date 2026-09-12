// ─────────────────────────────────────────────────────────────
// manuscript_detail_view — 作品详情页 UI 装配视图
//
// 从 manuscript_detail_page.dart 真分解而来（R-019：State 本体超限，
// 将 UI 装配从 State 抽为独立无状态 View，State 只留生命周期/数据加载）。
//
// 数据与回调全部经构造注入；本类不直接访问 provider。
//   - build            页面骨架（AppBar / 加载态 / 错误态 / 内容）
//   - _buildAppBar     AppBar（返回 + 新建卷 + 更多）
//   - _buildTabBar     三 Tab（章节 / 文件 / 相关对话）
//   - _buildTabBarView TabBarView
//   - _buildChaptersTab 章节 Tab（加载 / 空态 / 卷分组列表）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import 'file_section.dart';
import 'manuscript_detail_chapter_list.dart';
import 'manuscript_detail_chapter_list_header.dart';
import 'manuscript_detail_states.dart';
import 'related_sessions_tab.dart';

/// 作品详情页装配视图（无状态）
class ManuscriptDetailView extends StatelessWidget {
  final Manuscript? manuscript;
  final bool isLoaded;
  final int tabIndex;
  final TabController tabController;
  final List<Chapter> chapters;
  final List<Volume> volumes;
  final bool chaptersLoading;
  final Set<String> collapsedVolumes;
  final String appBarTitle;

  final VoidCallback onBack;
  final VoidCallback onCreateVolume;
  final VoidCallback onMoreMenu;
  final VoidCallback onImport;
  final ValueChanged<Chapter> onChapterTap;
  final ValueChanged<Chapter> onChapterLongPress;
  final ValueChanged<Chapter> onRenameChapter;
  final ValueChanged<String?> onQuickCreateChapter;
  final ValueChanged<String> onToggleVolume;
  final ValueChanged<Volume> onVolumeLongPress;
  final ValueChanged<Volume> onRenameVolume;
  final ValueChanged<String> onOpenSession;

  const ManuscriptDetailView({
    super.key,
    required this.manuscript,
    required this.isLoaded,
    required this.tabIndex,
    required this.tabController,
    required this.chapters,
    required this.volumes,
    required this.chaptersLoading,
    required this.collapsedVolumes,
    required this.appBarTitle,
    required this.onBack,
    required this.onCreateVolume,
    required this.onMoreMenu,
    required this.onImport,
    required this.onChapterTap,
    required this.onChapterLongPress,
    required this.onRenameChapter,
    required this.onQuickCreateChapter,
    required this.onToggleVolume,
    required this.onVolumeLongPress,
    required this.onRenameVolume,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    final ms = manuscript;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(appBarTitle),
      body: SafeArea(
        // P3-3：加载中显示 LoadingView，作品不存在显示错误视图，否则正常布局
        child: !isLoaded
            ? const ManuscriptLoadingView()
            : ms == null
            ? const ManuscriptNotFoundView()
            : Column(
                children: [
                  // 作品元信息条（批次 37：只保留体裁单行）
                  ManuscriptMetaBar(
                    manuscript: ms,
                    chapterCount: chapters.length,
                  ),
                  // 批次 28：三 Tab（章节 / 文件 / 相关对话）
                  _buildTabBar(),
                  Expanded(child: _buildTabBarView(ms)),
                ],
              ),
      ),
    );
  }

  /// AppBar：返回书架 + 新建卷（仅章节 Tab）+ 更多。
  PreferredSizeWidget _buildAppBar(String appBarTitle) {
    return AppBar(
      title: Text(appBarTitle),
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      toolbarHeight: 48,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, size: 22),
        onPressed: onBack,
        tooltip: '返回书架',
      ),
      actions: [
        // 批次96-3：右上角「+」= 新建卷（详情页唯一入口，列表级「新建章节」另在列表内）
        if (tabIndex == 0)
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: onCreateVolume,
            tooltip: '新建卷',
          ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: onMoreMenu,
          tooltip: '更多',
        ),
      ],
    );
  }

  /// 三 Tab 栏（章节 / 文件 / 相关对话）。
  Widget _buildTabBar() {
    return TabBar(
      controller: tabController,
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 14),
      tabs: const [
        Tab(text: '章节'),
        Tab(text: '文件'),
        Tab(text: '相关对话'),
      ],
    );
  }

  /// TabBarView：章节 / 文件 / 相关对话。
  Widget _buildTabBarView(Manuscript ms) {
    return TabBarView(
      controller: tabController,
      children: [
        // ── Tab0 章节 ──
        _buildChaptersTab(),
        // ── Tab1 文件（批次 28：从章节列表尾部独立成 Tab）──
        FileSection(manuscriptId: ms.id, manuscriptTitle: ms.title),
        // ── Tab2 相关对话（批次 28：按活跃度排序；批次 30：点击跳转打开会话）──
        RelatedSessionsTab(manuscriptId: ms.id, onOpenSession: onOpenSession),
      ],
    );
  }

  /// 章节 Tab：加载 / 空态（章卷皆空）/ 卷分组列表。
  Widget _buildChaptersTab() {
    // 空态判据必须是「章与卷皆空」：只按 chapters 判会让零章节
    // 作品新建的卷被章节空态吞掉，必须再建一章才可见。
    if (chaptersLoading) return const ManuscriptLoadingView();
    if (chapters.isEmpty && volumes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        children: [
          ChapterListHeader(onImport: onImport, chapterCount: 0),
          SizedBox(
            height: 260,
            child: EmptyChaptersState(
              // 批次96-3：空态 CTA 直接创建「第一章」，无弹窗
              onCreate: () => onQuickCreateChapter(null),
            ),
          ),
        ],
      );
    }
    return ChapterList(
      chapters: chapters,
      volumes: volumes,
      onTap: onChapterTap,
      onLongPress: onChapterLongPress,
      onImport: onImport,
      chapterCount: chapters.length,
      onRenameChapter: onRenameChapter,
      onQuickCreateChapter: onQuickCreateChapter,
      // 批次92-1/92-4/92-5：卷分组 + 折叠 + 吸顶 + 卷操作
      collapsedVolumes: collapsedVolumes,
      onToggleVolume: onToggleVolume,
      onVolumeLongPress: onVolumeLongPress,
      onRenameVolume: onRenameVolume,
    );
  }
}
