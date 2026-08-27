// ─────────────────────────────────────────────────────────────
// PracticeResultIndicator — 练习结果指示器
// 复刻 yuesheng-android/src/components/diagnosis/PracticeResultIndicator.tsx
//
// 状态：
//   passed  → 达标！你掌握了这个要点（竹青）
//   partial → 部分达标，方向正确，细节需打磨（矿物黄）
//   failed  → 未达标，建议重新理解要求（矿物红）
//
// 操作：
//   - failed 时显示「再试一次」（可选）
//   - 始终显示「关闭」
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../types/teaching_types.dart';

/// 训练结果 → 文案 + 配色
({String text, IconData icon, Color color, Color bg}) _resultConfig(
  TrainingResult result,
) {
  switch (result) {
    case TrainingResult.passed:
      return (
        text: '达标！你掌握了这个要点',
        icon: Icons.check_circle_outline,
        color: AppColors.primary,
        bg: AppColors.l1,
      );
    case TrainingResult.partial:
      return (
        text: '部分达标，方向正确，细节需打磨',
        icon: Icons.change_circle_outlined,
        color: AppColors.l2Text,
        bg: AppColors.l2,
      );
    case TrainingResult.failed:
      return (
        text: '未达标，建议重新理解要求',
        icon: Icons.cancel_outlined,
        color: AppColors.l3Text,
        bg: AppColors.l3,
      );
  }
}

class PracticeResultIndicator extends StatelessWidget {
  final TrainingResult result;
  final String? details;

  /// 关闭结果回调
  final VoidCallback? onDismiss;

  /// 再试一次（未达标时）
  final VoidCallback? onRetry;

  const PracticeResultIndicator({
    super.key,
    required this.result,
    this.details,
    this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _resultConfig(result);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cfg.icon, size: 20, color: cfg.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cfg.text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cfg.color,
                  ),
                ),
              ),
            ],
          ),
          if (details != null && details!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (result == TrainingResult.failed && onRetry != null) ...[
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.l3Text,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xsm,
                    ),
                  ),
                  child: const Text(
                    '再试一次',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textTertiary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xsm,
                  ),
                ),
                child: const Text(
                  '关闭',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
