// ─────────────────────────────────────────────────────────────
// growth_detail_error_view — 成长详情页错误态视图
//
// 从 growth_detail_page.dart 真分解而来（R-019：原 part 伪拆分根除）。
//   - GrowthErrorView 加载失败提示 + 重新加载按钮
//
// 无状态纯渲染，仅经构造注入 error 文本与重试回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 加载失败视图（图标 + 文案 + 重新加载）
class GrowthErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const GrowthErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: AppColors.danger),
            const SizedBox(height: 8),
            const Text('加载失败', style: AppTextStyles.body),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.section,
                  vertical: AppSpacing.smx,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}
