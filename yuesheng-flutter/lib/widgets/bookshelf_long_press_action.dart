// ─────────────────────────────────────────────────────────────
// bookshelf_long_press_action — 书架长按操作菜单项
//
// 从 bookshelf_page.dart 宿主内嵌私有 `_LongPressAction` 真分解提公而来。
// 批次93-7 起被 BookshelfActionsController 的长按菜单复用 4 次，故必须公有。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 批次93-7：长按操作菜单项
class BookshelfLongPressAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color labelColor;
  final VoidCallback onTap;

  const BookshelfLongPressAction({
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
