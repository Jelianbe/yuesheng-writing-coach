// ─────────────────────────────────────────────────────────────
// bookshelf_filter_controller — 书架页搜索 / 排序动作控制器
//
// 从 bookshelf_filter.dart（原 part/extension）真分解而来：
//   applyFilterAndSort / buildSearchField
//
// 依赖经 [BookshelfPageHost] 显式注入；搜索关键字与排序模式的读写全部
// 走宿主接口，控制器本身不持有状态。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import 'bookshelf_page_host.dart';
import 'bookshelf_sort_mode.dart';

/// 书架页搜索与排序动作
class BookshelfFilterController {
  final BookshelfPageHost host;

  BookshelfFilterController(this.host);

  /// 批次93-2：搜索 + 排序后的列表
  List<Manuscript> applyFilterAndSort(List<Manuscript> all) {
    var list = all;
    final q = host.query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((m) => m.title.toLowerCase().contains(q)).toList();
    }
    final sorted = [...list];
    switch (host.sortMode) {
      case BookshelfSortMode.recent:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case BookshelfSortMode.created:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case BookshelfSortMode.title:
        sorted.sort((a, b) => a.title.compareTo(b.title));
      case BookshelfSortMode.manual:
        sorted.sort((a, b) {
          final c = a.sortOrder.compareTo(b.sortOrder);
          return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
        });
    }
    return sorted;
  }

  /// 批次93-2：AppBar 搜索框（标题模糊匹配，输入即过滤）
  Widget buildSearchField() {
    return TextField(
      key: const Key('bookshelf-search-field'),
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        hintText: '搜索书名',
        hintStyle: TextStyle(fontSize: 14, color: AppColors.textTertiary),
        border: InputBorder.none,
        isDense: true,
      ),
      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      onChanged: host.setQuery,
    );
  }
}
