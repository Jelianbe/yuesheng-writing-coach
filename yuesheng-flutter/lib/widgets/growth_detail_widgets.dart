// ─────────────────────────────────────────────────────────────
// growth_detail_widgets — 成长详情页通用原子组件
//
// 从 growth_detail_page.dart 真分解而来（R-019：原 part 伪拆分根除）。
// 本文件收纳与「成长详情页」强相关、但彼此独立的纯展示组件：
//   - GrowthInfoCard        通用卡片（左侧 4dp 竹青色条）
//   - GrowthInfoRow         标签-值行
//   - GrowthRecurrenceRow   单条症候复发率行
//   - SeverityChip          严重度徽章（L1/L2/L3 矿物色）
//
// 均为无状态纯渲染，无宿主状态依赖。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/growth_service.dart';

/// 通用卡片（左侧 4dp 竹青色条，与 GrowthPage._Card 视觉一致）
///
/// 注意：色条使用 [AppColors.primary]（= #2D5A52），
/// widget 测试 #V3 断言 `maxWidth==4 && color==0xFF2D5A52`，不得变更。
class GrowthInfoCard extends StatelessWidget {
  final Widget child;

  const GrowthInfoCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: AppColors.primary),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标签-值行（左右两端对齐）
class GrowthInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const GrowthInfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppTextStyles.subBody),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// 批次65（B62h）：单条症候复发率行（症候名 + 出现/好转/再犯 + 复发率%）
class GrowthRecurrenceRow extends StatelessWidget {
  final SyndromeRecurrence recurrence;

  const GrowthRecurrenceRow({super.key, required this.recurrence});

  @override
  Widget build(BuildContext context) {
    final rate = (recurrence.rate * 100).round();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recurrence.syndromeName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '出现 ${recurrence.occurrences} 次 · 好转 ${recurrence.recovered} 次 · '
                '再犯 ${recurrence.recurrences} 次',
                style: AppTextStyles.microCaption,
              ),
            ],
          ),
        ),
        Text(
          '$rate%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: rate >= 50 ? AppColors.danger : AppColors.primary,
          ),
        ),
      ],
    );
  }
}

/// 严重度徽章（L1/L2/L3 → 矿物色；未知归 border 灰）
class SeverityChip extends StatelessWidget {
  final String severity;

  const SeverityChip({super.key, required this.severity});

  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      'L1' => AppColors.l1,
      'L2' => AppColors.l2,
      'L3' => AppColors.l3,
      _ => AppColors.border,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        severity,
        style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
      ),
    );
  }
}
