// ─────────────────────────────────────────────────────────────
// bookshelf_no_search_result — 书架搜索无结果空态
//
// 从 bookshelf_page.dart 宿主内嵌私有 `_NoSearchResult` 真分解提公而来。
// 批次93-2：搜索无结果空态。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 批次93-2：搜索无结果空态
class BookshelfNoSearchResult extends StatelessWidget {
  final String query;
  final bool searching;

  const BookshelfNoSearchResult({
    super.key,
    required this.query,
    required this.searching,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.search_off, size: 48, color: AppColors.textTertiary),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            '没有找到相关作品',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(searching ? '换个书名试试吧' : '', style: AppTextStyles.caption),
        ),
      ],
    );
  }
}
