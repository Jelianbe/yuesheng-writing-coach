// ─────────────────────────────────────────────────────────────
// WritingStatsSheet — 写作统计弹层（批次85-5 写作统计入口）
// 教学特色增补：growth_service 写作曲线数据层 + WritingCurveChart
// 图表 widget 已有雏形（批次51），补写作页内查看入口。
//
// 展示：
//   - 写作成长曲线（近 14 天每日字数 + 诊断次数柱状图）
//   - 摘要行（总字数 / 诊断次数 / 活跃天数）
// 无数据时显示空态引导（多写几天，曲线会自动出现）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../providers/app_providers.dart';
import '../services/growth_service.dart';
import 'writing_curve_chart.dart';
import 'yue_sheet.dart';

class WritingStatsSheet extends ConsumerStatefulWidget {
  const WritingStatsSheet({super.key});

  /// 打开写作统计弹层（批次85-5）
  static Future<void> show(BuildContext context) {
    return showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const WritingStatsSheet(),
    );
  }

  @override
  ConsumerState<WritingStatsSheet> createState() => _WritingStatsSheetState();
}

class _WritingStatsSheetState extends ConsumerState<WritingStatsSheet> {
  List<WritingDataPoint> _points = const [];
  bool _loaded = false;

  /// 批次87-3：统计窗口（近 7/14/30 天），默认 14 天保持原行为
  int _days = 14;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? days}) async {
    final points = await GrowthService(
      ref.read(appDatabaseProvider),
    ).getWritingCurve(days: days ?? _days);
    if (!mounted) return;
    setState(() {
      _points = points;
      _loaded = true;
    });
  }

  void _switchDays(int days) {
    setState(() => _days = days);
    _load(days: days);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Row(
            children: [
              const Text(
                '写作统计',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textInk,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.textTertiary,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 批次87-3：统计窗口切换（近 7/14/30 天）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in const [7, 14, 30]) ...[
                ChoiceChip(
                  label: Text(
                    '近$d天',
                    style: TextStyle(
                      fontSize: 12,
                      color: _days == d
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  selected: _days == d,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.surface,
                  selectedColor: AppColors.primarySoft,
                  side: BorderSide(
                    color: _days == d
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (_) => _switchDays(d),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_points.isEmpty)
            const _StatsEmpty()
          else ...[
            WritingCurveChart(points: _points),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '每天进步一点点，成长看得见。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    ),
  );
  }
}

/// 空态：暂无写作记录
class _StatsEmpty extends StatelessWidget {
  const _StatsEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.trending_up, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '还没有写作记录',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '多写几天，这里会展示你的成长轨迹',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
