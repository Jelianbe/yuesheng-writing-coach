// ─────────────────────────────────────────────────────────────
// SyndromeDetailModal — 症候详情弹层（缺口清单第 3 项）
// 真源：yuesheng-android/src/components/diagnosis/SyndromeDetailModal.tsx
//
// 结构（对齐 RN）：
//   - 头部：症候名 + 严重度 chip + 关闭按钮
//   - 统计行：出现次数 / 趋势（好转/稳定/加重）/ 首次发现（相对时间）
//   - 趋势变化 section：迷你折线图（CustomPaint 自绘，不引入图表依赖）+ 图例
//   - 诊断记录 section：严重度色点 + 严重度标签 + 相对时间
//
// 数据：SyndromeTracked（由 syndrome_tracker.loadSyndromeTrends 聚合）
// 承载：showModalBottomSheet（RN Modal slide 等价物，点击 barrier 关闭）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/syndrome_tracker.dart';
import '../utils/time_format.dart';

/// 严重度 → 矿物色配置（L1 竹青淡 / L2 矿物黄 / L3 矿物红）
class _SeverityTheme {
  final Color bg;
  final Color fg;
  const _SeverityTheme(this.bg, this.fg);
}

const Map<String, _SeverityTheme> _severityTheme = {
  'L1': _SeverityTheme(AppColors.l1, AppColors.primary),
  'L2': _SeverityTheme(AppColors.l2, AppColors.l2Text),
  'L3': _SeverityTheme(AppColors.l3, AppColors.l3Text),
};

const Map<String, String> _severityLabel = {'L1': '轻微', 'L2': '中等', 'L3': '严重'};

const Map<String, int> _severityScore = {'L1': 1, 'L2': 2, 'L3': 3};

class SyndromeDetailModal extends StatelessWidget {
  final SyndromeTracked syndrome;

  const SyndromeDetailModal({super.key, required this.syndrome});

  _SeverityTheme _sev(String s) =>
      _severityTheme[s] ??
      const _SeverityTheme(AppColors.l1, AppColors.primary);

  /// 趋势 → 主题色（对齐 RN getTrendColor：success/neutral/danger）
  Color _trendColor(String trend) => switch (trend) {
    'improving' => AppColors.primary,
    'worsening' => AppColors.danger,
    _ => AppColors.textTertiary,
  };

  @override
  Widget build(BuildContext context) {
    final sev = _sev(syndrome.currentSeverity);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部拖拽把手（对齐 RN handle）
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.smx),
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              alignment: Alignment.center,
            ),
            // 头部：症候 chip + 关闭
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xs),
              child: Row(
                children: [
                  _buildSyndromeTag(sev),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                    ),
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatsRow(),
                    const SizedBox(height: 8),
                    _buildTrendSection(),
                    const SizedBox(height: 8),
                    _buildRecordsSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 症候名 chip（对齐 RN SyndromeTag）──
  Widget _buildSyndromeTag(_SeverityTheme sev) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xsm),
      decoration: BoxDecoration(
        color: sev.bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: AppSpacing.xsm),
            decoration: BoxDecoration(color: sev.fg, shape: BoxShape.circle),
          ),
          Text(
            syndrome.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: sev.fg,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            syndrome.currentSeverity,
            style: TextStyle(
              fontSize: 12,
              color: sev.fg.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  // ── 统计行：出现次数 / 趋势 / 首次发现（对齐 RN statsRow）──
  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          _buildStatItem(
            value: '${syndrome.occurrenceCount}',
            label: '出现次数',
            color: AppColors.textPrimary,
          ),
          const _StatDivider(),
          _buildStatItem(
            value: getTrendLabel(syndrome.trend),
            label: '趋势',
            color: _trendColor(syndrome.trend),
          ),
          const _StatDivider(),
          _buildStatItem(
            value: formatRelativeTime(syndrome.firstSeen),
            label: '首次发现',
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── 趋势变化 section（对齐 RN chartContainer + legend）──
  Widget _buildTrendSection() {
    final points = syndrome.recentPoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '趋势变化',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.section),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: points.isEmpty
              ? const Center(
                  child: Text(
                    '暂无趋势数据',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.disabledText,
                    ),
                  ),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 64,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _TrendChartPainter(points),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '最近 ${points.length} 次诊断',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.disabledText,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // ── 诊断记录 section（对齐 RN records + recordItem）──
  Widget _buildRecordsSection() {
    final points = syndrome.recentPoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '诊断记录',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        if (points.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Center(
              child: Text(
                '暂无诊断记录',
                style: TextStyle(fontSize: 13, color: AppColors.disabledText),
              ),
            ),
          )
        else
          for (var i = 0; i < points.length; i++)
            _buildRecordItem(points[i], isLast: i == points.length - 1),
      ],
    );
  }

  Widget _buildRecordItem(SyndromeTrendPoint point, {required bool isLast}) {
    final sev = _sev(point.severity);
    final label = _severityLabel[point.severity] ?? point.severity;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.smx),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: AppColors.borderSoft),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: AppSpacing.md),
            decoration: BoxDecoration(
              color: sev.bg,
              shape: BoxShape.circle,
              border: Border.all(color: sev.fg, width: 2),
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            formatRelativeTime(point.timestamp),
            style: const TextStyle(fontSize: 12, color: AppColors.disabledText),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: AppColors.borderLight);
  }
}

/// 迷你趋势折线（复刻 RN MiniTrendChart，不引入第三方依赖）
/// Y 轴：L1(1) 底部 → L3(3) 顶部；X 轴按时间点均分
class _TrendChartPainter extends CustomPainter {
  final List<SyndromeTrendPoint> points;
  const _TrendChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const topPadding = 4.0;
    const bottomPadding = 4.0;
    final chartHeight = size.height - topPadding - bottomPadding;

    double yFor(String severity) {
      final score = _severityScore[severity] ?? 2;
      // L1=1 → 底部，L3=3 → 顶部
      final t = (score - 1) / 2; // 0..1
      return size.height - bottomPadding - t * chartHeight;
    }

    final xs = <double>[];
    final n = points.length;
    for (var i = 0; i < n; i++) {
      xs.add(n == 1 ? size.width / 2 : size.width * i / (n - 1));
    }

    // 网格参考线（L1/L2/L3 三档）
    final gridPaint = Paint()
      ..color = AppColors.borderSoft
      ..strokeWidth = 1;
    for (var s = 1; s <= 3; s++) {
      final y = size.height - bottomPadding - chartHeight * (s - 1) / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 折线
    final linePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (n > 1) {
      final path = Path()..moveTo(xs[0], yFor(points[0].severity));
      for (var i = 1; i < n; i++) {
        path.lineTo(xs[i], yFor(points[i].severity));
      }
      canvas.drawPath(path, linePaint);
    }

    // 数据点（严重度配色）
    for (var i = 0; i < n; i++) {
      final sev =
          _severityTheme[points[i].severity] ??
          const _SeverityTheme(AppColors.l1, AppColors.primary);
      final center = Offset(xs[i], yFor(points[i].severity));
      canvas.drawCircle(center, 5, Paint()..color = sev.fg);
      canvas.drawCircle(
        center,
        5,
        Paint()
          ..color = AppColors.surfaceWhite
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      oldDelegate.points != points;
}
