// ─────────────────────────────────────────────────────────────
// manuscript_detail_menu — 作品详情页更多菜单
//
// 从 manuscript_detail_page.dart 真分解而来（R-019：根除宿主塞满私有 Widget）。
//   - MoreMenuSheet    更多菜单 bottom sheet（批次 20，对齐 RN MoreMenuSheet）
//   - MenuActionItem   菜单项（正常可点击）
//
// 无状态纯渲染，仅经构造注入回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 更多菜单 bottom sheet（批次 20，对齐 RN MoreMenuSheet）
class MoreMenuSheet extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onExport;
  final VoidCallback onRecycleBin;
  final VoidCallback onDelete;

  const MoreMenuSheet({
    super.key,
    required this.onOpenSettings,
    required this.onExport,
    required this.onRecycleBin,
    required this.onDelete,
  });

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
            ..._buildMenuItems(),
            const SizedBox(height: 8),
            _buildCancelButton(context),
          ],
        ),
      ),
    );
  }

  /// 菜单项列表：项目设置 / 导出整书 / 回收站 / 删除项目（R-019 清偿拆出）。
  List<Widget> _buildMenuItems() {
    return [
      // 批次77：移除「导出项目」「分享」开发中死菜单项（对齐写作页 E3 清理，
      // 菜单只保留真实功能：项目设置 / 删除项目）
      MenuActionItem(
        icon: Icons.settings_outlined,
        label: '项目设置',
        iconColor: AppColors.textPrimary,
        labelColor: AppColors.textPrimary,
        onTap: onOpenSettings,
      ),
      const Divider(height: 1, color: AppColors.divider),
      // 批次94-1：导出整书（批次77 曾移除的「导出项目」死菜单，现为真实功能）
      MenuActionItem(
        icon: Icons.ios_share_outlined,
        label: '导出整书',
        iconColor: AppColors.primary,
        labelColor: AppColors.textPrimary,
        onTap: onExport,
      ),
      const Divider(height: 1, color: AppColors.divider),
      // 批次94-2：章节回收站（软删章节恢复/永久删除）
      MenuActionItem(
        icon: Icons.delete_sweep_outlined,
        label: '回收站',
        iconColor: AppColors.textPrimary,
        labelColor: AppColors.textPrimary,
        onTap: onRecycleBin,
      ),
      const Divider(height: 1, color: AppColors.divider),
      MenuActionItem(
        icon: Icons.delete_outline,
        label: '删除项目',
        iconColor: AppColors.danger,
        labelColor: AppColors.danger,
        onTap: onDelete,
      ),
    ];
  }

  /// 顶部把手（R-019 清偿拆出）。
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

  /// 取消按钮（R-019 清偿拆出）。
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

/// 菜单项（正常可点击）
class MenuActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color labelColor;
  final VoidCallback onTap;

  const MenuActionItem({
    super.key,
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
