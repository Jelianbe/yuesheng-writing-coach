// ─────────────────────────────────────────────────────────────
// ability_progress_chart — 教学线 P1-5 能力进步曲线
//
// 数据源：跨会话评估历史（EvaluationData.abilityScores，按
// generatedAt 升序）。x = 评估轮次（第 N 次评估），y = 0-100 分，
// 六大能力维度各一条折线。自绘（项目图表全部自绘，无第三方库）。
//
// 克制：点数 <2 时显示空态引导（一次评估画不出「进步」）；
// 竖屏下图例两行 + 图面横向铺满。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../config/app_theme.dart';
import '../services/growth_service.dart';
import '../types/display_types.dart';

/// 能力进步曲线（P1-5）
class AbilityProgressChart extends StatelessWidget {
  final List<EvaluationData> history;

  const AbilityProgressChart({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    // 只取带能力快照的评估（旧报告无快照 → 跳过，不编造分数）
    final points = history.where((h) => h.abilityScores.isNotEmpty).toList();
    if (points.length < 2) {
      return _Section(
        title: '能力进步曲线',
        description: '完成两次评估后，这里会展示六大能力随评估轮次的变化趋势',
        child: const _EmptyState(
          icon: Icons.show_chart,
          title: '暂无进步曲线',
          description: '评估报告会记录每次诊断时的能力分数，累积后形成曲线',
        ),
      );
    }

    // 六个维度的分数序列
    final series = <({String dimension, List<int> scores})>[];
    for (final dim in GrowthService.abilityDimensions) {
      final scores = <int>[];
      for (final p in points) {
        for (final a in p.abilityScores) {
          if (a.dimension == dim.label) scores.add(a.score);
        }
      }
      if (scores.isNotEmpty) {
        series.add((dimension: dim.label, scores: scores));
      }
    }

    return _Section(
      title: '能力进步曲线',
      description: '每次评估记录六大能力分数，连线看变化趋势',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChartCanvas(series: series, pointCount: points.length),
          const SizedBox(height: 8),
          _Legend(series: series),
        ],
      ),
    );
  }
}

/// 折线画布（自绘）。
class _ChartCanvas extends StatelessWidget {
  final List<({String dimension, List<int> scores})> series;
  final int pointCount;

  const _ChartCanvas({required this.series, required this.pointCount});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: CustomPaint(
        painter: _CurvePainter(series: series, pointCount: pointCount),
      ),
    );
  }
}

/// 折线 painter（0-100 纵轴，横轴 = 评估点序号）。
class _CurvePainter extends CustomPainter {
  final List<({String dimension, List<int> scores})> series;
  final int pointCount;

  _CurvePainter({required this.series, required this.pointCount});

  static const _colors = [
    Color(0xFF2D5A52),
    Color(0xFF8B5E3C),
    Color(0xFF6B7FD7),
    Color(0xFFB08968),
    Color(0xFF5B8C5A),
    Color(0xFF9A6B9E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final left = 28.0;
    final top = 8.0;
    final bottom = size.height - 8;
    final right = size.width - 8;
    final plotW = right - left;
    final plotH = bottom - top;

    // 网格（25/50/75 分三条浅线）
    final gridPaint = Paint()
      ..color = AppColors.borderSoft
      ..strokeWidth = 1;
    for (final v in [25.0, 50.0, 75.0]) {
      final y = top + plotH * (1 - v / 100);
      canvas.drawLine(Offset(left, y), Offset(right, y), gridPaint);
    }

    for (int si = 0; si < series.length; si++) {
      final scores = series[si].scores;
      if (scores.length < 2) continue;
      final paint = Paint()
        ..color = _colors[si % _colors.length]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < scores.length; i++) {
        final x = left + plotW * i / (pointCount - 1);
        final y = top + plotH * (1 - scores[i].clamp(0, 100) / 100);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) =>
      oldDelegate.pointCount != pointCount ||
      oldDelegate.series.length != series.length;
}

/// 图例（两行六列）。
class _Legend extends StatelessWidget {
  final List<({String dimension, List<int> scores})> series;

  const _Legend({required this.series});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (int i = 0; i < series.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color:
                      _CurvePainter._colors[i % _CurvePainter._colors.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                series[i].dimension,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 区块容器（与成长页其他区块同视觉）。
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// 空态。
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
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
