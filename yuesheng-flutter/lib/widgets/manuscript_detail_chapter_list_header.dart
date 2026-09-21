// ─────────────────────────────────────────────────────────────
// manuscript_detail_chapter_list_header — 作品详情页章节列表头/新建行
//
// 从 manuscript_detail_page.dart 真分解而来（R-019：根除宿主塞满私有 Widget）。
//   - ChapterListHeader 「章节列表 X 章」+ 导入（修复2：章节数移到右侧）
//   - NewChapterRow    列表级「新建章节」行（批次96-2）
//
// 无状态纯渲染，仅经构造注入数据与回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../config/app_theme.dart';
import '../theme/app_typography.dart';

/// 章节列表头：「章节列表 X 章」+ 新建卷 + 导入（修复2：章节数移到右侧区域）
class ChapterListHeader extends StatelessWidget {
  final VoidCallback onImport;
  final int chapterCount;

  const ChapterListHeader({
    super.key,
    required this.onImport,
    required this.chapterCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 横向 padding 收进组件自身：此前只声明纵向，横向定位由父级提供，
      // 而两个父级给的横向基准不同（空态 ListView 给 lg、数据态 CustomScrollView
      // 未传 padding 即 0）⇒ 建章后整行左移 16dp（「字串漂移」根因）。
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '章节列表',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Text('$chapterCount 章', style: context.text.caption),
          const Spacer(),
          InkWell(
            onTap: onImport,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xsm,
              ),
              decoration: BoxDecoration(
                color: context.palette.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '导入',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 批次96-2：列表级「新建章节」行（百灵「⊕ 新建章节」模型）
/// targetVolumeId = 归属卷；null = 未分卷（列表末尾）
class NewChapterRow extends StatelessWidget {
  final String? targetVolumeId;
  final VoidCallback onTap;

  const NewChapterRow({
    super.key,
    required this.targetVolumeId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
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
            color: context.palette.background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.palette.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 18,
                color: context.palette.textTertiary,
              ),
              SizedBox(width: 8),
              Text(
                '新建章节',
                style: TextStyle(
                  fontSize: 14,
                  color: context.palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
