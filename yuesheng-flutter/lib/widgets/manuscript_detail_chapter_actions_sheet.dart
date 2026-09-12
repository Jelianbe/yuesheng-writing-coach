// ─────────────────────────────────────────────────────────────
// manuscript_detail_chapter_actions_sheet — 章节长按操作弹层
//
// 从 manuscript_detail_chapter.dart（原 part/extension _handleChapterLongPress）
// 真分解而来（R-019：根除 244 行超限方法 + part 形态）。
//   - ChapterActionsSheet 章节操作弹层（重命名/上移/下移/移动到卷/导出/删除）
//
// 无状态纯渲染：每个动作经构造注入回调；点按后先关闭弹层再执行动作
// （与原实现一致）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';

/// 章节长按操作弹层
class ChapterActionsSheet extends StatelessWidget {
  final Chapter chapter;
  final VoidCallback onRename;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onMoveToVolume;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const ChapterActionsSheet({
    super.key,
    required this.chapter,
    required this.onRename,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMoveToVolume,
    required this.onExport,
    required this.onDelete,
  });

  /// 章节显示名（空标题 → 未命名章节）
  String get _name => chapter.title.isEmpty ? '未命名章节' : chapter.title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          12,
          AppSpacing.lg,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            ..._buildEditActions(context),
            ..._buildOrganizeActions(context),
            const SizedBox(height: 8),
            _buildCancelButton(context),
          ],
        ),
      ),
    );
  }

  /// 编辑类操作项（重命名 / 上移 / 下移）
  List<Widget> _buildEditActions(BuildContext context) {
    return [
      // 修复3：重命名章节（铅笔图标入口之外的第二入口）
      _actionItem(
        context,
        icon: Icons.edit_outlined,
        label: '重命名《$_name》',
        color: AppColors.primary,
        onTap: onRename,
      ),
      const Divider(height: 1, color: AppColors.divider),
      // 批次96-1：卷内上移（同卷前一章交换 sort_order）
      _actionItem(
        context,
        icon: Icons.arrow_upward_outlined,
        label: '上移',
        color: AppColors.primary,
        onTap: onMoveUp,
      ),
      const Divider(height: 1, color: AppColors.divider),
      // 批次96-1：卷内下移（同卷后一章交换 sort_order）
      _actionItem(
        context,
        icon: Icons.arrow_downward_outlined,
        label: '下移',
        color: AppColors.primary,
        onTap: onMoveDown,
      ),
      const Divider(height: 1, color: AppColors.divider),
    ];
  }

  /// 整理与危险操作项（移动到卷 / 导出 / 删除）
  List<Widget> _buildOrganizeActions(BuildContext context) {
    return [
      // 批次96-1：移动到卷（跨卷归属调整，对齐章节树抽屉入口）
      _actionItem(
        context,
        icon: Icons.drive_file_move_outlined,
        label: '移动到卷',
        color: AppColors.primary,
        onTap: onMoveToVolume,
      ),
      const Divider(height: 1, color: AppColors.divider),
      // 批次94-1：导出本章（重命名与删除之间）
      _actionItem(
        context,
        icon: Icons.ios_share_outlined,
        label: '导出《$_name》',
        color: AppColors.primary,
        onTap: onExport,
      ),
      const Divider(height: 1, color: AppColors.divider),
      _actionItem(
        context,
        icon: Icons.delete_outline,
        label: '删除《$_name》',
        color: AppColors.danger,
        labelColor: AppColors.danger,
        onTap: onDelete,
      ),
    ];
  }

  /// 顶部把手
  Widget _buildHandle() {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }

  /// 单个操作项：先关闭弹层再执行动作（与原实现一致）
  Widget _actionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    Color? labelColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: labelColor ?? AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 取消按钮
  Widget _buildCancelButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          side: const BorderSide(color: AppColors.border),
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        child: const Text('取消'),
      ),
    );
  }
}
