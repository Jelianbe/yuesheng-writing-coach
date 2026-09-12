// ─────────────────────────────────────────────────────────────
// bookshelf_long_press_sheet — 书架长按操作菜单
//
// 从 bookshelf_page.dart 家族真分解而来：原 `_handleManuscriptLongPress`
// （111 行 R-019 债务）中的菜单渲染在此提为独立展示型 Widget，控制器只负责
// 组装回调（继续写作/编辑信息/置顶/删除），不再内嵌 100+ 行 UI。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'bookshelf_long_press_action.dart';

/// 长按操作菜单（顶部把手 + 作品标题 + 四项动作 + 取消）
class BookshelfLongPressSheet extends StatelessWidget {
  final String title;
  final VoidCallback onContinueWriting;
  final VoidCallback onEditInfo;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const BookshelfLongPressSheet({
    super.key,
    required this.title,
    required this.onContinueWriting,
    required this.onEditInfo,
    required this.onPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            _buildTitle(),
            ..._buildItems(context),
            const SizedBox(height: 8),
            _buildCancel(context),
          ],
        ),
      ),
    );
  }

  /// 四个动作菜单项
  List<Widget> _buildItems(BuildContext context) {
    return [
      _buildItem(
        context,
        icon: Icons.edit_note_outlined,
        label: '继续写作',
        color: AppColors.primary,
        onTap: onContinueWriting,
      ),
      _buildItem(
        context,
        icon: Icons.edit_outlined,
        label: '编辑信息',
        color: AppColors.textPrimary,
        onTap: onEditInfo,
      ),
      _buildItem(
        context,
        icon: Icons.push_pin_outlined,
        label: '置顶',
        color: AppColors.textPrimary,
        onTap: onPin,
      ),
      _buildItem(
        context,
        icon: Icons.delete_outline,
        label: '删除',
        color: AppColors.danger,
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
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  /// 菜单作品标题
  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// 单个菜单项（分隔线 + 长按动作行；点击先收起菜单再执行回调）
  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        BookshelfLongPressAction(
          icon: icon,
          label: label,
          iconColor: color,
          labelColor: color,
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
        ),
      ],
    );
  }

  /// 菜单底部取消按钮
  Widget _buildCancel(BuildContext context) {
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
