// ─────────────────────────────────────────────────────────────
// bookshelf_error_view — 书架加载失败错误态
//
// 从 bookshelf_page.dart 宿主内嵌私有 `_ErrorView` 真分解提公而来。
// 批次93-3：错误态（重试按钮）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 批次93-3：加载失败错误态（重试按钮）
class BookshelfErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const BookshelfErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
