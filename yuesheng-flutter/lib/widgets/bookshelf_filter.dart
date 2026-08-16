// ignore_for_file: invalid_use_of_protected_member
part of 'bookshelf_page.dart';

extension _BookshelfFilter on _BookshelfPageState {
    /// 批次93-2：搜索 + 排序后的列表
    List<Manuscript> _applyFilterAndSort(List<Manuscript> all) {
      var list = all;
      final q = _query.trim().toLowerCase();
      if (q.isNotEmpty) {
        list = list
            .where((m) => m.title.toLowerCase().contains(q))
            .toList();
      }
      final sorted = [...list];
      switch (_sortMode) {
        case _SortMode.recent:
          sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        case _SortMode.created:
          sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        case _SortMode.title:
          sorted.sort((a, b) => a.title.compareTo(b.title));
        case _SortMode.manual:
          sorted.sort((a, b) {
            final c = a.sortOrder.compareTo(b.sortOrder);
            return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
          });
      }
      return sorted;
    }
    /// 批次93-2：AppBar 搜索框（标题模糊匹配，输入即过滤）
    Widget _buildSearchField() {
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
        onChanged: (value) => setState(() => _query = value),
      );
    }
}
