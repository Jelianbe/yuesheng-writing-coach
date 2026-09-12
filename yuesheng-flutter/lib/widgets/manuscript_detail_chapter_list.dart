// ─────────────────────────────────────────────────────────────
// manuscript_detail_chapter_list — 作品详情页章节列表
//
// 从 manuscript_detail_page.dart 真分解而来（R-019：根除宿主塞满私有 Widget）。
//   - ChapterList 章节列表（批次92-1/92-4/92-5：CustomScrollView + 卷分组 + 卷头吸顶）
//
// 无状态纯渲染，仅经构造注入数据与回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../utils/volume_group.dart';
import 'manuscript_detail_chapter_card.dart';
import 'manuscript_detail_chapter_list_header.dart';
import 'manuscript_detail_volume.dart';

/// 章节列表（批次92-1/92-4/92-5：CustomScrollView + 卷分组 + 卷头吸顶）
///
/// - 无卷（volumes 为空）→ 扁平章节列表（批次83 原行为，兼容既有测试）
/// - 有卷 → 按 buildChapterSections 渲染（批次96-4）：
///   散落章节直接平铺（无组头），卷组按全局序自然穿插；
///   卷头为 SliverPersistentHeader(pinned) 吸顶（纯纯 v27.12.7 + 笔落 v2.1.3），
///   整行可点折叠（accordion 教训：48px 高触摸目标），折叠态由父 State 持有
///   （吸顶滚动时保留，不随列表重建）
class ChapterList extends StatelessWidget {
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

  const ChapterList({
    super.key,
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
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ChapterCard(
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
    final header = ChapterListHeader(
      onImport: onImport,
      chapterCount: chapterCount,
    );

    // 无卷 → 扁平章节列表（批次83 原行为）
    if (volumes.isEmpty) {
      return _buildFlatScrollView(header);
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            sliver: SliverToBoxAdapter(child: _buildChapterCard(loose, 0)),
          ),
        );
        continue;
      }
      _appendVolumeSectionSlivers(slivers, sec);
    }
    // 批次96-4：列表末尾「新建章节」入口（归属散落，与无卷扁平列表一致）
    slivers.add(
      SliverToBoxAdapter(
        child: NewChapterRow(
          targetVolumeId: null,
          onTap: () => onQuickCreateChapter(null),
        ),
      ),
    );
    return CustomScrollView(slivers: slivers);
  }

  /// 无卷 → 扁平章节列表（批次83 原行为；R-019 清偿拆出）。
  Widget _buildFlatScrollView(Widget header) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          sliver: _chapterSliver(chapters),
        ),
        // 批次96-2：列表末尾「新建章节」入口（无卷 → 未分卷）
        SliverToBoxAdapter(
          child: NewChapterRow(
            targetVolumeId: null,
            onTap: () => onQuickCreateChapter(null),
          ),
        ),
      ],
    );
  }

  /// 单卷段 sliver 追加：吸顶卷头 + 章列表 + 卷内新建入口（R-019 清偿拆出）。
  void _appendVolumeSectionSlivers(List<Widget> slivers, ChapterSection sec) {
    final group = VolumeGroup(volume: sec.volume, chapters: sec.chapters);
    final key = sec.volume!.id;
    slivers.add(
      SliverPersistentHeader(
        pinned: true,
        delegate: VolumeHeaderDelegate(
          group: group,
          collapsed: collapsedVolumes.contains(key),
          onToggle: () => onToggleVolume(key),
          onLongPress: () => onVolumeLongPress(sec.volume!),
          onRename: () => onRenameVolume(sec.volume!),
        ),
      ),
    );
    if (collapsedVolumes.contains(key)) return;
    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        sliver: sec.chapters.isEmpty
            ? const SliverToBoxAdapter(child: DetailEmptyVolumeHint())
            : _chapterSliver(sec.chapters),
      ),
    );
    // 批次96-2：卷内末尾「新建章节」入口（就近归属该卷）
    slivers.add(
      SliverToBoxAdapter(
        child: NewChapterRow(
          targetVolumeId: sec.volume!.id,
          onTap: () => onQuickCreateChapter(sec.volume!.id),
        ),
      ),
    );
  }
}
