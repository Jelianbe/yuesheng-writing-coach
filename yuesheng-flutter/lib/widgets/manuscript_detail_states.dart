// ─────────────────────────────────────────────────────────────
// manuscript_detail_states — 作品详情页状态/元信息组件
//
// 从 manuscript_detail_page.dart 真分解而来（R-019：根除宿主塞满私有 Widget）。
//   - ManuscriptMetaBar         作品元信息条（体裁单行）
//   - ManuscriptLoadingView     加载中视图
//   - ManuscriptNotFoundView    作品不存在视图（P3-3）
//   - EmptyChaptersState        章节空状态
//
// 无状态纯渲染，仅经构造注入数据与回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';

/// 作品元信息条（批次 37 简化 + 修复2：章节数已移到列表头右侧）
///
/// 只保留体裁（纯文字无章节数），大幅压缩顶部占位。
class ManuscriptMetaBar extends StatelessWidget {
  final Manuscript manuscript;
  final int chapterCount;

  const ManuscriptMetaBar({
    super.key,
    required this.manuscript,
    required this.chapterCount,
  });

  @override
  Widget build(BuildContext context) {
    final genre = manuscript.genre.trim();
    if (genre.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
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
              style: AppTextStyles.subBody,
            ),
          ),
        ],
      ),
    );
  }
}

/// 加载中视图
class ManuscriptLoadingView extends StatelessWidget {
  const ManuscriptLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}

/// 作品不存在视图（P3-3：作品被删除或 ID 无效时显示）
class ManuscriptNotFoundView extends StatelessWidget {
  const ManuscriptNotFoundView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
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
              style: AppTextStyles.subBody,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go('/bookshelf'),
              style: AppButtonStyles.primary,
              child: const Text('返回书架'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 章节空状态
class EmptyChaptersState extends StatelessWidget {
  final VoidCallback onCreate;

  const EmptyChaptersState({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text('还没有章节', style: AppTextStyles.titleLg),
            const SizedBox(height: 8),
            const Text(
              '点击「新建章节」开始你的第一篇',
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onCreate,
              style: AppButtonStyles.primary,
              child: const Text('新建章节'),
            ),
          ],
        ),
      ),
    );
  }
}
