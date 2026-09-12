// ─────────────────────────────────────────────────────────────
// manuscript_detail_volume — 作品详情页卷头组件
//
// 从 manuscript_detail_page.dart 真分解而来（R-019：根除宿主塞满私有 Widget）。
//   - DetailVolumeHeader     详情页卷头（批次92-4 视觉加厚）
//   - VolumeHeaderDelegate   吸顶卷头 delegate（批次92-5：SliverPersistentHeader pinned）
//   - DetailEmptyVolumeHint  详情页空卷占位
//
// 无状态纯渲染，仅经构造注入数据与回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../utils/volume_group.dart';

/// 吸顶卷头 delegate（批次92-5：SliverPersistentHeader pinned）
class VolumeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final VolumeGroup group;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;

  VolumeHeaderDelegate({
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
    return DetailVolumeHeader(
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
  bool shouldRebuild(VolumeHeaderDelegate old) {
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
class DetailVolumeHeader extends StatelessWidget {
  final Volume? volume;
  final int count;
  final int totalWords;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;

  const DetailVolumeHeader({
    super.key,
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
          height: VolumeHeaderDelegate._height,
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border(
              bottom: BorderSide(color: AppColors.divider, width: 1),
            ),
          ),
          child: Row(
            children: [
              _buildLeading(isUnassigned, collapsed),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMd,
                ),
              ),
              _buildTrailingInfo(),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 左侧：3dp 色条 + 折叠箭头 + 卷图标（R-019 清偿拆出）。
  Widget _buildLeading(bool isUnassigned, bool collapsed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 左侧 3dp 色条（卷 → 竹青；未分卷 → 弱化灰）
        Container(
          width: 3,
          color: isUnassigned ? AppColors.placeholder : AppColors.primary,
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
      ],
    );
  }

  /// 尾部：字数 + 章数 + 重命名铅笔（R-019 清偿拆出）。
  Widget _buildTrailingInfo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (totalWords > 0) ...[
          Text(_formatWords(totalWords), style: AppTextStyles.microCaption),
          const SizedBox(width: 8),
        ],
        Text('$count 章', style: AppTextStyles.microCaption),
        if (onRename != null) ...[
          const SizedBox(width: 4),
          // 批次92-2：卷头铅笔图标 → 直接重命名
          InkWell(
            onTap: onRename,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              child: Icon(
                Icons.edit_outlined,
                size: 14,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 详情页空卷占位（卷内无章节时显示在卷头下方）
class DetailEmptyVolumeHint extends StatelessWidget {
  const DetailEmptyVolumeHint({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Text('暂无章节', style: AppTextStyles.caption),
    );
  }
}
