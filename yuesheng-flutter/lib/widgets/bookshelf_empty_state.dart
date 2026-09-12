// ─────────────────────────────────────────────────────────────
// bookshelf_empty_state — 书架空状态视图
//
// 从 bookshelf_page.dart 宿主内嵌私有 `_EmptyState` 真分解提公而来。
// 批次93-6：包在可滚动容器内，支持 RefreshIndicator 下拉刷新。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 空状态视图（批次93-6：包在可滚动容器内，支持 RefreshIndicator 下拉刷新）
class BookshelfEmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const BookshelfEmptyState({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.library_books,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 20),
                  const Text('还没有作品', style: AppTextStyles.titleLg),
                  const SizedBox(height: 8),
                  const Text(
                    '点击「新建」创建你的第一部作品',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onCreate,
                    style: AppButtonStyles.primary,
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
