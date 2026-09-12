// ─────────────────────────────────────────────────────────────
// bookshelf_genre_section — 新建作品弹窗「类型」区
//
// 从 bookshelf_page.dart 家族真分解而来：原 `_CreateManuscriptModalState`
// 内嵌的体裁 Chip 预设（批次93-5 番茄作家助手模型）+ 自定义输入在此提为
// 独立展示型 Widget，使弹窗 State 保持 ≤300 行且每个构建函数 ≤50 行。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 类型区：ChoiceChip 预设（奇幻/都市/言情/…/其他）+ 选中「其他」时展开自定义输入
class BookshelfGenreSection extends StatelessWidget {
  final TextEditingController controller;
  final String selected;
  final bool custom;
  final bool enabled;
  final ValueChanged<String> onPresetSelected;
  final ValueChanged<String> onCustomChanged;

  const BookshelfGenreSection({
    super.key,
    required this.controller,
    required this.selected,
    required this.custom,
    required this.enabled,
    required this.onPresetSelected,
    required this.onCustomChanged,
  });

  /// 批次93-5：体裁 Chip 预设（番茄作家助手模型）
  static const List<String> presets = [
    '奇幻',
    '都市',
    '言情',
    '科幻',
    '武侠',
    '悬疑',
    '历史',
    '其他',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '类型（可选）',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 8),
        _buildChips(),
        // 选中「其他」→ 展开自定义体裁输入
        if (custom) ...[const SizedBox(height: 10), _buildCustomField()],
      ],
    );
  }

  Widget _buildChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final preset in presets) _buildChip(preset)],
    );
  }

  /// 单个体裁 Chip
  Widget _buildChip(String preset) {
    final isSelected = selected == preset;
    return ChoiceChip(
      key: ValueKey('genre-chip-$preset'),
      label: Text(preset),
      selected: isSelected,
      selectedColor: AppColors.primarySoft,
      labelStyle: TextStyle(
        fontSize: 13,
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
      onSelected: enabled ? (_) => onPresetSelected(preset) : null,
    );
  }

  Widget _buildCustomField() {
    return TextField(
      key: const Key('custom-genre-field'),
      controller: controller,
      enabled: enabled,
      onChanged: onCustomChanged,
      decoration: AppBoxStyles.standardInput(
        hintText: '输入自定义类型',
        isDense: true,
      ),
    );
  }
}
