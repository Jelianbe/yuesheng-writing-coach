// ─────────────────────────────────────────────────────────────
// bookshelf_loading_view — 书架加载中视图
//
// 从 bookshelf_page.dart 宿主内嵌私有 `_LoadingView` 真分解提公而来。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 书架加载中视图
class BookshelfLoadingView extends StatelessWidget {
  const BookshelfLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}
