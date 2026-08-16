// ─────────────────────────────────────────────────────────────
// EvaluationReportPanel — 训练评估报告面板
// 复刻 yuesheng-android/src/components/profile/EvaluationReportPanel.tsx
//
// 结构：
//   1. Header：趋势图标 + 趋势徽章 + 达标率 + 展开/收起箭头
//   2. 详情：训练次数 / 达标率 / 严重度变化 + 趋势文案
//   3. 症候明细（可选）+ 关闭按钮
//
// 配色（月色竹青矿物色，对齐 RN success/warning/danger）：
//   improving → 竹青绿 l1Text
//   stable    → 次级灰 textTertiary
//   worsening → 矿物红 l3Text
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../types/display_types.dart';
import 'teaching_state_badge.dart';

/// 趋势 → 图标 + 文案 + 配色
({IconData icon, String label, Color color}) _trendConfig(
  EvaluationTrend trend,
) {
  switch (trend) {
    case EvaluationTrend.improving:
      return (icon: Icons.trending_up, label: '改善', color: AppColors.l1Text);
    case EvaluationTrend.stable:
      return (
        icon: Icons.arrow_forward,
        label: '稳定',
        color: AppColors.textTertiary,
      );
    case EvaluationTrend.worsening:
      return (icon: Icons.trending_down, label: '恶化', color: AppColors.l3Text);
  }
}

class EvaluationReportPanel extends StatefulWidget {
  final EvaluationData evaluation;

  /// 关闭报告回调
  final VoidCallback? onDismiss;

  const EvaluationReportPanel({
    super.key,
    required this.evaluation,
    this.onDismiss,
  });

  @override
  State<EvaluationReportPanel> createState() => _EvaluationReportPanelState();
}

class _EvaluationReportPanelState extends State<EvaluationReportPanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final evaluation = widget.evaluation;
    final trend = _trendConfig(evaluation.trend);
    final passRatePercent = (evaluation.passRate * 100).round();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header：趋势 + 达标率 + 展开 ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(trend.icon, size: 22, color: trend.color),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      trend.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: trend.color,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '达标率 $passRatePercent%',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          // ── 详情 ──
          if (_expanded) ...[
            Container(height: 1, color: AppColors.borderLight),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 统计行：训练次数 / 达标率 / 严重度变化
                  Row(
                    children: [
                      _StatItem(
                        value: '${evaluation.trainingCount}',
                        label: '训练次数',
                      ),
                      const _StatDivider(),
                      _StatItem(value: '$passRatePercent%', label: '达标率'),
                      if (evaluation.severityDelta != null) ...[
                        const _StatDivider(),
                        _StatItem(
                          value: evaluation.severityDelta! > 0
                              ? '+${evaluation.severityDelta}'
                              : '${evaluation.severityDelta}',
                          label: '严重度变化',
                          valueColor: evaluation.severityDelta! < 0
                              ? AppColors.l1Text
                              : evaluation.severityDelta! > 0
                              ? AppColors.l3Text
                              : AppColors.textPrimary,
                        ),
                      ],
                    ],
                  ),
                  // 达标率进度条（批次 42：候选 1 剩余——让学员直观感知达标进度）
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: LinearProgressIndicator(
                      value: evaluation.passRate.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.background,
                      valueColor: AlwaysStoppedAnimation(trend.color),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    evaluation.summaryText,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  // ── 症候明细 ──
                  if (evaluation.syndromeDetails.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '症候明细',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final detail in evaluation.syndromeDetails)
                      _SyndromeItem(detail: detail),
                  ],
                  // ── 关闭 ──
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: widget.onDismiss,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textTertiary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                      ),
                      child: const Text(
                        '关闭',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 统计项（数值 + 标签）
class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const _StatItem({required this.value, required this.label, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 统计分隔线
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: AppColors.border);
  }
}

/// 症候明细条目
class _SyndromeItem extends StatelessWidget {
  final SyndromeEvaluationDetail detail;

  const _SyndromeItem({required this.detail});

  @override
  Widget build(BuildContext context) {
    final trend = _trendConfig(detail.trend);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.syndromeName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // 教学状态徽章（刚识别/训练中/趋稳中/已掌握）——让学员感知阶段迁移
              TeachingStateBadge(
                state: detail.teachingState,
                size: TeachingStateBadgeSize.sm,
                showLabel: true,
              ),
              const SizedBox(width: 8),
              Text(
                trend.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: trend.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '达标 ${detail.passCount}/${detail.totalCount} · 严重度 ${detail.currentSeverity.value}',
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
