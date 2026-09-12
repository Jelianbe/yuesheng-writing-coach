// ─────────────────────────────────────────────────────────────
// manuscript_detail_chapter_card — 作品详情页章节卡片
//
// 从 manuscript_detail_page.dart 真分解而来（R-019：根除宿主塞满私有 Widget）。
//   - ChapterStatusConfig   章节状态 → 中文标签 + 矿物色配色
//   - chapterStatusConfig   状态配置表（draft/revising/complete）
//   - ChapterCard           章节卡片（修复1：纯文字无序号色块；修复3：行尾编辑图标）
//
// 无状态纯渲染，仅经构造注入数据与回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';

/// 章节状态 → 中文标签 + 矿物色配色
class ChapterStatusConfig {
  final String label;
  final Color bgColor;
  final Color textColor;
  const ChapterStatusConfig(this.label, this.bgColor, this.textColor);
}

/// 章节状态配置表
const Map<String, ChapterStatusConfig> chapterStatusConfig = {
  'draft': ChapterStatusConfig('草稿', AppColors.border, AppColors.textDeep),
  'revising': ChapterStatusConfig(
    '修改中',
    AppColors.warningBg,
    AppColors.warning,
  ),
  'complete': ChapterStatusConfig('完成', AppColors.l1, AppColors.primary),
};

/// 章节卡片（修复1：移除序号色块，改为纯文字；修复3：行尾增加编辑图标用于重命名）
class ChapterCard extends StatelessWidget {
  final Chapter chapter;
  final int index;
  final VoidCallback onTap;

  /// 长按 → 操作菜单（删除 / 重命名）
  final VoidCallback onLongPress;

  /// 行尾可见删除入口（对齐 file_section 批次75，复用长按删除流程）
  final VoidCallback onDelete;

  /// 修复3：行尾铅笔图标 → 直接重命名
  final VoidCallback onRename;

  const ChapterCard({
    super.key,
    required this.chapter,
    required this.index,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onRename,
  });

  String _formatWords(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万字';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}千字';
    }
    return '$count字';
  }

  @override
  Widget build(BuildContext context) {
    final statusCfg =
        chapterStatusConfig[chapter.status] ?? chapterStatusConfig['draft']!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              // 章节信息（修复1：移除左侧序号色块，纯文字展示）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(statusCfg),
                    const SizedBox(height: 6),
                    _buildMetaRow(),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _buildTrailingActions(),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题行：章节名 + 状态标签（R-019 清偿拆出）。
  Widget _buildTitleRow(ChapterStatusConfig statusCfg) {
    return Row(
      children: [
        Expanded(
          child: Text(
            chapter.title.isEmpty ? '未命名章节' : chapter.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        // 状态标签
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: statusCfg.bgColor,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            statusCfg.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: statusCfg.textColor,
            ),
          ),
        ),
      ],
    );
  }

  /// 元信息行：字数 + 已诊断（R-019 清偿拆出）。
  Widget _buildMetaRow() {
    return Row(
      children: [
        const Icon(
          Icons.sticky_note_2_outlined,
          size: 12,
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: 4),
        Text(
          _formatWords(chapter.wordCount),
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
        if (chapter.lastDiagnosedAt != null) ...[
          const SizedBox(width: 12),
          const Icon(
            Icons.check_circle_outline,
            size: 12,
            color: AppColors.textDeep,
          ),
          const SizedBox(width: 4),
          const Text(
            '已诊断',
            style: TextStyle(fontSize: 12, color: AppColors.textDeep),
          ),
        ],
      ],
    );
  }

  /// 行尾操作：重命名 + 删除 + 跳转箭头（R-019 清偿拆出）。
  Widget _buildTrailingActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 修复3：行尾铅笔图标（直接重命名章节名）
        IconButton(
          onPressed: onRename,
          icon: const Icon(
            Icons.edit_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
          tooltip: '重命名章节',
          visualDensity: VisualDensity.compact,
        ),
        // 批次79 C：行尾可见删除入口
        IconButton(
          onPressed: onDelete,
          icon: const Icon(
            Icons.delete_outline,
            size: 18,
            color: AppColors.danger,
          ),
          tooltip: '删除章节',
          visualDensity: VisualDensity.compact,
        ),
        const Icon(
          Icons.chevron_right,
          size: 20,
          color: AppColors.textTertiary,
        ),
      ],
    );
  }
}
