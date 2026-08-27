// ─────────────────────────────────────────────────────────────
// ImportSuccessSheet — 导入成功反馈弹层（缺口清单 B 类）
// 真源：yuesheng-android/src/components/reference/ImportSuccessSheet.tsx
//
// 作品导入完成后引导：
//   - 立即诊断：触发自动诊断（RN startDiagnosis=true&chapterId=X 语义）
//   - 稍后再说：仅关闭，刷新引用/消息
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class ImportSuccessSheet extends StatelessWidget {
  /// 作品标题
  final String manuscriptTitle;

  /// 导入章节数
  final int chapterCount;

  /// 作品 ID（预留，对齐 RN manuscriptId）
  final String manuscriptId;

  /// 首章 ID（「立即诊断」诊断目标）
  final String? chapterId;

  /// 「稍后再说」/ 遮罩关闭（对齐 RN handleLater）
  final VoidCallback onClose;

  /// 「立即诊断」（对齐 RN handleDiagnosis：触发自动诊断）
  final VoidCallback onDiagnose;

  /// 是否启用「立即诊断」引导（批次78：追加章节场景不触发诊断，
  /// 关闭提问行与「稍后再说」副按钮，主按钮文案降级为「返回作品」，
  /// 避免「立即诊断」按钮名不副实）
  final bool diagnoseEnabled;

  const ImportSuccessSheet({
    super.key,
    required this.manuscriptTitle,
    required this.chapterCount,
    required this.manuscriptId,
    this.chapterId,
    required this.onClose,
    required this.onDiagnose,
    this.diagnoseEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.section + AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部把手
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.section),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              alignment: Alignment.center,
            ),
            // 成功图标（圆底 + 勾，对齐 RN successIcon）
            Container(
              width: 56,
              height: 56,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.check,
                size: 24,
                color: AppColors.onPrimary,
              ),
            ),
            const Text(
              '导入成功！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已成功导入 $chapterCount 个章节到\n「$manuscriptTitle」',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            if (diagnoseEnabled) ...[
              const Text(
                '是否立即发送给月笙诊断？',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 20),
            ],
            // 立即诊断 / 返回作品（primary 实底）
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDiagnose();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: Text(
                diagnoseEnabled ? '立即诊断' : '返回作品',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
            if (diagnoseEnabled) ...[
              const SizedBox(height: 10),
              // 稍后再说（描边）
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onClose();
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: const Text(
                  '稍后再说',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
