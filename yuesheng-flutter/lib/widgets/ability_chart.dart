// ─────────────────────────────────────────────────────────────
// AbilityChart — 能力图谱（六大写作能力横向条）
// 真源：yuesheng-android/src/components/profile/AbilityChart.tsx
//
// 视觉（月色竹青）：卡片 + 每行（维度名/描述 | 分数 + 趋势箭头）
// + 分数横向进度条。分数着色：>=80 绿 / >=60 竹青 / >=45 警示 / 其余红
//
// 批次 51b：Flutter GrowthDetailPage 对齐 RN growth-detail.tsx 组件层落地。
// 数据源 AbilityScore（growth_service.dart，批次 51a）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/growth_service.dart';
import '../types/teaching_types.dart';

/// 能力图谱
class AbilityChart extends StatelessWidget {
  final List<AbilityScore> scores;

  const AbilityChart({super.key, required this.scores});

  /// 分数着色（复刻 RN getScoreColor）
  static Color scoreColor(int score) {
    if (score >= 80) return AppColors.success; // 正向
    if (score >= 60) return AppColors.primary; // 竹青
    if (score >= 45) return AppColors.warning; // 警示
    return AppColors.danger; // 红
  }

  /// 趋势箭头文案 + 颜色（复刻 RN getTrendIcon / getTrendColor）
  static (String, Color) trendGlyph(Trend trend) {
    switch (trend) {
      case Trend.improving:
        return ('↑', AppColors.success);
      case Trend.worsening:
        return ('↓', AppColors.danger);
      case Trend.stable:
        return ('→', AppColors.textTertiary);
      case Trend.unknown:
        return ('→', AppColors.textTertiary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '能力图谱',
      description: '从整体（情节/人物/结构）与表达（语言/细节）两个层面评估的六大写作能力',
      child: scores.isEmpty
          ? const _EmptyState(
              icon: Icons.bar_chart,
              title: '暂无能力数据',
              description: '完成几次诊断后，这里会展示你的写作能力画像',
            )
          : Column(
              children: [
                for (final item in scores)
                  _AbilityRow(
                    dimension: item.dimension,
                    description: item.description,
                    score: item.score,
                    trend: item.trend,
                  ),
              ],
            ),
    );
  }
}

class _AbilityRow extends StatelessWidget {
  final String dimension;
  final String description;
  final int score;
  final Trend trend;

  const _AbilityRow({
    required this.dimension,
    required this.description,
    required this.score,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    final color = AbilityChart.scoreColor(score);
    final (glyph, glyphColor) = AbilityChart.trendGlyph(trend);
    final fillWidth = (score < 2 ? 2 : score).clamp(0, 100).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dimension,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    glyph,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: glyphColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // 分数进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: AppColors.surface),
                  FractionallySizedBox(
                    widthFactor: fillWidth / 100,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用区块（对齐 GrowthDetailPage._Card 左侧竹青条风格）
class _Section extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _Section({
    required this.title,
    required this.description,
    required this.child,
  });

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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      child,
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
