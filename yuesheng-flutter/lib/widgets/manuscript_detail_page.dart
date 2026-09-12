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
//   - 章节卡片：白底 + 圆角 12 + 浅灰边框（无阴影，百灵扁平风）
//   - 章节状态标签：矿物色（草稿 / 修改中 / 完成）
//
// 架构（R-019 复合形态真分解）：本文件仅保留页面宿主 [ManuscriptDetailPage]
// 与其 State（生命周期 + 数据加载 + 委托装配）。
//   - 13 个原私有 Widget → 公有并按内聚分文件（states / chapter_card / volume
//     / menu / chapter_list / chapter_list_header / chapter_actions_sheet /
//     move_to_volume_sheet）
//   - 4 个原 part/extension 动作方法 → 独立类 + 显式接口注入
//     （host 接口 / chapter_controller / volume_controller / navigator / exporter）
//   - UI 装配 → manuscript_detail_view.dart
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/database/database.dart';
import '../data/repositories/app_state_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chapter_providers.dart';
import '../providers/manuscript_providers.dart';
import 'manuscript_detail_chapter_controller.dart';
import 'manuscript_detail_exporter.dart';
import 'manuscript_detail_host.dart';
import 'manuscript_detail_navigator.dart';
import 'manuscript_detail_view.dart';
import 'manuscript_detail_volume_controller.dart';

/// 作品详情页路由参数
///
/// ⚠️ 公开类：被 app_router / 多处测试引用，必须保持可从本文件导入。
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
    with SingleTickerProviderStateMixin
    implements ManuscriptDetailHost {
  Manuscript? _manuscript;

  /// P3-3：区分「加载中」和「作品不存在」
  bool _isLoaded = false;

  /// 批次92-4：卷折叠状态（卷 id → 是否折叠；吸顶滚动时保留，不随列表重建）
  final Set<String> _collapsedVolumes = {};

  /// 批次28：详情页 Tab（0=章节 1=文件 2=相关对话）
  late final TabController _tabController;

  // ── R-019 真分解：动作控制器（经 ManuscriptDetailHost 注入）──
  late final ManuscriptDetailExporter _exporter = ManuscriptDetailExporter(
    this,
  );
  late final ManuscriptDetailNavigator _navigator = ManuscriptDetailNavigator(
    this,
    _exporter,
  );
  late final ManuscriptDetailChapterController _chapterController =
      ManuscriptDetailChapterController(this, _exporter);
  late final ManuscriptDetailVolumeController _volumeController =
      ManuscriptDetailVolumeController(this, _exporter);

  // ── ManuscriptDetailHost 实现 ──
  @override
  Manuscript? get manuscript => _manuscript;

  @override
  String get manuscriptId => widget.args.manuscriptId;

  @override
  String? get manuscriptTitle => widget.args.title;

  @override
  void showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

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

  /// 批次93-3：返回书架前发刷新信号（书架 listen 后失效章节统计缓存）
  void _handleBack() {
    ref.read(bookshelfRefreshSignalProvider.notifier).state++;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/bookshelf');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapterState = ref.watch(
      chapterStoreProvider(widget.args.manuscriptId),
    );
    // 批次92-1：详情页接入卷分组（读取作品卷列表，无卷走扁平列表）
    final volumes =
        ref.watch(volumeListProvider(widget.args.manuscriptId)).value ??
        const <Volume>[];

    return ManuscriptDetailView(
      manuscript: _manuscript,
      isLoaded: _isLoaded,
      tabIndex: _tabController.index,
      tabController: _tabController,
      chapters: chapterState.chapters,
      volumes: volumes,
      chaptersLoading: chapterState.isLoading,
      collapsedVolumes: _collapsedVolumes,
      appBarTitle: _manuscript?.title ?? widget.args.title ?? '作品详情',
      onBack: _handleBack,
      onCreateVolume: _volumeController.createVolume,
      onMoreMenu: _navigator.openMoreMenu,
      onImport: _navigator.openAppendChapters,
      onChapterTap: _chapterController.openChapter,
      onChapterLongPress: _chapterController.openChapterActions,
      onRenameChapter: _chapterController.renameChapter,
      onQuickCreateChapter: _chapterController.quickCreateChapter,
      onToggleVolume: _toggleVolumeCollapsed,
      onVolumeLongPress: _volumeController.showVolumeActions,
      onRenameVolume: _volumeController.renameVolume,
      onOpenSession: _navigator.handleOpenRelatedSession,
    );
  }
}
