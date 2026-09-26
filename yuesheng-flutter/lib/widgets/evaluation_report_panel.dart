// ─────────────────────────────────────────────────────────────
// EvaluationReportPanel — 训练评估报告面板
// 复刻 yuesheng-android/src/components/profile/EvaluationReportPanel.tsx
//
// 结构：
//   1. Header：趋势图标 + 趋势徽章 + 达标率 + 展开/收起箭头
//   2. 详情：训练次数 / 达标率 / 严重度变化 + 趋势文案
//   3. 症候明细（可选，含 E-1 复诊行）+ 关闭按钮
//
// 配色（月色竹青矿物色，对齐 RN success/warning/danger）：
//   improving → 竹青绿 l1Text
//   stable    → 次级灰 textTertiary
//   worsening → 矿物红 l3Text
//
// E-1（复诊闭环）：症候明细行内追加「第 N 次出现 · 较上次 L3 → L2」小字，
//   仅在该症候跨会话复诊时出现（首次出现不渲染）。数据取自
//   SyndromeEvaluationDetail 的复发字段，措辞只陈述真实计数、不给结论。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../types/display_types.dart';
import '../services/syndrome_recurrence.dart';
import 'teaching_state_badge.dart';
import '../theme/app_typography.dart';
import '../config/app_palette.dart';

/// 趋势 → 图标 + 文案 + 配色
({IconData icon, String label, Color color}) _trendConfig(
  BuildContext context,
  EvaluationTrend trend,
) {
  switch (trend) {
    case EvaluationTrend.improving:
      return (
        icon: Icons.trending_up,
        label: '改善',
        color: context.palette.l1Text,
      );
    case EvaluationTrend.stable:
      return (
        icon: Icons.arrow_forward,
        label: '稳定',
        color: context.palette.textTertiary,
      );
    case EvaluationTrend.worsening:
      return (
        icon: Icons.trending_down,
        label: '恶化',
        color: context.palette.l3Text,
      );
  }
}

/// E-1（复诊）：症候行的历史对比小字。
///
/// 仅当该症候此前出现过（[SyndromeEvaluationDetail.isRecurrence]）时返回文案，
/// 否则返回 null（首次出现的症候不加此行）。
///
/// 措辞原则：只陈述真实计数（出现次数 / 严重度对比），不给结论式指令；
/// 「再犯次数」已由报告 summaryText 统一叙述，此处不重复。
String? _recurrenceNoteText(SyndromeEvaluationDetail detail) {
  if (!detail.isRecurrence) return null;
  final prefix = '第 ${detail.occurrences} 次出现';
  final trend = recurrenceSeverityText(
    previousSeverity: detail.previousSeverity?.value,
    currentSeverity: detail.currentSeverity.value,
  );
  return trend.isEmpty ? prefix : '$prefix · $trend';
}

class EvaluationReportPanel extends StatefulWidget {
  final EvaluationData evaluation;

  /// 关闭报告回调
  final VoidCallback? onDismiss;

  /// E1-b②：跳转「成长记录」页回调（null 时不渲染该入口，避免死按钮）
  final VoidCallback? onOpenGrowth;

  const EvaluationReportPanel({
    super.key,
    required this.evaluation,
    this.onDismiss,
    this.onOpenGrowth,
  });

  @override
  State<EvaluationReportPanel> createState() => _EvaluationReportPanelState();
}

class _EvaluationReportPanelState extends State<EvaluationReportPanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final evaluation = widget.evaluation;
    final trend = _trendConfig(context, evaluation.trend);
    final passRatePercent = (evaluation.passRate * 100).round();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, trend, passRatePercent),
          if (_expanded)
            ..._buildDetailSection(context, evaluation, trend, passRatePercent),
        ],
      ),
    );
  }

  /// 顶部：趋势图标 + 趋势徽章 + 达标率 + 展开箭头
  Widget _buildHeader(
    BuildContext context,
    ({IconData icon, String label, Color color}) trend,
    int passRatePercent,
  ) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(trend.icon, size: 22, color: trend.color),
            const SizedBox(width: 10),
            _buildTrendBadge(context, trend),
            const Spacer(),
            Text(
              '达标率 $passRatePercent%',
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 18,
              color: context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  /// 趋势徽章（彩色圆角标签）
  Widget _buildTrendBadge(
    BuildContext context,
    ({IconData icon, String label, Color color}) trend,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smx,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
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
    );
  }

  /// 详情区：统计行 + 达标率进度条 + 趋势文案 + 症候明细 + 动作区
  List<Widget> _buildDetailSection(
    BuildContext context,
    EvaluationData evaluation,
    ({IconData icon, String label, Color color}) trend,
    int passRatePercent,
  ) {
    return [
      Container(height: 1, color: context.palette.borderLight),
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatRow(context, evaluation, passRatePercent),
            const SizedBox(height: 10),
            _buildPassRateBar(context, evaluation, trend),
            const SizedBox(height: 10),
            Text(
              evaluation.summaryText,
              style: context.text.subBody.copyWith(height: 1.5),
            ),
            ..._buildSyndromeDetails(context, evaluation),
            const SizedBox(height: 8),
            _PanelActions(
              onDismiss: widget.onDismiss,
              onOpenGrowth: widget.onOpenGrowth,
            ),
          ],
        ),
      ),
    ];
  }

  /// 统计行：训练次数 / 达标率 / 严重度变化
  Widget _buildStatRow(
    BuildContext context,
    EvaluationData evaluation,
    int passRatePercent,
  ) {
    return Row(
      children: [
        _StatItem(value: '${evaluation.trainingCount}', label: '训练次数'),
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
                ? context.palette.l1Text
                : evaluation.severityDelta! > 0
                ? context.palette.l3Text
                : context.palette.textPrimary,
          ),
        ],
      ],
    );
  }

  /// 达标率进度条
  Widget _buildPassRateBar(
    BuildContext context,
    EvaluationData evaluation,
    ({IconData icon, String label, Color color}) trend,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: LinearProgressIndicator(
        value: evaluation.passRate.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: context.palette.background,
        valueColor: AlwaysStoppedAnimation(trend.color),
      ),
    );
  }

  /// 症候明细列表（非空时渲染标题 + 条目）
  List<Widget> _buildSyndromeDetails(
    BuildContext context,
    EvaluationData evaluation,
  ) {
    if (evaluation.syndromeDetails.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Text(
        '症候明细',
        style: context.text.subBody.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      for (final detail in evaluation.syndromeDetails)
        _SyndromeItem(detail: detail),
    ];
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
              color: valueColor ?? context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: context.text.caption),
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
    return Container(width: 1, height: 30, color: context.palette.border);
  }
}

/// 症候明细条目
class _SyndromeItem extends StatelessWidget {
  final SyndromeEvaluationDetail detail;

  const _SyndromeItem({required this.detail});

  @override
  Widget build(BuildContext context) {
    final trend = _trendConfig(context, detail.trend);
    final note = _recurrenceNoteText(detail);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.smx),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildItemHeader(context, detail, trend),
          const SizedBox(height: 4),
          _buildPassInfo(context, detail),
          // E-1：复诊行（仅跨会话复诊时出现）
          if (note != null) ...[
            const SizedBox(height: 2),
            _RecurrenceNote(text: note),
          ],
        ],
      ),
    );
  }

  /// 条目头部：症候名 + 教学状态徽章 + 趋势标签
  Widget _buildItemHeader(
    BuildContext context,
    SyndromeEvaluationDetail detail,
    ({IconData icon, String label, Color color}) trend,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            detail.syndromeName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
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
    );
  }

  /// 达标 / 严重度信息行
  Widget _buildPassInfo(BuildContext context, SyndromeEvaluationDetail detail) {
    return Text(
      '达标 ${detail.passCount}/${detail.totalCount} · 严重度 ${detail.currentSeverity.value}',
      style: context.text.caption,
    );
  }
}

/// E-1 复诊行：历史对比小字（出现次数 + 严重度对比）。
class _RecurrenceNote extends StatelessWidget {
  final String text;

  const _RecurrenceNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.history, size: 12, color: context.palette.textTertiary),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: context.text.microCaption)),
      ],
    );
  }
}

/// 面板底部动作区（E1-b②）：主入口「查看成长记录」+ 次级「关闭」。
///
/// 从 build 抽出（原内联 19 行），既控制 build 体量，也让入口显隐规则
/// 单点可查：[onOpenGrowth] 为空时整颗按钮不渲染，不留死交互。
class _PanelActions extends StatelessWidget {
  final VoidCallback? onDismiss;
  final VoidCallback? onOpenGrowth;

  const _PanelActions({this.onDismiss, this.onOpenGrowth});

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (onOpenGrowth != null) ...[
            TextButton.icon(
              onPressed: onOpenGrowth,
              icon: const Icon(Icons.insights_outlined, size: 16),
              label: const Text('查看成长记录', style: labelStyle),
              style: TextButton.styleFrom(
                foregroundColor: context.palette.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xsm,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          TextButton(
            onPressed: onDismiss,
            style: TextButton.styleFrom(
              foregroundColor: context.palette.textTertiary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xsm,
              ),
            ),
            child: const Text('关闭', style: labelStyle),
          ),
        ],
      ),
    );
  }
}
