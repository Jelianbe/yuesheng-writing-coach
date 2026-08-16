// ─────────────────────────────────────────────────────────────
// AbandonPracticeDialog — 放弃练习确认弹窗（缺口清单 C 类）
// 真源：yuesheng-android/src/components/modals/AbandonPracticeModal.tsx
//
// 训练中点击「跳过」→ 阻断式确认：
//   - 继续练习：关闭弹窗，任务保留
//   - 确认跳过：关闭弹窗 → 清空练习状态 → 子阶段回 DIAGNOSIS
// 阻断式：点击遮罩不关闭（对齐 RN onRequestClose 空实现）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class AbandonPracticeDialog extends StatelessWidget {
  /// 继续练习：关闭弹窗，保留任务
  final VoidCallback onContinue;

  /// 确认跳过：关闭弹窗 → 调用方清空练习状态并回 DIAGNOSIS
  final VoidCallback onConfirmSkip;

  const AbandonPracticeDialog({
    super.key,
    required this.onContinue,
    required this.onConfirmSkip,
  });

  /// 打开确认弹窗（阻断式：barrierDismissible=false，对齐 RN 点击遮罩不关闭）
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onContinue,
    required VoidCallback onConfirmSkip,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AbandonPracticeDialog(
        onContinue: onContinue,
        onConfirmSkip: onConfirmSkip,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 警示图标圆底（对齐 RN iconContainer 56x56 dangerBg）
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.dangerBg,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 28,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '确定跳过本次练习？',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '已输入的内容将丢失，练习进度不会保存。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onContinue();
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text(
                      '继续练习',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onConfirmSkip();
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text(
                      '确认跳过',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
