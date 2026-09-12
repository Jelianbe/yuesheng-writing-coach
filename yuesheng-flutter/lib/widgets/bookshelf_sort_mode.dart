// ─────────────────────────────────────────────────────────────
// bookshelf_sort_mode — 书架排序模式
//
// 批次93-2：书架排序（笔落 v2.1.10 手机端书籍列表排序切换）。
// 由 bookshelf_page.dart 家族真分解提升为**公有**：宿主 AppBar 排序菜单与
// BookshelfFilterController 需跨文件共用（原 `_SortMode` 为家族私有）。
// ─────────────────────────────────────────────────────────────

/// 书架排序模式（枚举自带展示文案，供菜单与 SnackBar 复用）
enum BookshelfSortMode {
  recent('最近更新'),
  created('创建时间'),
  title('书名'),
  manual('手动');

  final String label;
  const BookshelfSortMode(this.label);
}
