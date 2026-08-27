// ─────────────────────────────────────────────────────────────
// WritingCurveChart — 写作成长曲线（近 N 天每日字数/诊断次数柱状图）
// 真源：yuesheng-android/src/components/profile/WritingCurveChart.tsx
//
// 视觉（月色竹青）：卡片 + 摘要行（总字数/诊断次数/活跃天数）+ 图例
// + 横向滚动柱状图（字数柱竹青，今天高亮；诊断点警示色）
//
// 批次 51b：Flutter GrowthDetailPage 对齐 RN growth-detail.tsx 组件层落地。
// 数据源 WritingDataPoint（growth_service.dart，批次 51a）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/shared_constants.dart';
import '../services/growth_service.dart';

/// 写作成长曲线
class WritingCurveChart extends StatelessWidget {
  final List<WritingDataPoint> points;

  const WritingCurveChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final maxWords = points.fold<int>(
      1,
      (m, p) => p.wordCount > m ? p.wordCount : m,
    );
    final totalWords = points.fold<int>(0, (s, p) => s + p.wordCount);
    final totalDiag = points.fold<int>(0, (s, p) => s + p.diagnosisCount);
    final activeDays = points.where((p) => p.wordCount > 0).length;

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
                        '写作成长曲线',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '每日字数与诊断次数趋势',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (points.isEmpty)
                        const _EmptyState(
                          icon: Icons.trending_up,
                          title: '暂无写作记录',
                          description: '持续写作，这里会展示你的成长轨迹',
                        )
                      else ...[
                        // 摘要行
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            children: [
                              _SummaryItem(
                                value: formatWordCount(totalWords),
                                label: '字数',
                              ),
                              const _SummaryDivider(),
                              _SummaryItem(value: '$totalDiag', label: '诊断'),
                              const _SummaryDivider(),
                              _SummaryItem(value: '$activeDays', label: '活跃天数'),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // 图例
                        const Row(
                          children: [
                            _LegendItem(color: AppColors.primary, label: '字数'),
                            SizedBox(width: AppSpacing.lg),
                            _LegendItem(color: AppColors.warning, label: '诊断'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // 柱状图（横向滚动）
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _ChartBody(points: points, maxWords: maxWords),
                        ),
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

class _ChartBody extends StatelessWidget {
  final List<WritingDataPoint> points;
  final int maxWords;

  const _ChartBody({required this.points, required this.maxWords});

  static const double _barWidth = 6;
  static const double _barGap = 2;
  static const double _cellWidth = _barWidth + _barGap;
  static const double _chartHeight = 120;
  static const double _maxRatio = 0.85;

  /// YYYY-MM-DD -> M/D（复刻 RN formatDayLabel）
  static String _dayLabel(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length < 3) return dateStr;
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;
    return '$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 字数柱状图
        SizedBox(
          height: _chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < points.length; i++)
                SizedBox(
                  width: _cellWidth,
                  child: Center(
                    child: Container(
                      width: _barWidth,
                      height: _barHeight(points[i]),
                      decoration: BoxDecoration(
                        color: i == points.length - 1
                            ? AppColors.primaryDeep
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 诊断次数点
        SizedBox(
          height: 24,
          child: Row(
            children: [
              for (final p in points)
                SizedBox(
                  width: _cellWidth,
                  child: p.diagnosisCount > 0
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (p.diagnosisCount > 1)
                              Text(
                                '${p.diagnosisCount}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                ),
                              ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
        // X 轴日期标签
        SizedBox(
          height: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < points.length; i++)
                SizedBox(
                  width: _cellWidth,
                  child: i % 2 == 0 || i == points.length - 1
                      ? Text(
                          i == points.length - 1
                              ? '今天'
                              : _dayLabel(points[i].date),
                          style: TextStyle(
                            fontSize: 9,
                            color: i == points.length - 1
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            fontWeight: i == points.length - 1
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  double _barHeight(WritingDataPoint p) {
    if (p.wordCount <= 0) return 2; // 最小高度
    final ratio = p.wordCount / maxWords;
    final h = _chartHeight * ratio * _maxRatio;
    return h < 2 ? 2 : h;
  }
}

class _SummaryItem extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.microCaption,
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: AppColors.border);
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.microCaption,
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
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
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
