// ─────────────────────────────────────────────────────────────
// WritingCoachDeleteDialog — 消息删除确认弹窗（独立纯 Widget，无 part）
//
// R-019 真分解：从 writing_coach_panel_teaching.dart 的 extension 中抽出的
// 151 行 `_buildDeleteConfirmDialog`。改为独立类的静态方法，无实例状态依赖。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 消息删除确认弹窗。
class WritingCoachDeleteDialog extends StatelessWidget {
  const WritingCoachDeleteDialog({super.key});

  /// 弹出确认弹窗，返回用户选择（true = 删除，false / null = 取消）。
  static Future<bool?> show({required BuildContext context}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.overlay,
      builder: (ctx) => _buildDialog(ctx),
    );
  }

  /// 构建 AlertDialog 本体（标题 + 内容 + 取消/删除按钮）。
  static Widget _buildDialog(BuildContext dialogCtx) {
    return AlertDialog(
      title: const Text('删除消息', style: AppTextStyles.titleLg),
      content: const Text(
        '确定要删除这条消息吗？此操作不可撤销。',
        textAlign: TextAlign.center,
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          style: AppButtonStyles.secondary,
          child: const Text(
            '取消',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            padding: const EdgeInsets.symmetric(
              // X-039-Batch1：16→lg / 12→md
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
          ),
          child: const Text(
            '删除',
            style: TextStyle(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildDialog(context);
  }
}
