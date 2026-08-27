// ─────────────────────────────────────────────────────────────
// TrainingPassRateCard — X-041b 训练通过率看板
//
// 数据源：GrowthState.trainingStats（来自 training_results 表聚合）
// UI 位置：growth_detail_page「症候分布」之后、「同类症候复发率」之前
//
// 设计意图：
// - 反映用户在各症候上的练习投入量与掌握程度
// - 作为长期进步曲线的补充维度（与写作曲线/症候趋势并列）
// - 通过率口径：passed=1.0 / partial=0.5 / failed=0.0
//
// 视觉规范（月色竹青，对齐 GrowthDetailPage._Card）：
//   卡片         #F2F4F2 + 左侧 4dp 竹青条 + AppRadius.md 圆角
//   通过率色    ≥80% primary / 50-80% warning / <50% danger
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/repositories/training_result_repository.dart';
import '../services/syndrome_registry.dart';

/// 训练通过率看板卡片
class TrainingPassRateCard extends StatelessWidget {
  final List<SyndromeTrainingStats> stats;

  const TrainingPassRateCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();

    final totalPractices = stats.fold<int>(0, (s, r) => s + r.total);
    final totalPassed = stats.fold<int>(0, (s, r) => s + r.passed);
    final totalPartial = stats.fold<int>(0, (s, r) => s + r.partial);
    // 整体通过率（加权：passed=1.0 / partial=0.5）
    final overallRate = totalPractices == 0
        ? 0.0
        : (totalPassed + totalPartial * 0.5) / totalPractices;

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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '训练通过率',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stats.length} 个症候 · 共 $totalPractices 次练习 · '
                        '整体通过率 ${(overallRate * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < stats.length; i++) ...[
                        _StatsRow(stat: stats[i]),
                        if (i < stats.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单症候训练统计行
class _StatsRow extends StatelessWidget {
  final SyndromeTrainingStats stat;

  const _StatsRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    final record = syndromeRecordOf(stat.syndromeId);
    final name = record?.name ?? stat.syndromeId;
    final ratePercent = (stat.passRate * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '通过 ${stat.passed} · 部分通过 ${stat.partial} · '
                    '未过 ${stat.failed}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$ratePercent%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _rateColor(stat.passRate),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: LinearProgressIndicator(
            value: stat.passRate,
            minHeight: 4,
            backgroundColor: AppColors.border,
            color: _rateColor(stat.passRate),
          ),
        ),
      ],
    );
  }

  /// 通过率颜色：≥80% primary（掌握良好）/ 50-80% warning（待巩固）/ <50% danger（需加强）
  Color _rateColor(double rate) {
    if (rate >= 0.8) return AppColors.primary;
    if (rate >= 0.5) return AppColors.warning;
    return AppColors.danger;
  }
}
