// ─────────────────────────────────────────────────────────────
// TrainingPassRateCard — X-041b 训练通过率看板
//
// 数据源：GrowthService.getSyndromeTrainingStats（来自 training_results 表聚合）
// UI 位置：growth_detail_page「症候分布」之后、「同类症候复发率」之前
//
// X-041c 增强：
// - 卡片改为 ConsumerStatefulWidget，内部自管理时间窗状态
// - 标题行右侧 SegmentedButton：7 天 / 30 天 / 全部
// - 切换时调用 growthService.getSyndromeTrainingStats(days: X) 局部刷新
//   不触发 GrowthStore 整体重载（最小侵入）
// - 初始值用 widget.stats（来自 store 加载的近 30 天），避免重复查询
//
// 设计意图：
// - 反映用户在各症候上的练习投入量与掌握程度
// - 作为长期进步曲线的补充维度（与写作曲线/症候趋势并列）
// - 通过率口径：passed=1.0 / partial=0.5 / failed=0.0
//
// 视觉规范（月色竹青，对齐 GrowthDetailPage._Card）：
//   卡片         surface + 左侧 4dp 竹青条 + AppRadius.md 圆角
//   通过率色    ≥80% primary / 50-80% warning / <50% danger
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/training_result_repository.dart';
import '../providers/growth_providers.dart';
import '../services/growth_service.dart';
import '../services/syndrome_registry.dart';

/// 训练通过率看板卡片（X-041c：支持时间窗切换）
class TrainingPassRateCard extends ConsumerStatefulWidget {
  /// 初始 stats（来自 GrowthStore.trainingStats，近 30 天）
  /// 若为空则卡片渲染 SizedBox.shrink
  final List<SyndromeTrainingStats> stats;

  const TrainingPassRateCard({super.key, required this.stats});

  @override
  ConsumerState<TrainingPassRateCard> createState() =>
      _TrainingPassRateCardState();
}

class _TrainingPassRateCardState extends ConsumerState<TrainingPassRateCard> {
  /// 时间窗：7 / 30 / null（全部）。默认 30（与 GrowthStore 一致）
  int? _days = 30;

  /// 当前展示的 stats。初始用 widget.stats，切换后由 service 重新加载
  late List<SyndromeTrainingStats> _stats;

  /// 是否正在加载（切换时间窗时为 true）
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _stats = widget.stats;
  }

  /// 切换时间窗并重新查询
  Future<void> _switchWindow(int? days) async {
    if (days == _days) return;
    setState(() {
      _days = days;
      _loading = true;
    });
    try {
      final service = ref.read(growthServiceProvider);
      final fresh = await service.getSyndromeTrainingStats(days: days);
      if (!mounted) return;
      setState(() {
        _stats = fresh;
        _loading = false;
      });
    } catch (e) {
      // 失败不阻断 UI，保留旧数据 + 控制台日志
      debugPrint('[TrainingPassRateCard] 时间窗切换失败: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 空数据：渲染 SizedBox.shrink（与 X-041b 行为一致）
    if (widget.stats.isEmpty && _stats.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalPractices = _stats.fold<int>(0, (s, r) => s + r.total);
    final totalPassed = _stats.fold<int>(0, (s, r) => s + r.passed);
    final totalPartial = _stats.fold<int>(0, (s, r) => s + r.partial);
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
                      // 标题行：左标题 + 右时间窗切换
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '训练通过率',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          _buildWindowSelector(),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_stats.length} 个症候 · 共 $totalPractices 次练习 · '
                        '整体通过率 ${(overallRate * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        )
                      else if (_stats.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '该时段暂无训练记录',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < _stats.length; i++) ...[
                          _StatsRow(stat: _stats[i]),
                          if (i < _stats.length - 1) const SizedBox(height: 10),
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

  /// 时间窗切换器：7 天 / 30 天 / 全部
  Widget _buildWindowSelector() {
    return SegmentedButton<int?>(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: 7, label: Text('7天')),
        ButtonSegment(value: 30, label: Text('30天')),
        ButtonSegment(value: null, label: Text('全部')),
      ],
      selected: {_days},
      onSelectionChanged: (Set<int?> newSelection) {
        final picked = newSelection.first;
        _switchWindow(picked);
      },
      showSelectedIcon: false,
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
                    style: AppTextStyles.microCaption,
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
